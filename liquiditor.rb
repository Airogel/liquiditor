# frozen_string_literal: true

require "bundler"

# Disable output buffering for real-time logging in containers
$stdout.sync = true
$stderr.sync = true

Bundler.require

require "active_support/core_ext/object/blank"

require "open3"
require "json"
require "cgi"
require "fileutils"
require "timeout"
require "securerandom"
require "net/http"
require "openssl"
require "uri"

require_relative "lib/shopify/liquid"
require_relative "lib/lng/liquid"
require_relative "lib/database"
require_relative "lib/file_system"

# =============================================================================
# Helpers
# =============================================================================

def theme_path
  theme = ENV["THEME"] || "default"
  theme_root = ENV["THEME_ROOT"]

  if theme_root&.start_with?("/")
    "#{theme_root}/#{theme}"
  else
    "#{__dir__}/themes/#{theme}"
  end
end

def init_template(page_template, template_file)
  tmpl = Liquid::Template.new
  tmpl.assigns["template"] = page_template
  tmpl.registers[:file_system] = FileSystem.new(File.dirname(template_file))
  tmpl
end

def content_for_header(content_path)
  <<~HTML
    <!-- Airogel CMS Reserved -->
    <meta name="content_path" content="#{CGI.escapeHTML(content_path.to_s)}">
    <link rel="stylesheet" href="/cms/cms.css">
    <script type="module" src="/cms/cms.js"></script>
  HTML
end

# =============================================================================
# Main page rendering — mirrors CMS Cms::PagesController
# =============================================================================

def load_path(path)
  puts "Loading path #{path}"

  content_path = Database.find_content_path(path)
  return halt 404, "Page not found" unless content_path

  layout_liquid = content_path[:layout_handle] || "theme"
  template_liquid = content_path[:template_handle] || "index"

  # Build assigns from SQLite
  if content_path[:is_index]
    current_page = (params[:page] || 1).to_i
    current_page = 1 if current_page < 1
    assigns = Database.build_assigns_for_index(content_path, page: current_page)
  else
    assigns = Database.build_assigns_for_entry(content_path)
  end

  # Navigation drop (lazy — queries on access)
  assigns["navigation"] = Extensions::NavigationDrop.new

  # Request context
  assigns["current_page"] = (params[:page] || 1).to_i
  assigns["current_path"] = "/#{path}"

  # Only set "page" as a pagination integer for index pages.
  # For entry pages, "page" may already hold the entry data (when collection_handle is "page").
  if content_path[:is_index]
    assigns["page"] = (params[:page] || 1).to_i
  end

  # Forms config (available as top-level variable for legacy compat)
  assigns["forms"] = load_forms_hash

  file_system = FileSystem.new(File.dirname("#{theme_path}/templates/."))

  # Two-pass rendering: content template → content_for_layout → layout
  template_tmpl = init_template("#{template_liquid}.liquid", "#{theme_path}/templates/.")
  template_tmpl.parse(file_system.read_template_file(template_liquid))

  layout_tmpl = init_template("#{layout_liquid}.liquid", "#{theme_path}/templates/.")
  layout_tmpl.parse(file_system.read_template_file(layout_liquid))

  assigns["content_for_layout"] = template_tmpl.render!(assigns)
  assigns["content_for_header"] = content_for_header(path)
  html = layout_tmpl.render!(assigns)

  # Inject live reload client (long-poll)
  current_v = LIVE_RELOAD_MUTEX.synchronize { LIVE_RELOAD_VERSION[0] }
  livereload_script = <<~HTML
    <script>
    (function() {
      var v = #{current_v};
      function poll() {
        var xhr = new XMLHttpRequest();
        xhr.open('GET', '/livereload?v=' + v, true);
        xhr.responseType = 'json';
        xhr.onload = function() {
          if (xhr.status >= 200 && xhr.status < 300) {
            var d = xhr.response || JSON.parse(xhr.responseText || '{}');
            if (d.changed) {
              // Defer reload if Pi chat is actively streaming
              if (window.__piChatStreaming) {
                window.__piChatPendingReload = true;
                return poll();
              }
              return location.reload();
            }
            if (typeof d.version === 'number') v = d.version;
          }
          poll();
        };
        xhr.onerror = function() { setTimeout(poll, 3000); };
        xhr.send();
      }
      poll();
    })();
    </script>
  HTML
  html.sub("</body>", livereload_script + "</body>")
end

