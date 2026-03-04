#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "json"
require "fileutils"
require "openssl"
require "digest"

class AirogelCmsClient
  # Load environment variables from a theme's .env file
  # Returns a hash with :api_url, :account_id, :api_key
  def self.load_theme_env(theme_path)
    env_file = File.join(theme_path, ".env")

    unless File.exist?(env_file)
      puts "Error: No .env file found at #{env_file}"
      puts "Create one based on themes/.env.example"
      return nil
    end

    env = {}
    File.readlines(env_file).each do |line|
      line = line.strip
      next if line.empty? || line.start_with?("#")

      key, value = line.split("=", 2)
      env[key] = value
    end

    {
      api_url: env["AIROGEL_API_URL"],
      account_id: env["AIROGEL_ACCOUNT_ID"],
      api_key: env["AIROGEL_API_KEY"]
    }
  end

  # Create a client from a theme's .env file
  def self.from_theme(theme_path)
    env = load_theme_env(theme_path)
    return nil unless env

    new(env[:api_url], env[:api_key])
  end
  MIME_TYPES = {
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".png" => "image/png",
    ".gif" => "image/gif",
    ".svg" => "image/svg+xml",
    ".ico" => "image/x-icon",
    ".css" => "text/css",
    ".js" => "application/javascript",
    ".woff" => "font/woff",
    ".woff2" => "font/woff2",
    ".ttf" => "font/ttf",
    ".eot" => "application/vnd.ms-fontobject",
    ".html" => "text/html",
    ".json" => "application/json",
    ".map" => "application/json",
    ".scss" => "text/x-scss"
  }.freeze

  def initialize(base_url, api_token)
    @base_url = base_url
    @api_token = api_token
  end

  def get_accounts
    make_request("/v1/accounts")
  end

  def get_templates(account_id)
    make_request("/v1/accounts/#{account_id}/templates")
  end

  def download_all_templates(account_id, output_dir)
    templates_response = get_templates(account_id)

    if templates_response.is_a?(Hash) && templates_response["error"]
      puts "Error fetching templates: #{templates_response["error"]}"
      return
    end

    templates = templates_response.is_a?(Array) ? templates_response : (templates_response["templates"] || [])
    FileUtils.mkdir_p(output_dir)

    templates.each do |template|
      # Use handle for path structure (e.g., "pages/about" -> "pages/about.liquid")
      handle = template["handle"] || template["name"] || "template_#{template["id"]}"
      filename = "#{handle}.liquid"
      content = template["html"] || template["content"] || template["body"] || ""

      file_path = File.join(output_dir, filename)
      FileUtils.mkdir_p(File.dirname(file_path))
      File.write(file_path, content)

      puts "Downloaded: #{filename}"
    end

    puts "Downloaded #{templates.size} templates to #{output_dir}"
  end

  def download_all_assets(account_id, output_dir)
    puts "Fetching assets list..."
    assets_response = get_assets(account_id)

    if assets_response.is_a?(Hash) && assets_response["error"]
      puts "Error fetching assets: #{assets_response["error"]}"
      return
    end

    assets = assets_response.is_a?(Array) ? assets_response : (assets_response["assets"] || [])

    if assets.empty?
      puts "No assets found"
      return
    end

    puts "Found #{assets.size} assets"
    puts

    FileUtils.mkdir_p(output_dir)
    downloaded = 0
    errors = 0

    assets.each do |asset|
      asset_url = asset["url"]
      filename = asset["filename"]
      path = asset["path"] || ""

      # Skip assets without a filename
      if filename.nil? || filename.empty?
        puts "⊘ Skipping asset with missing filename (id: #{asset["id"]})"
        next
      end

      # Build the full local path
      local_path = path.empty? ? File.join(output_dir, filename) : File.join(output_dir, path, filename)
      display_name = path.empty? ? filename : "#{path}/#{filename}"

      begin
        # Create subdirectories if needed
        FileUtils.mkdir_p(File.dirname(local_path))

        # Download the asset - need to construct full URL and follow redirects
        uri = URI.join(@base_url, asset_url)

        # Follow redirects (max 5)
        redirect_count = 0
        max_redirects = 5

        loop do
          http = build_http(uri)

          request = Net::HTTP::Get.new(uri.request_uri)
          response = http.request(request)

          case response
          when Net::HTTPSuccess
            File.binwrite(local_path, response.body)
            puts "✓ Downloaded: #{display_name}"
            downloaded += 1
            break
          when Net::HTTPRedirection
            redirect_count += 1
            if redirect_count > max_redirects
              puts "✗ Error downloading #{display_name}: Too many redirects"
              errors += 1
              break
            end
            uri = URI(response["location"])
          else
            puts "✗ Error downloading #{display_name}: HTTP #{response.code}"
            errors += 1
            break
          end
        end
      rescue => e
        puts "✗ Error downloading #{display_name}: #{e.message}"
        errors += 1
      end
    end

    puts
    puts "Downloaded #{downloaded} assets to #{output_dir}"
    puts "Errors: #{errors}" if errors > 0
  end

  # Template CRUD methods

  def create_template(account_id, title:, handle:, html:)
    make_post_request(
      "/v1/accounts/#{account_id}/templates",
      { template: { title: title, handle: handle, html: html } }
    )
  end

  def update_template(account_id, template_id, html:)
    make_put_request(
      "/v1/accounts/#{account_id}/templates/#{template_id}",
      { template: { html: html } }
    )
  end

  def delete_template(account_id, template_id)
    make_delete_request("/v1/accounts/#{account_id}/templates/#{template_id}")
  end

  # Asset CRUD methods

  def get_assets(account_id)
    make_request("/v1/accounts/#{account_id}/assets")
  end

  def create_asset(account_id, file_path, path:)
    make_multipart_request(
      "/v1/accounts/#{account_id}/assets",
      file_path,
      { path: path }
    )
  end

  def update_asset(account_id, asset_id, file_path)
    make_multipart_put_request(
      "/v1/accounts/#{account_id}/assets/#{asset_id}",
      file_path
    )
  end

  def delete_asset(account_id, asset_id)
    make_delete_request("/v1/accounts/#{account_id}/assets/#{asset_id}")
  end

  # ============================================================
  # Collections API
  # ============================================================

  def get_collections(account_id, page: 1, per_page: 25)
    make_request("/v1/accounts/#{account_id}/collections?page=#{page}&per_page=#{per_page}")
  end

  def get_collection(account_id, collection_id)
    make_request("/v1/accounts/#{account_id}/collections/#{collection_id}")
  end

  def create_collection(account_id, name:, handle:, **options)
    body = {
      collection: {
        name: name,
        handle: handle
      }.merge(options)
    }
    make_post_request("/v1/accounts/#{account_id}/collections", body)
  end

  def update_collection(account_id, collection_id, **attributes)
    make_put_request(
      "/v1/accounts/#{account_id}/collections/#{collection_id}",
      { collection: attributes }
    )
  end

  def delete_collection(account_id, collection_id)
    make_delete_request("/v1/accounts/#{account_id}/collections/#{collection_id}")
  end

  # ============================================================
  # Collection Entries API
  # ============================================================

  def get_entries(account_id, collection_id, page: 1, per_page: 25)
    make_request("/v1/accounts/#{account_id}/collections/#{collection_id}/entries?page=#{page}&per_page=#{per_page}")
  end

  def get_entry(account_id, collection_id, entry_id)
    make_request("/v1/accounts/#{account_id}/collections/#{collection_id}/entries/#{entry_id}")
  end

  def create_entry(account_id, collection_id, **fields)
    make_post_request(
      "/v1/accounts/#{account_id}/collections/#{collection_id}/entries",
      { entry: fields }
    )
  end

  def update_entry(account_id, collection_id, entry_id, **fields)
    make_put_request(
      "/v1/accounts/#{account_id}/collections/#{collection_id}/entries/#{entry_id}",
      { entry: fields }
    )
  end

  def delete_entry(account_id, collection_id, entry_id)
    make_delete_request("/v1/accounts/#{account_id}/collections/#{collection_id}/entries/#{entry_id}")
  end

  # ============================================================
  # Blueprints API
  # ============================================================

  def get_blueprints(account_id, page: 1, per_page: 25)
    make_request("/v1/accounts/#{account_id}/blueprints?page=#{page}&per_page=#{per_page}")
  end

  def get_blueprint(account_id, blueprint_id)
    make_request("/v1/accounts/#{account_id}/blueprints/#{blueprint_id}")
  end

  def create_blueprint(account_id, handle:, title:, fields: [])
    make_post_request(
      "/v1/accounts/#{account_id}/blueprints",
      { blueprint: { handle: handle, title: title, fields: fields } }
    )
  end

  def update_blueprint(account_id, blueprint_id, **attributes)
    make_put_request(
      "/v1/accounts/#{account_id}/blueprints/#{blueprint_id}",
      { blueprint: attributes }
    )
  end

  def delete_blueprint(account_id, blueprint_id)
    make_delete_request("/v1/accounts/#{account_id}/blueprints/#{blueprint_id}")
  end

  # ============================================================
  # Navigations API
  # ============================================================

  def get_navigations(account_id, page: 1, per_page: 25)
    make_request("/v1/accounts/#{account_id}/navigations?page=#{page}&per_page=#{per_page}")
  end

  def get_navigation(account_id, navigation_id)
    make_request("/v1/accounts/#{account_id}/navigations/#{navigation_id}")
  end

  def create_navigation(account_id, handle:, title:, items: [])
    make_post_request(
      "/v1/accounts/#{account_id}/navigations",
      { navigation: { handle: handle, title: title, items: items } }
    )
  end

  def update_navigation(account_id, navigation_id, **attributes)
    make_put_request(
      "/v1/accounts/#{account_id}/navigations/#{navigation_id}",
      { navigation: attributes }
    )
  end

  def delete_navigation(account_id, navigation_id)
    make_delete_request("/v1/accounts/#{account_id}/navigations/#{navigation_id}")
  end

  # ============================================================
  # Navigation Items API
  # ============================================================

  def get_navigation_items(account_id, navigation_id)
    make_request("/v1/accounts/#{account_id}/navigations/#{navigation_id}/items")
  end

  def create_navigation_item(account_id, navigation_id, **fields)
    make_post_request(
      "/v1/accounts/#{account_id}/navigations/#{navigation_id}/items",
      { item: fields }
    )
  end

  def update_navigation_item(account_id, navigation_id, item_id, **fields)
    make_put_request(
      "/v1/accounts/#{account_id}/navigations/#{navigation_id}/items/#{item_id}",
      { item: fields }
    )
  end

  def delete_navigation_item(account_id, navigation_id, item_id)
    make_delete_request("/v1/accounts/#{account_id}/navigations/#{navigation_id}/items/#{item_id}")
  end

  # ============================================================
  # Globals API
  # ============================================================

  def get_globals(account_id, page: 1, per_page: 25)
    make_request("/v1/accounts/#{account_id}/globals?page=#{page}&per_page=#{per_page}")
  end

  def get_global(account_id, global_id)
    make_request("/v1/accounts/#{account_id}/globals/#{global_id}")
  end

  def create_global(account_id, handle:, title:, **fields)
    make_post_request(
      "/v1/accounts/#{account_id}/globals",
      { global: { handle: handle, title: title }.merge(fields) }
    )
  end

  def update_global(account_id, global_id, **fields)
    make_put_request(
      "/v1/accounts/#{account_id}/globals/#{global_id}",
      { global: fields }
    )
  end

  def delete_global(account_id, global_id)
    make_delete_request("/v1/accounts/#{account_id}/globals/#{global_id}")
  end

  # Export methods

  def get_export(account_id, format: :yaml)
    endpoint = "/v1/accounts/#{account_id}/export.#{format}"
    make_raw_request(endpoint)
  end

  def download_database(account_id, output_path)
    puts "Downloading database export..."

    # Remove existing database.yml before downloading fresh copy
    if File.exist?(output_path)
      FileUtils.rm(output_path)
    end

    result = get_export(account_id, format: :yaml)

    if result[:error]
      puts "✗ Error downloading export: #{result[:error]}"
      return false
    end

    File.write(output_path, result[:body])
    puts "✓ Downloaded database to #{output_path}"
    true
  end

  def download_theme(account_id, theme_path)
    puts "Downloading theme to #{theme_path}..."
    puts

    FileUtils.mkdir_p(theme_path)

    # Download database.yml
    database_path = File.join(theme_path, "database.yml")
    download_database(account_id, database_path)

    # Download templates
    puts
    templates_dir = File.join(theme_path, "templates")
    download_all_templates(account_id, templates_dir)

    # Download assets
    puts
    assets_dir = File.join(theme_path, "assets")
    download_all_assets(account_id, assets_dir)

    puts
    puts "Theme downloaded to #{theme_path}"
  end

  # Theme upload methods

  def upload_theme(account_id, theme_path)
    templates_dir = File.join(theme_path, "templates")
    assets_dir = File.join(theme_path, "assets")

    puts "Uploading theme from #{theme_path}..."
    puts

    template_stats = upload_templates(account_id, templates_dir)
    puts
    asset_stats = upload_assets(account_id, assets_dir)

    puts
    puts "=" * 60
    puts "Summary: #{template_stats[:total]} templates (#{template_stats[:created]} created, #{template_stats[:updated]} updated, #{template_stats[:errors]} errors)"
    skipped_info = (asset_stats[:skipped] > 0) ? ", #{asset_stats[:skipped]} skipped" : ""
    puts "         #{asset_stats[:total]} assets (#{asset_stats[:created]} created, #{asset_stats[:updated]} updated#{skipped_info}, #{asset_stats[:errors]} errors)"
    puts "=" * 60

    { templates: template_stats, assets: asset_stats }
  end

  def upload_templates(account_id, templates_dir)
    stats = { total: 0, created: 0, updated: 0, errors: 0 }

    unless Dir.exist?(templates_dir)
      puts "Templates directory not found: #{templates_dir}"
      return stats
    end

    # Fetch existing templates
    puts "Fetching existing templates..."
    existing = get_templates(account_id)

    if existing.is_a?(Hash) && existing["error"]
      puts "Error fetching templates: #{existing["error"]}"
      return stats
    end

    templates_list = existing.is_a?(Array) ? existing : (existing["templates"] || [])
    existing_by_handle = templates_list.to_h { |t| [ t["handle"], t ] }
    puts "Found #{existing_by_handle.size} existing templates"
    puts

    # Find all .liquid files
    files = Dir.glob(File.join(templates_dir, "**", "*.liquid"))
    puts "Uploading #{files.size} templates..."

    files.each do |file_path|
      stats[:total] += 1
      handle = derive_handle(file_path, templates_dir)
      title = File.basename(file_path)
      html = File.read(file_path)

      begin
        if existing_by_handle[handle]
          # Update existing template
          template_id = existing_by_handle[handle]["id"] || existing_by_handle[handle]["prefix_id"]
          result = update_template(account_id, template_id, html: html)
          if result["error"] || result["errors"]
            error_msg = result["error"] || result["errors"]
            puts "✗ Error updating #{handle}: #{error_msg}"
            stats[:errors] += 1
          else
            puts "✓ Updated template: #{handle}"
            stats[:updated] += 1
          end
        else
          # Create new template
          result = create_template(account_id, title: title, handle: handle, html: html)
          if result["error"] || result["errors"]
            error_msg = result["error"] || result["errors"]
            puts "✗ Error creating #{handle}: #{error_msg}"
            stats[:errors] += 1
          else
            puts "✓ Created template: #{handle}"
            stats[:created] += 1
          end
        end
      rescue => e
        puts "✗ Error uploading #{handle}: #{e.message}"
        stats[:errors] += 1
      end
    end

    stats
  end

  def upload_assets(account_id, assets_dir, skip_unchanged: true)
    stats = { total: 0, created: 0, updated: 0, skipped: 0, errors: 0 }

    unless Dir.exist?(assets_dir)
      puts "Assets directory not found: #{assets_dir}"
      return stats
    end

    # Fetch existing assets
    puts "Fetching existing assets..."
    existing = get_assets(account_id)

    if existing.is_a?(Hash) && existing["error"]
      puts "⚠ Error fetching assets: #{existing["error"]}"
      puts "⚠ This may be due to corrupted assets on the server. Continuing with upload (all files will be created as new)..."
      existing_by_full_path = {}
    else
      assets_list = existing.is_a?(Array) ? existing : (existing["assets"] || [])
      # Build lookup key from path + filename (e.g., "fonts/flaticon.woff" or "application.css")
      # Skip assets with nil filenames to avoid errors
      existing_by_full_path = assets_list.compact.select { |a| a["filename"] }.to_h do |a|
        full_path = a["path"].to_s.empty? ? a["filename"] : "#{a["path"]}/#{a["filename"]}"
        [ full_path, a ]
      end
      puts "Found #{existing_by_full_path.size} existing assets"
    end
    puts

    # Find all files (not directories)
    files = Dir.glob(File.join(assets_dir, "**", "*")).select { |f| File.file?(f) }
    puts "Uploading #{files.size} assets..."

    files.each do |file_path|
      stats[:total] += 1
      filename = File.basename(file_path)
      path = derive_asset_path(file_path, assets_dir)
      # Build the same lookup key for matching
      full_path = path.empty? ? filename : "#{path}/#{filename}"
      display_name = full_path

      begin
        if existing_by_full_path[full_path]
          existing_asset = existing_by_full_path[full_path]

          # Skip if unchanged (compare Base64-encoded MD5 checksums)
          if skip_unchanged && existing_asset["checksum"]
            local_checksum = Digest::MD5.base64digest(File.binread(file_path))
            if local_checksum == existing_asset["checksum"]
              puts "⊘ Skipped (unchanged): #{display_name}"
              stats[:skipped] += 1
              next
            end
          end

          # Update existing asset
          asset_id = existing_asset["id"] || existing_asset["prefix_id"]
          result = update_asset(account_id, asset_id, file_path)
          if result["error"] || result["errors"]
            error_msg = result["error"] || result["errors"]
            puts "✗ Error updating #{display_name}: #{error_msg}"
            stats[:errors] += 1
          else
            puts "✓ Updated asset: #{display_name}"
            stats[:updated] += 1
          end
        else
          # Create new asset
          result = create_asset(account_id, file_path, path: path)
          if result["error"] || result["errors"]
            error_msg = result["error"] || result["errors"]
            puts "✗ Error creating #{display_name}: #{error_msg}"
            stats[:errors] += 1
          else
            puts "✓ Uploaded asset: #{display_name}"
            stats[:created] += 1
          end
        end
      rescue => e
        puts "✗ Error uploading #{display_name}: #{e.message}"
        stats[:errors] += 1
      end
    end

    stats
  end

  private

  def derive_handle(file_path, templates_dir)
    relative = file_path.sub("#{templates_dir}/", "")
    relative.sub(/\.liquid$/, "")
  end

  def derive_asset_path(file_path, assets_dir)
    relative = file_path.sub("#{assets_dir}/", "")
    # Return just the directory path, not the filename
    dir = File.dirname(relative)
    (dir == ".") ? "" : dir
  end

  def make_request(endpoint)
    uri = URI("#{@base_url}#{endpoint}")
    http = build_http(uri)

    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{@api_token}"
    request["Content-Type"] = "application/json"

    response = http.request(request)

    if response.code.to_i >= 200 && response.code.to_i < 300
      JSON.parse(response.body)
    else
      { "error" => "HTTP #{response.code}: #{response.body}" }
    end
  rescue => e
    { "error" => e.message }
  end

  def make_raw_request(endpoint)
    uri = URI("#{@base_url}#{endpoint}")
    http = build_http(uri)

    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{@api_token}"

    response = http.request(request)

    if response.code.to_i >= 200 && response.code.to_i < 300
      { body: response.body.force_encoding("UTF-8") }
    else
      { error: "HTTP #{response.code}: #{response.body.force_encoding("UTF-8")}" }
    end
  rescue => e
    { error: e.message }
  end

  def make_post_request(endpoint, body)
    uri = URI("#{@base_url}#{endpoint}")
    http = build_http(uri)

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{@api_token}"
    request["Content-Type"] = "application/json"
    request.body = body.to_json

    response = http.request(request)

    if response.code.to_i >= 200 && response.code.to_i < 300
      JSON.parse(response.body)
    else
      { "error" => "HTTP #{response.code}: #{response.body}" }
    end
  rescue => e
    { "error" => e.message }
  end

  def make_put_request(endpoint, body)
    uri = URI("#{@base_url}#{endpoint}")
    http = build_http(uri)

    request = Net::HTTP::Put.new(uri)
    request["Authorization"] = "Bearer #{@api_token}"
    request["Content-Type"] = "application/json"
    request.body = body.to_json

    response = http.request(request)

    if response.code.to_i >= 200 && response.code.to_i < 300
      JSON.parse(response.body)
    else
      { "error" => "HTTP #{response.code}: #{response.body}" }
    end
  rescue => e
    { "error" => e.message }
  end

  def make_delete_request(endpoint)
    uri = URI("#{@base_url}#{endpoint}")
    http = build_http(uri)

    request = Net::HTTP::Delete.new(uri)
    request["Authorization"] = "Bearer #{@api_token}"

    response = http.request(request)

    if response.code.to_i >= 200 && response.code.to_i < 300
      response.body.empty? ? {} : JSON.parse(response.body)
    else
      { "error" => "HTTP #{response.code}: #{response.body}" }
    end
  rescue => e
    { "error" => e.message }
  end

  def make_multipart_request(endpoint, file_path, params = {})
    uri = URI("#{@base_url}#{endpoint}")
    http = build_http(uri)

    boundary = "----RubyMultipartPost#{rand(1_000_000)}"
    filename = File.basename(file_path)
    content_type = content_type_for(filename)

    body = []
    body << "--#{boundary}\r\n"
    body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n"
    body << "Content-Type: #{content_type}\r\n\r\n"
    body << File.binread(file_path)
    body << "\r\n"

    params.each do |key, value|
      body << "--#{boundary}\r\n"
      body << "Content-Disposition: form-data; name=\"#{key}\"\r\n\r\n"
      body << value.to_s
      body << "\r\n"
    end

    body << "--#{boundary}--\r\n"

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{@api_token}"
    request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
    request.body = body.join

    response = http.request(request)

    if response.code.to_i >= 200 && response.code.to_i < 300
      JSON.parse(response.body)
    else
      { "error" => "HTTP #{response.code}: #{response.body}" }
    end
  rescue => e
    { "error" => e.message }
  end

  def make_multipart_put_request(endpoint, file_path, params = {})
    uri = URI("#{@base_url}#{endpoint}")
    http = build_http(uri)

    boundary = "----RubyMultipartPost#{rand(1_000_000)}"
    filename = File.basename(file_path)
    content_type = content_type_for(filename)

    body = []
    body << "--#{boundary}\r\n"
    body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n"
    body << "Content-Type: #{content_type}\r\n\r\n"
    body << File.binread(file_path)
    body << "\r\n"

    params.each do |key, value|
      body << "--#{boundary}\r\n"
      body << "Content-Disposition: form-data; name=\"#{key}\"\r\n\r\n"
      body << value.to_s
      body << "\r\n"
    end

    body << "--#{boundary}--\r\n"

    request = Net::HTTP::Put.new(uri)
    request["Authorization"] = "Bearer #{@api_token}"
    request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
    request.body = body.join

    response = http.request(request)

    if response.code.to_i >= 200 && response.code.to_i < 300
      JSON.parse(response.body)
    else
      { "error" => "HTTP #{response.code}: #{response.body}" }
    end
  rescue => e
    { "error" => e.message }
  end

  def content_type_for(filename)
    ext = File.extname(filename).downcase
    MIME_TYPES[ext] || "application/octet-stream"
  end

  def build_http(uri)
    http = Net::HTTP.new(uri.host, uri.port)

    if uri.scheme == "https"
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    end

    http
  end
