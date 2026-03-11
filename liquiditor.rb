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

  # Inject live reload client (SSE)
  current_v = LIVE_RELOAD_MUTEX.synchronize { LIVE_RELOAD_VERSION[0] }
  livereload_script = <<~HTML
    <script>
    (function() {
      var v = #{current_v};
      var es = null;
      function connect() {
        es = new EventSource('/livereload?v=' + v);
        es.addEventListener('reload', function(e) {
          var d = JSON.parse(e.data || '{}');
          if (typeof d.version === 'number') v = d.version;
          // Defer reload if Pi chat is actively streaming
          if (window.__piChatStreaming) {
            window.__piChatPendingReload = true;
          } else {
            location.reload();
          }
        });
        es.onerror = function() {
          es.close();
          es = null;
          setTimeout(connect, 3000);
        };
      }
      // Close the SSE connection when leaving the page so the server-side
      // thread is released immediately instead of waiting for the next
      // keepalive write to detect the dead socket (up to 25s later).
      window.addEventListener('pagehide', function() {
        if (es) { es.close(); es = null; }
      });
      connect();
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

def sanitize_session_id(session_id)
  session_id.to_s.gsub(/[^a-zA-Z0-9_-]/, "")
end

# PiDaemon owns the single long-running `pi --mode rpc` process.
#
# Responsibilities:
#   - Spawn and own the process (stdin/stdout/stderr pipes)
#   - Read all output lines and route them:
#       * "response" messages (with an "id") → per-request Queue registered via register_response_queue
#       * all other events                   → broadcast to registered event handlers
#   - Restart the process automatically if it exits (with exponential back-off)
#   - Provide send_line(json_string) for callers to write a command
#
# It does NOT know about sessions, prompts, or the RPC protocol above raw JSON.
class PiDaemon
  MAX_RESTART_DELAY = 30 # seconds

  def initialize(session_dir:, provider: nil, model: nil)
    @session_dir = session_dir
    @pi_cmd = [ "pi", "--mode", "rpc", "--session-dir", session_dir ]
    @pi_cmd.push("--provider", provider) if provider
    @pi_cmd.push("--model", model) if model

    @mutex = Mutex.new
    @write_mutex = Mutex.new
    @response_queues = {}  # request_id => Queue
    @event_handlers = {}  # handler_id => callable

    @stopped = false
    @restart_delay = 1

    start_process
  end

  # Register a handler that receives all non-response events while the block
  # runs. The handler is removed when the block returns or raises.
  def with_event_handler(handler_id, callable)
    @mutex.synchronize { @event_handlers[handler_id] = callable }
    yield
  ensure
    @mutex.synchronize { @event_handlers.delete(handler_id) }
  end

  # Register a response Queue for a specific request id before sending the
  # command; unregister it in ensure. Returns the queue.
  def register_response_queue(request_id)
    q = Queue.new
    @mutex.synchronize { @response_queues[request_id] = q }
    q
  end

  def unregister_response_queue(request_id)
    @mutex.synchronize { @response_queues.delete(request_id) }
  end

  # Write a raw JSON line to the daemon's stdin. Thread-safe.
  def send_line(json)
    @write_mutex.synchronize do
      @stdin.puts(json)
      @stdin.flush
    end
  rescue IOError, Errno::EPIPE => e
    puts "PiDaemon: send_line failed (#{e.class}: #{e.message}) — process may be restarting"
  end

  def stop
    @stopped = true
    close_process
  end

  private

  def start_process
    @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(*@pi_cmd)
    puts "PiDaemon: started pi process (pid=#{@wait_thr.pid})"
    @restart_delay = 1
    @reader_thread = Thread.new { read_loop }
    @stderr_thread = Thread.new { drain_stderr }
  end

  def close_process
    [ @stdin, @stdout, @stderr ].each do |io|
      io.close
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

  def drain_stderr
    @stderr.each_line { |line| puts "pi[stderr]: #{line.chomp}" }
  rescue IOError, Errno::EPIPE
    # process gone
  end

  def read_loop
    @stdout.each_line do |line|
      dispatch(line)
    rescue JSON::ParserError
      puts "PiDaemon: unparseable line: #{line.chomp}"
    end
  rescue IOError, Errno::EPIPE
    # stdout closed
  ensure
    handle_exit
  end

  def dispatch(line)
    event = JSON.parse(line)

    if event["type"] == "response" && event["id"]
      q = @mutex.synchronize { @response_queues[event["id"]] }
      q&.push(event)
    else
      handlers = @mutex.synchronize { @event_handlers.values.dup }
      handlers.each { |h| h.call(event) }
    end
  end

  def handle_exit
    return if @stopped

    exit_status = begin
      @wait_thr&.value
    rescue
      nil
    end

    # Clean up stale pipes / threads from the dead process before restarting.
    # The reader thread (us) is about to return so killing it is a no-op, but
    # close_process tidies stdin, stderr, and the stderr drain thread.
    close_process

    puts "PiDaemon: process exited (status=#{exit_status}) — restarting in #{@restart_delay}s"

    sleep @restart_delay
    @restart_delay = [ @restart_delay * 2, MAX_RESTART_DELAY ].min

    start_process
  end
end

# PiRpcSession sends commands to PiDaemon on behalf of one logical session.
#
# Responsibilities:
#   - Track which logical session id is active on the daemon (switch_session)
#   - Implement send_command (request/response round-trip)
#   - Implement prompt (streaming LLM response)
#
# It does NOT own a process and does NOT block the daemon mutex during waits.
class PiRpcSession
  attr_reader :session_id

  def initialize(session_id, session_dir, daemon:)
    @session_id = sanitize_session_id(session_id)
    @session_dir = session_dir
    @daemon = daemon
    @counter_mutex = Mutex.new
    @request_counter = 0
    @active_session_id = nil
    @session_mutex = Mutex.new # serializes switch_session + prompt pairs
  end

  def switch_session(session_id)
    normalized_id = sanitize_session_id(session_id)
    normalized_id = "default" if normalized_id.empty?
    return if @active_session_id == normalized_id

    session_file = File.join(@session_dir, "#{normalized_id}.jsonl")
    send_command({ type: "switch_session", sessionPath: session_file })
    @active_session_id = normalized_id
  end

  def send_command(command)
    request_id = next_request_id
    command[:id] = request_id
    q = @daemon.register_response_queue(request_id)

    begin
      @daemon.send_line(command.to_json)
      Timeout.timeout(30) { q.pop }
    ensure
      @daemon.unregister_response_queue(request_id)
    end
  end

  def prompt(message, session_id: nil, &block)
    # The pi RPC protocol does not tag streaming events (message_update,
    # agent_end, etc.) with a request id — they are broadcast globally on
    # stdout. This means only one prompt can be in flight at a time on a
    # given pi process; otherwise handler A would receive handler B's deltas.
    #
    # @session_mutex serializes the full prompt lifecycle: switch_session →
    # send prompt → collect streaming events → agent_end. Concurrent callers
    # queue behind this mutex. This is a protocol limitation, not a bug.
    @session_mutex.synchronize do
      switch_session(session_id || @session_id)

      response_text = ""
      done_queue = Queue.new
      handler_id = "prompt-#{next_request_id}"

      handler = lambda do |event|
        case event["type"]
        when "message_update"
          ae = event["assistantMessageEvent"]
          if ae && ae["type"] == "text_delta"
            chunk = ae["delta"]
            response_text += chunk
            block&.call(chunk)
          end
        when "agent_end", "agent_error", "error"
          done_queue.push(event["type"])
        end
      end

      @daemon.with_event_handler(handler_id, handler) do
        @daemon.send_line({ type: "prompt", message: message }.to_json)

        Timeout.timeout(60) { done_queue.pop }
      end

      response_text
    end
  end

  def close
    nil # process lifecycle managed by PiDaemon
  end

  private

  def next_request_id
    @counter_mutex.synchronize { "req-#{@request_counter += 1}" }
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

class PiSessionManager
  def initialize(session_dir: "./.pi/sessions", provider: nil, model: nil)
    @session_dir = session_dir
    @sessions = {}
    @sessions_mutex = Mutex.new
    FileUtils.mkdir_p(@session_dir)

    # One long-running pi daemon process; all logical sessions multiplex over it.
    @daemon = PiDaemon.new(session_dir: @session_dir, provider: provider, model: model)
    @rpc_session = PiRpcSession.new("default", @session_dir, daemon: @daemon)
  end

  def get_session(session_id)
    @sessions_mutex.synchronize do
      @sessions[session_id] ||= PiSessionHandle.new(@rpc_session, session_id)
    end
  end

  def cleanup_session(session_id)
    @sessions_mutex.synchronize { @sessions.delete(session_id) }
  end

  def cleanup_all
    @sessions_mutex.synchronize do
      @sessions.clear
      @daemon.stop
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
# Tracks open SSE connection count. Guarded by LIVE_RELOAD_MUTEX.
# Capped at LIVE_RELOAD_MAX_CONNECTIONS to protect Puma's thread pool
# from being exhausted by stale browser connections (e.g. back/forward
# navigation where pagehide doesn't fire, or multiple open tabs).
LIVE_RELOAD_CONN_COUNT = [ 0 ]
LIVE_RELOAD_MAX_CONNECTIONS = 8

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
  content_type "text/event-stream"
  headers "Cache-Control" => "no-cache"

  client_version = params[:v].to_i

  # Reject the connection if we're already at the cap. This prevents a burst
  # of stale connections (e.g. rapid page navigation) from exhausting Puma's
  # thread pool. The client will reconnect after 3s once slots free up.
  at_capacity = LIVE_RELOAD_MUTEX.synchronize do
    if LIVE_RELOAD_CONN_COUNT[0] >= LIVE_RELOAD_MAX_CONNECTIONS
      true
    else
      LIVE_RELOAD_CONN_COUNT[0] += 1
      false
    end
  end
  if at_capacity
    status 503
    return "data: {\"error\":\"at capacity\"}\n\n"
  end

  stream :keep_open do |out|
    safe_write = lambda do |data|
      out << data
      true
    rescue
      false
    end

    loop do
      # Wait up to 8s for a reload signal, then send a keepalive comment and
      # loop. A short timeout means we write to the socket frequently and
      # detect a dead connection (closed browser tab / navigation away) within
      # one cycle instead of waiting up to 25s.
      signaled = LIVE_RELOAD_MUTEX.synchronize do
        unless LIVE_RELOAD_VERSION[0] > client_version
          LIVE_RELOAD_COND.wait(LIVE_RELOAD_MUTEX, 8)
        end
        LIVE_RELOAD_VERSION[0] > client_version
      end

      if signaled
        current = LIVE_RELOAD_MUTEX.synchronize { LIVE_RELOAD_VERSION[0] }
        client_version = current
        payload = { version: current }.to_json
        break unless safe_write.call("event: reload\n")
        break unless safe_write.call("data: #{payload}\n\n")
      else
        # Keepalive — no change yet. The write will raise if the client is gone,
        # causing safe_write to return false and break the loop immediately.
        break unless safe_write.call(": keepalive\n\n")
      end
    end
  ensure
    LIVE_RELOAD_MUTEX.synchronize { LIVE_RELOAD_CONN_COUNT[0] -= 1 }
    begin
      out.close
    rescue
      nil
    end
  end
end

# =============================================================================
# Cleanup
# =============================================================================

# Explicit SIGTERM handler so EC2 instance termination (which sends SIGTERM)
# guarantees the log flush runs. Without this trap, SIGTERM kills the process
# immediately in some Puma/Sinatra configurations and at_exit never fires.
# Calling exit here triggers the at_exit block below for the actual flush.
Signal.trap("TERM") do
  # Signal.trap blocks run on the main thread in MRI and must not call
  # blocking I/O directly. Spawn a thread to do the flush, join it so the
  # main thread waits, then call exit to trigger the at_exit block below.
  # ship_all is idempotent (byte-offset tracking), so the at_exit re-flush
  # is a no-op if the SIGTERM flush already shipped everything.
  Thread.new do
    puts "PiSessionShipper: SIGTERM received, flushing logs..."
    settings.pi_session_shipper.ship_all
    puts "PiSessionShipper: SIGTERM flush complete."
  rescue => e
    puts "PiSessionShipper: SIGTERM flush error: #{e.message}"
  end.join
  exit
end

at_exit do
  # Flush any unshipped log lines before the pi processes are closed.
  # Covers clean shutdown (explicit exit, Ctrl-C/SIGINT) and runs as a
  # safety net after the SIGTERM handler above (ship_all is idempotent).
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
  headers "Cache-Control" => "no-cache"

  # Capture request params now — they are unavailable inside the stream block
  # after the Puma thread is released.
  prompt = params[:prompt]
  session_id = params[:session_id] || "default"
  context_parts = []
  context_parts << "Active theme directory: #{theme_path}"
  context_parts << "Content path: #{params[:content_path]}" if params[:content_path].present?
  context_parts << "Page URL: #{params[:full_url]}" if params[:full_url].present?
  context_parts << "Page title: #{params[:page_title]}" if params[:page_title].present?
  context_parts << "Path: #{params[:pathname]}" if params[:pathname].present?
  inspiration = inspiration_context
  context_parts << "\n#{inspiration}" if inspiration
  full_prompt = "The user is currently viewing the following page:\n#{context_parts.join("\n")}\n\nUser asks: #{prompt}"

  # Use a Queue to decouple the LLM worker thread from the Rack streaming
  # thread. Under Puma (threaded mode), stream :keep_open holds a Puma thread
  # for the duration of the block. By pushing all work onto a background thread
  # and draining a Queue here, the pattern remains correct regardless of whether
  # the Rack adapter is evented or threaded: the stream block yields quickly
  # between Queue#pop calls, freeing the scheduler.
  #
  # Sentinel: nil means the background thread finished (success or error).
  queue = Queue.new

  Thread.new do
    if prompt.nil? || prompt.empty?
      queue.push([ :event, "error" ])
      queue.push([ :data, "No prompt provided" ])
      queue.push(nil)
      next
    end

    begin
      session = settings.pi_session_manager.get_session(session_id)
      queue.push([ :event, "start" ])
      queue.push([ :data, "{\"session_id\":\"#{session_id}\"}" ])

      session.prompt(full_prompt) do |chunk|
        escaped_chunk = chunk.gsub("\\", "\\\\").gsub("\n", '\\n').gsub('"', '\\"')
        queue.push([ :chunk, escaped_chunk ])
      end

      queue.push([ :event, "done" ])
      queue.push([ :data, "{}" ])
    rescue => e
      queue.push([ :event, "error" ])
      queue.push([ :data, e.message ])
    ensure
      queue.push(nil)
    end
  end

  stream :keep_open do |out|
    safe_write = lambda do |data|
      out << data
      true
    rescue
      false
    end

    # Keepalive comments every 15s while waiting for the next queue item.
    # Prevents ALB / intermediate proxies from closing an idle connection.
    keepalive_thread = Thread.new do
      loop do
        sleep 15
        break unless safe_write.call(": keepalive\n\n")
      end
    end

    begin
      loop do
        msg = queue.pop
        break if msg.nil?

        type, payload = msg
        case type
        when :event
          break unless safe_write.call("event: #{payload}\n")
        when :data
          break unless safe_write.call("data: #{payload}\n\n")
        when :chunk
          break unless safe_write.call("data: #{payload}\n\n")
        end
      end
    ensure
      keepalive_thread.kill
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
  path = params["splat"].first.chomp("/")
  load_path(path)
end

set :static, true
set :public_folder, theme_path + "/assets"

puts "Theme: #{ENV["THEME"]}"
puts "Theme path: #{theme_path}"