def load_forms_hash
  forms = {}
  Database.connection[:forms].all.each do |row|
    forms[row[:handle]] = Database.find_form(row[:handle])
  end
  forms
end

# =============================================================================
# Pi RPC Session Manager
# =============================================================================

class PiSessionManager
  def initialize(session_dir: "./.pi/sessions", provider: nil, model: nil)
    @session_dir = session_dir
    @provider = provider
    @model = model
    @sessions = {}
    @sessions_mutex = Mutex.new
    FileUtils.mkdir_p(@session_dir)

    # Keep exactly one long-lived pi RPC process and multiplex logical
    # sessions over it via switch_session.
    @rpc_session = PiRpcSession.new("default", @session_dir, provider: @provider, model: @model)
  end

  def get_session(session_id)
    @sessions_mutex.synchronize do
      @sessions[session_id] ||= PiSessionHandle.new(@rpc_session, session_id)
    end
  end

  def cleanup_session(session_id)
    @sessions_mutex.synchronize do
      @sessions.delete(session_id)
    end
  end

  def cleanup_all
    @sessions_mutex.synchronize do
      @sessions.clear
      @rpc_session&.close
      @rpc_session = nil
    end
  end
end

class PiSessionHandle
  def initialize(rpc_session, session_id)
    @rpc_session = rpc_session
    @session_id = sanitize_session_id(session_id)
  end

  def prompt(message, &block)
    @rpc_session.prompt(message, session_id: @session_id, &block)
  end

  def close
    nil
  end
end

def sanitize_session_id(session_id)
  session_id.to_s.gsub(/[^a-zA-Z0-9_-]/, "")
end

class PiRpcSession
  attr_reader :session_id

  def initialize(session_id, session_dir, provider: nil, model: nil)
    @session_id = sanitize_session_id(session_id)
    @session_dir = session_dir
    @session_file = File.join(@session_dir, "#{@session_id}.jsonl")
    @pi_cmd = [ "pi", "--mode", "rpc", "--session-dir", @session_dir ]
    @pi_cmd.push("--provider", provider) if provider
    @pi_cmd.push("--model", model) if model
    @mutex = Mutex.new
    @process = nil
    @request_counter = 0
    @active_session_id = nil
    start_process
  end

  def start_process
    @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(*@pi_cmd)
    @reader_thread = Thread.new { read_output }
    @stderr_thread = Thread.new { drain_stderr }
    @response_queue = {}
    @event_handlers = []
  end

  def drain_stderr
    @stderr.each_line do |line|
      puts "pi[stderr]: #{line.chomp}"
    end
  rescue IOError, Errno::EPIPE
    # Process terminated
  end

  def switch_session(session_id)
    normalized_id = sanitize_session_id(session_id)
    normalized_id = "default" if normalized_id.empty?
    return if @active_session_id == normalized_id

    session_file = File.join(@session_dir, "#{normalized_id}.jsonl")
    send_command({ type: "switch_session", sessionPath: session_file })
    @active_session_id = normalized_id
  end

  def read_output
    @stdout.each_line do |line|
      event = JSON.parse(line)

      if event["type"] == "response" && event["id"]
        request_id = event["id"]
        @mutex.synchronize do
          queue = @response_queue[request_id]
          queue&.push(event)
        end
      else
        @mutex.synchronize do
          @event_handlers.each { |handler| handler.call(event) }
        end
      end
    rescue JSON::ParserError
      puts "Failed to parse pi output: #{line}"
    end
  rescue IOError, Errno::EPIPE
    # Process terminated
  end

  def send_command(command)
    response_queue = Queue.new
    request_id = nil

    @mutex.synchronize do
      request_id = "req-#{@request_counter += 1}"
      command[:id] = request_id
      @response_queue[request_id] = response_queue
    end

    @stdin.puts(command.to_json)
    @stdin.flush

    begin
      Timeout.timeout(30) do
        response_queue.pop
      end
    ensure
      @mutex.synchronize do
        @response_queue.delete(request_id)
      end
    end
  end

  def prompt(message, session_id: nil, &block)
    switch_session(session_id || @session_id)

    response_text = ""
    agent_ended = false
    condition = ConditionVariable.new

    handler = lambda do |event|
      case event["type"]
      when "message_update"
        assistant_event = event["assistantMessageEvent"]
        if assistant_event && assistant_event["type"] == "text_delta"
          chunk = assistant_event["delta"]
          response_text += chunk
          block&.call(chunk)
        end
      when "agent_end", "agent_error", "error"
        agent_ended = true
        condition.signal
      end
    end

    @mutex.synchronize do
      @event_handlers << handler
    end

    begin
      command = { type: "prompt", message: message }
      @stdin.puts(command.to_json)
      @stdin.flush

      @mutex.synchronize do
        deadline = Time.now + 60
        until agent_ended
          remaining = deadline - Time.now
          break if remaining <= 0
          condition.wait(@mutex, remaining)
        end
      end

      response_text
    ensure
      @mutex.synchronize do
        @event_handlers.delete(handler)
      end
    end
  end

  def close
    begin
      @stdin.close
    rescue
      nil
    end
    begin
      @stdout.close
    rescue
      nil
    end
    begin
      @stderr.close
    rescue
      nil
    end
    @reader_thread&.kill
    @stderr_thread&.kill
    begin
      Process.kill("TERM", @wait_thr.pid)
    rescue
      nil
    end
  end
