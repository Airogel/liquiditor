# frozen_string_literal: true

require "sequel"
require "json"
require "listen"
require "securerandom"

require_relative "../db/schema"

module Database
  MAX_RESOLVE_DEPTH = 5

  def self.database_path
    theme = ENV["THEME"] || "default"
    theme_root = ENV["THEME_ROOT"] || "themes"

    if theme_root.start_with?("/")
      "#{theme_root}/#{theme}/database.sqlite3"
    else
      File.expand_path("#{theme_root}/#{theme}/database.sqlite3", Dir.pwd)
    end
  end

  def self.connection
    start_file_watcher unless defined?(@@watcher_started) && @@watcher_started
    return @@db if defined?(@@db) && @@db

    @@db = Sequel.sqlite(database_path)
    ensure_schema!
    @@db
  end

  def self.ensure_schema!
    Schema.create!(@@db)
  end

  def self.reset!
    @@db = nil if defined?(@@db)
  end

  # ---------------------------------------------------------------------------
  # Content Path Lookup
  # ---------------------------------------------------------------------------

  def self.find_content_path(path)
    connection[:content_paths].where(path: path).first
  end

  # ---------------------------------------------------------------------------
  # Entry Queries
  # ---------------------------------------------------------------------------

  def self.find_entry(collection_handle, handle)
    row = connection[:entries].where(collection_handle: collection_handle, handle: handle).first
    return nil unless row

    entry_from_row(row)
  end

  def self.find_published_entries(collection_handle, order_by: :published_at, order_dir: :desc, limit: nil)
    ds = connection[:entries]
      .where(collection_handle: collection_handle, published: true)
      .order((order_dir == :asc) ? Sequel.asc(order_by) : Sequel.desc(order_by))

    ds = ds.limit(limit) if limit
    ds.all.map { |row| entry_from_row(row) }
  end

  def self.find_all_entries(collection_handle)
    connection[:entries]
      .where(collection_handle: collection_handle)
      .order(Sequel.asc(:position), Sequel.desc(:published_at))
      .all
      .map { |row| entry_from_row(row) }
  end

  # ---------------------------------------------------------------------------
  # Globals
  # ---------------------------------------------------------------------------

  def self.all_globals
    connection[:globals].all.map do |row|
      global_from_row(row)
    end
  end

  def self.find_global(handle)
    row = connection[:globals].where(handle: handle).first
    return nil unless row

    global_from_row(row)
  end

  def self.global_from_row(row)
    data = JSON.parse(row[:data] || "{}")
    # Merge metadata, but don't overwrite data keys
    # CMS SiteGlobal#to_stache sets "title" => name and "handle" => handle
    # but data fields should take precedence if they exist
    result = { "handle" => row[:handle] }
    result["title"] = row[:name] unless data.key?("title")
    result.merge(data)
  end

  # ---------------------------------------------------------------------------
  # Navigations
  # ---------------------------------------------------------------------------

  def self.find_navigation_items(navigation_handle)
    items = connection[:navigation_items]
      .where(navigation_handle: navigation_handle, parent_id: nil)
      .order(Sequel.asc(:position))
      .all

    items.map { |item| navigation_item_to_hash(item) }
  end

  def self.navigation_item_to_hash(item)
    result = {
      "title" => item[:title],
      "url" => item[:url] || resolve_navigation_entity_url(item),
      "children" => load_navigation_children(item[:id])
    }

    # Merge custom field data
    custom_data = JSON.parse(item[:data] || "{}")
    result.merge(custom_data)
  end

  def self.load_navigation_children(parent_id)
    children = connection[:navigation_items]
      .where(parent_id: parent_id)
      .order(Sequel.asc(:position))
      .all

    children.map { |child| navigation_item_to_hash(child) }
  end

  def self.resolve_navigation_entity_url(item)
    return nil unless item[:collection_handle] && item[:entry_handle]

    cp = connection[:content_paths]
      .where(collection_handle: item[:collection_handle], entry_handle: item[:entry_handle])
      .first
    cp ? "/#{cp[:path]}" : nil
  end

  # ---------------------------------------------------------------------------
  # Forms
  # ---------------------------------------------------------------------------

  def self.find_form(handle)
    row = connection[:forms].where(handle: handle).first
    return nil unless row

    {
      "handle" => row[:handle],
      "title" => row[:title],
      "collection" => row[:collection_handle],
      "blueprint" => row[:blueprint_handle],
      "honeypot_enabled" => row[:honeypot_enabled],
      "redirect_url" => row[:redirect_url],
      "success_message" => row[:success_message],
      "fields" => JSON.parse(row[:fields] || "[]")
    }
  end

  # ---------------------------------------------------------------------------
  # Collections
  # ---------------------------------------------------------------------------

  def self.find_collection(handle)
    connection[:collections].where(handle: handle).first
  end

  # ---------------------------------------------------------------------------
  # Query — used by {% query %} Liquid tag
  # ---------------------------------------------------------------------------

  # Execute a filtered, sorted, paginated query against a collection.
  #
  # @param collection_handle [String]
  # @param field_filters [Array<Hash>] e.g. [{path: 'unit', op: 'eq', value: 'cnety_...'}]
  # @param order_by [Symbol] column or field name (default :published_at)
  # @param order_dir [Symbol] :asc or :desc
  # @param page [Integer]
  # @param per_page [Integer]
  # @param published_only [Boolean]
  # @return [Hash] { items: [...], total:, page:, per_page:, total_pages: }
  #
  def self.query_entries(collection_handle, field_filters: [], order_by: :published_at,
    order_dir: :desc, page: 1, per_page: 25, published_only: true)
    ds = connection[:entries].where(collection_handle: collection_handle)
    ds = ds.where(published: true) if published_only

    # Apply field filters via SQLite json_extract
    field_filters.each do |filter|
      path = filter[:path].to_s
      op = filter[:op].to_s
      value = filter[:value]

      next if path.nil? || path.empty?

      # Resolve prefix_id to {handle, collection} for entity matching
      resolved = resolve_filter_value_for_sqlite(path, value)
      next if resolved.nil?

      case resolved[:type]
      when :entity
        # Locally, entity fields are stored as resolved hashes: {"id": "cnety_...", "handle": "...", "title": "...", "content_path": "..."}
        # The "collection" key is NOT present in the stored data (it was stripped during resolution).
        # Match on the prefix_id stored in the "id" sub-key, which is unique and always present.
        id_expr = Sequel.lit("json_extract(data, ?)", "$.#{path}.id")
        case op
        when "eq"
          ds = ds.where(id_expr => resolved[:prefix_id])
        when "ne"
          ds = ds.exclude(id_expr => resolved[:prefix_id])
        end
      when :scalar
        json_expr = Sequel.lit("json_extract(data, ?)", "$.#{path}")
        case op
        when "eq"
          ds = ds.where(json_expr => resolved[:value].to_s)
        when "ne"
          ds = ds.exclude(json_expr => resolved[:value].to_s)
        when "contains"
          ds = ds.where(Sequel.like(json_expr, "%#{resolved[:value]}%"))
        when "starts_with"
          ds = ds.where(Sequel.like(json_expr, "#{resolved[:value]}%"))
        when "ends_with"
          ds = ds.where(Sequel.like(json_expr, "%#{resolved[:value]}"))
        end
      end
    end

    total = ds.count

    # Sorting
    direct_columns = %i[published_at created_at updated_at title handle position]
    if direct_columns.include?(order_by.to_sym)
      ds = ds.order((order_dir == :asc) ? Sequel.asc(order_by) : Sequel.desc(order_by))
    else
      # Sort by JSON field
      sort_expr = Sequel.lit("json_extract(data, ?)", "$.#{order_by}")
      ds = ds.order((order_dir == :asc) ? Sequel.asc(sort_expr) : Sequel.desc(sort_expr))
    end

    # Pagination
    page = [ page.to_i, 1 ].max
    per_page = per_page.to_i.clamp(1, 100)
    offset = (page - 1) * per_page
    rows = ds.limit(per_page).offset(offset).all

    {
      items: rows.map { |row| entry_from_row(row) },
      total: total,
      page: page,
      per_page: per_page,
      total_pages: [ (total.to_f / per_page).ceil, 1 ].max
    }
  end

  # Resolve a filter value for SQLite JSON matching.
  # Returns nil if the value can't be resolved, otherwise a hash:
  #   { type: :entity, prefix_id: "cnety_..." }  — for entity prefix_id lookups
  #   { type: :scalar, value: "..." }              — for plain value comparison
  #
  # NOTE: Locally, resolved entity hashes stored in SQLite data JSON do NOT include a
  # "collection" key. They look like {"id": "cnety_...", "handle": "...", "title": "...",
  # "content_path": "..."}. Always match on the "id" sub-key (the prefix_id).
  def self.resolve_filter_value_for_sqlite(field_path, value)
    return nil if value.nil? || (value.respond_to?(:empty?) && value.empty?)

    # If value looks like a prefix_id (cnety_...), use it directly for entity matching
    if value.is_a?(String) && value.start_with?("cnety_")
      row = connection[:entries].where(prefix_id: value).first
      return nil unless row
      return { type: :entity, prefix_id: value }
    end

    # If value is a Hash with an "id" key (already a resolved entity drop from Liquid context)
    if value.is_a?(Hash) && value["id"]&.start_with?("cnety_")
      return { type: :entity, prefix_id: value["id"] }
    end

    # Plain scalar
    { type: :scalar, value: value }
  end

  # ---------------------------------------------------------------------------
  # Entry Data Resolution
  # ---------------------------------------------------------------------------

  def self.entry_from_row(row, visited: Set.new, depth: 0)
    data = JSON.parse(row[:data] || "{}")

    entry = {
      "id" => row[:prefix_id],
      "title" => row[:title],
      "handle" => row[:handle],
      "published_at" => row[:published_at],
      "position" => row[:position]
    }

    # Add content_path from content_paths table
    cp = connection[:content_paths]
      .where(collection_handle: row[:collection_handle], entry_handle: row[:handle])
      .first
    entry["content_path"] = "/#{cp[:path]}" if cp

    # Resolve entity references in data
    resolved_data = resolve_data(data, visited: visited, depth: depth, source_id: row[:prefix_id])
    entry.merge(resolved_data)
  end

  def self.resolve_data(data, visited: Set.new, depth: 0, source_id: nil)
    return data unless data.is_a?(Hash)

    resolved = {}
    data.each do |key, value|
      resolved[key] = resolve_value(value, visited: visited, depth: depth, source_id: source_id)
    end
    resolved
  end

  def self.resolve_value(value, visited: Set.new, depth: 0, source_id: nil)
    case value
    when Array
      value.map { |item| resolve_value(item, visited: visited, depth: depth, source_id: source_id) }
    when Hash
      if entity_reference?(value)
        resolve_entity_reference(value, visited: visited, depth: depth)
      else
        resolve_data(value, visited: visited, depth: depth, source_id: source_id)
      end
    else
      value
    end
  end

  def self.entity_reference?(hash)
    hash.is_a?(Hash) && hash.key?("handle") && hash.key?("collection") && hash.keys.length <= 3
  end

  def self.resolve_entity_reference(ref, visited: Set.new, depth: 0)
    return ref if depth >= MAX_RESOLVE_DEPTH

    row = connection[:entries]
      .where(collection_handle: ref["collection"], handle: ref["handle"])
      .first
    return ref unless row
    return { "id" => row[:prefix_id], "title" => row[:title], "handle" => row[:handle], "_visited" => true } if visited.include?(row[:prefix_id])

    entry_from_row(row, visited: visited.dup.add(row[:prefix_id]), depth: depth + 1)
  end

  # ---------------------------------------------------------------------------
  # Build full assigns hash for Liquid rendering
  # ---------------------------------------------------------------------------

  def self.build_assigns_for_entry(content_path_row)
    assigns = {}

    # Load the entry
    entry_row = connection[:entries]
      .where(collection_handle: content_path_row[:collection_handle], handle: content_path_row[:entry_handle])
      .first

    if entry_row
      assigns[content_path_row[:collection_handle]] = entry_from_row(entry_row)
    end

    # Load all globals
    inject_globals(assigns)

    assigns
  end

  def self.build_assigns_for_index(content_path_row, page: 1, per_page: 10)
    assigns = {}

    # Load published entries for the collection
    entries = find_published_entries(content_path_row[:collection_handle])

    # Server-side pagination
    total_entries = entries.size
    total_pages = (total_entries > 0) ? (total_entries.to_f / per_page).ceil : 1
    page = page.clamp(1, total_pages)
    offset = (page - 1) * per_page
    paged_entries = entries.slice(offset, per_page) || []

    assigns[content_path_row[:collection_handle]] = { "entries" => paged_entries }
    assigns["pagination"] = build_pagination(page, total_pages, total_entries, per_page, content_path_row[:path])

    # Load all globals
    inject_globals(assigns)

    assigns
  end

  def self.inject_globals(assigns)
    all_globals.each do |global|
      assigns[global["handle"]] = global
    end
  end

  def self.build_pagination(current_page, total_pages, total_entries, per_page, base_path)
    {
      "page" => current_page,
      "current_page" => current_page,
      "total_pages" => total_pages,
      "total_entries" => total_entries,
      "per_page" => per_page,
      "previous_page" => (current_page > 1) ? current_page - 1 : nil,
      "next_page" => (current_page < total_pages) ? current_page + 1 : nil,
      "has_previous" => current_page > 1,
      "has_next" => current_page < total_pages,
      "previous_url" => (current_page > 1) ? "/#{base_path}/page/#{current_page - 1}" : nil,
      "next_url" => (current_page < total_pages) ? "/#{base_path}/page/#{current_page + 1}" : nil
    }
  end

  # ---------------------------------------------------------------------------
  # File Watcher (invalidate cache on DB changes)
  # ---------------------------------------------------------------------------

  def self.start_file_watcher
    return if (defined?(@@watcher_started) && @@watcher_started) || ENV["RACK_ENV"] == "production"

    @@watcher_started = true
    watch_dir = File.dirname(database_path)

    return unless Dir.exist?(watch_dir)

    puts "Starting database file watcher on: #{watch_dir}"

    Thread.new do
      listener = Listen.to(watch_dir, only: /\.sqlite3$/, force_polling: true) do |modified, added, removed|
        if (modified + added + removed).any? { |file| File.basename(file) == "database.sqlite3" }
          puts "Database file changed, reconnecting..."
          @@db = nil
        end
      end
      listener.start
      loop { sleep 1 }
    end
  end
end