end

# Usage examples:
#
# # ============================================================
# # Option 1: Load from theme's .env file (RECOMMENDED)
# # ============================================================
# # First, create a .env file in your theme directory:
# #   cp themes/.env.example themes/jbsite/.env
# #   # Then edit themes/jbsite/.env with your credentials
# #
# theme_path = './themes/jbsite'
# env = AirogelCmsClient.load_theme_env(theme_path)
# client = AirogelCmsClient.new(env[:api_url], env[:api_key])
# account_id = env[:account_id]
#
# # Or use the convenience method:
# client = AirogelCmsClient.from_theme('./themes/jbsite')
# env = AirogelCmsClient.load_theme_env('./themes/jbsite')
# account_id = env[:account_id]
#
# # ============================================================
# # Option 2: Initialize manually
# # ============================================================
# # client = AirogelCmsClient.new('https://api.airogelcms.com', 'your_api_key')
# # account_id = 'acct_xxx'
#
# # ============================================================
# # Common operations
# # ============================================================
#
# # Get all accounts
# accounts = client.get_accounts
# puts 'Available accounts:'
# accounts.each { |account| puts "- #{account['id']}: #{account['name']}" }
#
# # Download database.yml (backs up existing with timestamp)
# client.download_database(account_id, "#{theme_path}/database.yml")
#
# # Download entire theme (database + templates + assets)
# client.download_theme(account_id, theme_path)
#
# # Download just templates
# client.download_all_templates(account_id, "#{theme_path}/templates")
#
# # Download just assets
# client.download_all_assets(account_id, "#{theme_path}/assets")
#
# # Upload an entire theme
# client.upload_theme(account_id, theme_path)
#
# # Upload just templates
# client.upload_templates(account_id, "#{theme_path}/templates")
#
# # Upload just assets
# client.upload_assets(account_id, "#{theme_path}/assets")
#
# # Individual template operations
# client.create_template(account_id, title: 'header.liquid', handle: 'header', html: '...')
# client.update_template(account_id, 'tmpl_xxx', html: '...')
# client.delete_template(account_id, 'tmpl_xxx')
#
# # Individual asset operations
# client.get_assets(account_id)
# client.create_asset(account_id, './path/to/file.png', path: 'images')
# client.update_asset(account_id, 'asset_xxx', './path/to/file.png')
# client.delete_asset(account_id, 'asset_xxx')