end

# =============================================================================
# Pi Session Log Shipper
# =============================================================================
#
# Reads new lines from each .pi/sessions/*.jsonl file (tracking byte offsets so
# lines are never re-posted) and POSTs them to the Rails /v1/pi_session_logs
# endpoint using the creator instance's API token.
#
# ENV vars consumed:
#   AIROGEL_API_URL  – e.g. https://api.airogelcms.com
#   AIROGEL_API_KEY  – the transient token issued at instance launch
#
# Offset state lives in .pi/sessions/.offsets/<session_id>.offset so it
# survives a Sinatra process restart without re-shipping old lines.

class PiSessionShipper
  SHIP_INTERVAL = 30 # seconds between periodic sweeps

  def initialize(session_dir: "./.pi/sessions")
    @session_dir = session_dir
    @offsets_dir = File.join(session_dir, ".offsets")
    @api_url = ENV["AIROGEL_API_URL"] || "https://api.airogelcms.com"
    @api_key = ENV["AIROGEL_API_KEY"]
    @account_id = ENV["AIROGEL_ACCOUNT_ID"]
    @mutex = Mutex.new
    FileUtils.mkdir_p(@offsets_dir)

    if @api_key
      puts "PiSessionShipper: initialized (api_url=#{@api_url}, session_dir=#{@session_dir})"
    else
      puts "PiSessionShipper: WARNING — AIROGEL_API_KEY not set, log shipping disabled"
    end
  end

  # Ship any unshipped lines across all known session files.
  # Thread-safe — can be called from the periodic thread or at_exit.
  def ship_all
    return unless @api_key

    Dir[File.join(@session_dir, "*.jsonl")].each do |path|
      session_id = File.basename(path, ".jsonl")
      ship_session(session_id, path)
    rescue => e
      puts "PiSessionShipper: error shipping #{session_id}: #{e.message}"
    end
  end

  private

  def ship_session(session_id, path)
    @mutex.synchronize do
      offset = read_offset(session_id)
      file_size = File.size(path)
      return if offset >= file_size

      new_lines = []
      File.open(path, "r") do |f|
        f.seek(offset)
        f.each_line { |line| new_lines << line.chomp unless line.strip.empty? }
        offset = f.pos
      end

      return if new_lines.empty?

      new_lines.each do |line|
        entry = JSON.parse(line)
        post_log(session_id, entry)
      rescue JSON::ParserError => e
        puts "PiSessionShipper: skipping malformed line in #{session_id}: #{e.message}"
      end

      write_offset(session_id, offset)
    end
  end

  def post_log(session_id, data)
    uri = URI("#{@api_url}/v1/pi_session_logs")
    http = Net::HTTP.new(uri.host, uri.port)
    if uri.scheme == "https"
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    end
    http.open_timeout = 5
    http.read_timeout = 10

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{@api_key}"
    request["Content-Type"] = "application/json"
    request.body = { account_id: @account_id, session_id: session_id, data: data }.to_json

    response = http.request(request)
    unless (200..299).cover?(response.code.to_i)
      puts "PiSessionShipper: POST failed (#{response.code}) for #{session_id}: #{response.body}"
    end
  end

  def offset_path(session_id)
    File.join(@offsets_dir, "#{session_id}.offset")
  end

  def read_offset(session_id)
    path = offset_path(session_id)
    File.exist?(path) ? File.read(path).strip.to_i : 0
  end

  def write_offset(session_id, offset)
    File.write(offset_path(session_id), offset.to_s)
  end
end

# =============================================================================
# Sinatra Configuration
# =============================================================================

configure do
  mime_type :css, "text/css"
  mime_type :js, "text/javascript"

  # Allow embedding in iframes from the CMS app
  set :protection, except: :frame_options

  # Sinatra 4.1+ adds HostAuthorization as a separate middleware (not part
  # of the protection stack). Permit all hosts since instances are accessed
  # via dynamic subdomains (*.creator.airogelcms.com) behind an ALB.
  set :host_authorization, permitted_hosts: [], allow_if: ->(_env) { true }
end

before do
  headers "Content-Security-Policy" => "frame-ancestors https://*.airogelcms.com https://app.airogeledit.com https://app.airogelcms.test"
end

# Initialize Pi session manager and log shipper
configure do
  set :pi_session_manager, PiSessionManager.new(
    provider: ENV["PI_PROVIDER"],
    model: ENV["PI_MODEL"]
  )

  shipper = PiSessionShipper.new
  set :pi_session_shipper, shipper

  # Background thread: ship new JSONL lines every 30 seconds
  Thread.new do
    loop do
      sleep PiSessionShipper::SHIP_INTERVAL
      shipper.ship_all
    rescue => e
      puts "PiSessionShipper thread error: #{e.message}"
    end
  end
end

# =============================================================================
# Live Reload
# =============================================================================

LIVE_RELOAD_VERSION = [ 0 ]
LIVE_RELOAD_MUTEX = Mutex.new
LIVE_RELOAD_COND = ConditionVariable.new

configure do
  Thread.new do
    sleep 1 # let server finish booting
    templates_dir = "#{theme_path}/templates"
    assets_dir = "#{theme_path}/assets"

    dirs = [ templates_dir, assets_dir ].select { |d| Dir.exist?(d) }
    if dirs.any?
      puts "Live reload watching: #{dirs.join(", ")}"
      listener = Listen.to(*dirs, force_polling: false) do |modified, added, removed|
        changed = (modified + added + removed).map { |f| File.basename(f) }
        puts "Live reload triggered by: #{changed.join(", ")}"
        LIVE_RELOAD_MUTEX.synchronize do
          LIVE_RELOAD_VERSION[0] += 1
          LIVE_RELOAD_COND.broadcast
        end
      end
      listener.start
      sleep
    else
      puts "Live reload: no directories to watch"
    end
  end
end

get "/livereload" do
  content_type :json
  headers "Cache-Control" => "no-cache"
  client_version = params[:v].to_i

  LIVE_RELOAD_MUTEX.synchronize do
    unless LIVE_RELOAD_VERSION[0] > client_version
      LIVE_RELOAD_COND.wait(LIVE_RELOAD_MUTEX, 25)
    end
  end

  current = LIVE_RELOAD_MUTEX.synchronize { LIVE_RELOAD_VERSION[0] }
  { version: current, changed: current > client_version }.to_json
end

# =============================================================================
# Cleanup
# =============================================================================

at_exit do
  # Flush any unshipped log lines before the pi processes are closed.
  # This ensures all session data reaches the API even on clean shutdown.
  puts "PiSessionShipper: flushing logs before exit..."
  settings.pi_session_shipper.ship_all
  puts "PiSessionShipper: flush complete."

  settings.pi_session_manager.cleanup_all
end

# =============================================================================
# Form Submissions
# =============================================================================

post "/forms/:form_handle/submit" do
  form_handle = params[:form_handle]
  fields = params[:fields] || {}
  redirect_url = params[:redirect_url] || request.referer || "/"
  params[:success_message] || "Thank you for your submission!"
  honeypot_value = params[:website]

  form_config = Database.find_form(form_handle) || {}
  collection = form_config["collection"] || form_handle
  honeypot_enabled = form_config["honeypot_enabled"] || false

  # Honeypot check
  if honeypot_enabled && honeypot_value && !honeypot_value.empty?
    puts "=" * 60
    puts "SPAM DETECTED (Honeypot triggered)"
    puts "=" * 60
    puts "Form: #{form_handle}"
    puts "Timestamp: #{Time.now}"
    puts "=" * 60
    redirect redirect_url
    return
  end

  # Log the submission
  puts "=" * 60
  puts "Form Submission"
  puts "=" * 60
  puts "Form: #{form_handle}"
  puts "Collection: #{collection}"
  puts "Timestamp: #{Time.now}"
  puts "-" * 60
  puts "Fields:"
  fields.each do |key, value|
    puts "  #{key}: #{value}"
  end
  puts "=" * 60

  # Save to SQLite
  begin
    entry_handle = "entry_#{Time.now.to_i}_#{SecureRandom.hex(4)}"
    Database.connection[:entries].insert(
      prefix_id: "cnety_#{SecureRandom.hex(12)}",
      collection_handle: collection,
      handle: entry_handle,
      title: "#{form_config["title"] || form_handle} - #{Time.now.strftime("%B %d, %Y at %I:%M %p")}",
      data: JSON.dump(fields),
      published: false
    )
    puts "Saved form submission as entry: #{entry_handle}"
  rescue => e
    puts "Warning: Could not save form submission: #{e.message}"
  end

  redirect redirect_url
end

# =============================================================================
# Pi Agent API
# =============================================================================

def inspiration_context
  dir = "#{theme_path}/.inspirations"
  return nil unless Dir.exist?(dir)

  files = Dir.entries(dir).reject { |f| f.start_with?(".") }
  return nil if files.empty?

  parts = [ "The user has uploaded the following inspiration/reference files (located in #{dir}):" ]
  files.each do |f|
    full = File.join(dir, f)
    parts << "  - #{f} (#{File.size(full)} bytes, #{Rack::Mime.mime_type(File.extname(f))})"
  end
  parts << "You can read these files for context when the user references them."
  parts.join("\n")
end

post "/api/pi/prompt" do
  content_type :json

  session_id = params[:session_id] || "default"
  prompt = nil

  if request.content_type&.include?("application/json")
    begin
      body = request.body.read
      data = JSON.parse(body)
      prompt = data["prompt"] || data["message"]
      session_id = data["session_id"] || session_id
    rescue JSON::ParserError
      prompt = body unless body.nil? || body.empty?
    end
  end

  prompt ||= params[:prompt]
  halt 400, { error: "No prompt provided" }.to_json if prompt.nil? || prompt.empty?

  context_parts = []
  context_parts << "Active theme directory: #{theme_path}"
  context_parts << "Content path: #{params[:content_path]}" if params[:content_path].present?
  context_parts << "Page URL: #{params[:full_url]}" if params[:full_url].present?
  context_parts << "Page title: #{params[:page_title]}" if params[:page_title].present?
  context_parts << "Path: #{params[:pathname]}" if params[:pathname].present?

  inspiration = inspiration_context
  context_parts << "\n#{inspiration}" if inspiration

  full_prompt = "The user is currently viewing the following page:\n#{context_parts.join("\n")}\n\nUser asks: #{prompt}"

  session = settings.pi_session_manager.get_session(session_id)
  response = session.prompt(full_prompt)

  { response: response, session_id: session_id }.to_json
end

get "/api/pi/stream" do
  content_type "text/event-stream"
  stream :keep_open do |out|
    prompt = params[:prompt]
    session_id = params[:session_id] || "default"

    if prompt.nil? || prompt.empty?
      out << "event: error\n"
      out << "data: No prompt provided\n\n"
      out.close
      next
    end

    context_parts = []
    context_parts << "Active theme directory: #{theme_path}"
    context_parts << "Content path: #{params[:content_path]}" if params[:content_path].present?
    context_parts << "Page URL: #{params[:full_url]}" if params[:full_url].present?
    context_parts << "Page title: #{params[:page_title]}" if params[:page_title].present?
    context_parts << "Path: #{params[:pathname]}" if params[:pathname].present?

    inspiration = inspiration_context
    context_parts << "\n#{inspiration}" if inspiration

    full_prompt = "The user is currently viewing the following page:\n#{context_parts.join("\n")}\n\nUser asks: #{prompt}"

    begin
      session = settings.pi_session_manager.get_session(session_id)

      safe_write = lambda do |data|
        out << data
        true
      rescue
        false
      end

      break unless safe_write.call("event: start\n")
      break unless safe_write.call("data: {\"session_id\":\"#{session_id}\"}\n\n")

      session.prompt(full_prompt) do |chunk|
        escaped_chunk = chunk.gsub("\\", "\\\\").gsub("\n", '\\n').gsub('"', '\\"')
        break unless safe_write.call("data: #{escaped_chunk}\n\n")
      end

      safe_write.call("event: done\n")
      safe_write.call("data: {}\n\n")
    rescue => e
      safe_write = lambda do |data|
        out << data
      rescue
        nil
      end
      safe_write.call("event: error\n")
      safe_write.call("data: #{e.message}\n\n")
    ensure
      begin
        out.close
      rescue
        nil
      end
    end
  end
end

get "/api/pi/sessions" do
  content_type :json

  session_files = Dir["./.pi/sessions/*.jsonl"].map do |file|
    {
      id: File.basename(file, ".jsonl"),
      path: file,
      modified: File.mtime(file).iso8601
    }
  end

  { sessions: session_files }.to_json
end

post "/api/pi/sessions" do
  content_type :json

  session_id = params[:session_id] || SecureRandom.hex(8)
  settings.pi_session_manager.get_session(session_id)

  { session_id: session_id, created: true }.to_json
end

delete "/api/pi/sessions/:session_id" do
  content_type :json
  session_id = sanitize_session_id(params[:session_id])

  settings.pi_session_manager.cleanup_session(session_id)
  session_file = File.join("./.pi/sessions", "#{session_id}.jsonl")
  File.delete(session_file) if File.exist?(session_file)

  { deleted: true }.to_json
end

# =============================================================================
# File Upload API
# =============================================================================

post "/api/uploads" do
  content_type :json

  file = params[:file]
  upload_type = params[:type] || "asset" # "asset" or "inspiration"

  halt 400, { error: "No file provided" }.to_json unless file && file[:tempfile]
  halt 400, { error: "Invalid upload type" }.to_json unless %w[asset inspiration].include?(upload_type)

  filename = file[:filename]
  # Sanitize filename: keep only safe characters
  safe_filename = filename.gsub(/[^\w.\-]/, "_")

  if upload_type == "asset"
    dest_dir = "#{theme_path}/assets"
    FileUtils.mkdir_p(dest_dir)
    dest = File.join(dest_dir, safe_filename)
    FileUtils.cp(file[:tempfile].path, dest)
    FileUtils.chmod(0o644, dest)

    # Trigger live reload so the page picks up new assets
    LIVE_RELOAD_MUTEX.synchronize do
      LIVE_RELOAD_VERSION[0] += 1
      LIVE_RELOAD_COND.broadcast
    end

    puts "Uploaded asset: #{safe_filename}"
    { success: true, type: "asset", filename: safe_filename, path: "/#{safe_filename}" }.to_json
  else
    dest_dir = "#{theme_path}/.inspirations"
    FileUtils.mkdir_p(dest_dir)
    dest = File.join(dest_dir, safe_filename)
    FileUtils.cp(file[:tempfile].path, dest)
    FileUtils.chmod(0o644, dest)

    puts "Uploaded inspiration: #{safe_filename}"
    { success: true, type: "inspiration", filename: safe_filename, path: dest }.to_json
  end
end

get "/api/uploads/inspirations" do
  content_type :json

  dir = "#{theme_path}/.inspirations"
  unless Dir.exist?(dir)
    return { files: [] }.to_json
  end

  files = Dir.entries(dir)
    .reject { |f| f.start_with?(".") }
    .map do |f|
      full = File.join(dir, f)
      {
        filename: f,
        size: File.size(full),
        modified: File.mtime(full).iso8601,
        content_type: Rack::Mime.mime_type(File.extname(f))
      }
    end
    .sort_by { |f| f[:modified] }
    .reverse

  { files: files }.to_json
end

delete "/api/uploads/inspirations/:filename" do
  content_type :json

  filename = params[:filename].gsub(/[^\w.\-]/, "_")
  dir = "#{theme_path}/.inspirations"
  path = File.join(dir, filename)

  halt 404, { error: "File not found" }.to_json unless File.exist?(path)

  File.delete(path)
  puts "Deleted inspiration: #{filename}"
  { success: true, filename: filename }.to_json
end

# =============================================================================
# CMS Asset Routes
# =============================================================================

get "/cms/cms.css" do
  content_type "text/css"
  send_file File.join(__dir__, "public", "cms", "cms.css")
end

get "/cms/cms.js" do
  content_type "application/javascript"
  send_file File.join(__dir__, "public", "cms", "cms.js")
end

# =============================================================================
# Page Routes
# =============================================================================

get "/" do
  load_path("index")
end

get "/*" do
  path = params["splat"].first
  load_path(path)
end

set :static, true
set :public_folder, theme_path + "/assets"

puts "Theme: #{ENV["THEME"]}"
puts "Theme path: #{theme_path}"
