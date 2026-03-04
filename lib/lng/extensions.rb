# frozen_string_literal: true

require "securerandom"

# Mirrors CMS lib/liquid/lng_extensions.rb
# All custom Liquid tags and drops for Liquiditor, backed by SQLite instead of ActiveRecord.

module Extensions
  # ---------------------------------------------------------------------------
  # Navigation Drop — mirrors CMS Liquid::NavigationDrop
  # Lazy: queries SQLite when accessed via {{ navigation.menu }}
  # ---------------------------------------------------------------------------

  class NavigationDrop < Liquid::Drop
    def liquid_method_missing(method)
      Database.find_navigation_items(method.to_s)
    end
  end

  # ---------------------------------------------------------------------------
  # Form Drops — mirrors CMS Liquid::LngExtensions::FieldDrop, FormDrop, etc.
  # ---------------------------------------------------------------------------

  class FieldDrop < Liquid::Drop
    def initialize(form_id, field_config)
      @form_id = form_id
      @field = field_config
    end

    def handle
      @field["handle"] || @field[:handle]
    end

    def label
      @field["label"] || @field["display"] || @field[:label] || handle&.to_s&.tr("_", " ")&.capitalize
    end

    def type
      @field["type"] || @field[:type] || "text"
    end

    def required
      @field["required"] || @field[:required] || false
    end

    def placeholder
      @field["placeholder"] || @field[:placeholder] || ""
    end

    def help_text
      @field["help_text"] || @field[:help_text] || ""
    end

    def input_type
      @field["input_type"] || @field[:input_type] || "text"
    end

    def options
      @field["options"] || @field[:options] || @field["enumerations"] || @field[:enumerations] || []
    end

    def display_as
      @field["display_as"] || @field[:display_as] || "select"
    end

    def max_items
      @field["max_items"] || @field[:max_items] || 10
    end

    def id
      "#{@form_id}_#{handle}"
    end

    def name
      "fields[#{handle}]"
    end

    def to_s
      handle
    end
  end

  class FieldLookup < Liquid::Drop
    def initialize(form_id, fields_config)
      @form_id = form_id
      @fields_config = fields_config || []
      @cache = {}
    end

    def [](handle)
      @cache[handle.to_s] ||= begin
        field = @fields_config.find { |f| (f["handle"] || f[:handle]) == handle.to_s }
        field ? FieldDrop.new(@form_id, field) : nil
      end
    end

    def liquid_method_missing(method)
      self[method.to_s]
    end
  end

  class ErrorsDrop < Liquid::Drop
    def initialize(errors)
      @errors = errors || {}
    end

    def [](field_handle)
      @errors[field_handle.to_s]
    end

    def liquid_method_missing(method)
      self[method.to_s]
    end

    def any
      @errors.any?
    end

    def all
      @errors.values.flatten
    end

    def full_messages
      @errors.map { |_field, messages| messages }.flatten
    end
  end

  class ValuesDrop < Liquid::Drop
    def initialize(values)
      @values = values || {}
    end

    def [](field_handle)
      @values[field_handle.to_s]
    end

    def liquid_method_missing(method)
      self[method.to_s]
    end
  end

  class FormDrop < Liquid::Drop
    def initialize(form_id, collection, blueprint, fields_config, errors = {}, old_values = {})
      @form_id = form_id
      @collection = collection
      @blueprint = blueprint
      @fields_config = fields_config || []
      @errors = errors || {}
      @old_values = old_values || {}
    end

    def id
      @form_id
    end

    attr_reader :collection, :blueprint

    def fields
      @fields ||= @fields_config.map { |field| FieldDrop.new(@form_id, field) }
    end

    def field
      @field_lookup ||= FieldLookup.new(@form_id, @fields_config)
    end

    def errors
      @errors_drop ||= ErrorsDrop.new(@errors)
    end

    def has_errors
      @errors && !@errors.empty?
    end

    def values
      @values_drop ||= ValuesDrop.new(@old_values)
    end
  end

  # ---------------------------------------------------------------------------
  # FormFor block tag — mirrors CMS Liquid::LngExtensions::FormFor
  # Queries SQLite forms table instead of ActiveRecord Form model
  # ---------------------------------------------------------------------------

  class FormFor < Liquid::Block
    def initialize(tag_name, markup, parse_context)
      super
      @options = {}
      markup.scan(Liquid::TagAttributes) do |key, value|
        @options[key] = value.delete('"')
      end
      @form_handle = @options.delete("form")
    end

    def render_to_output_buffer(context, output)
      return "" unless @form_handle

      # Load form configuration from SQLite
      form_config = Database.find_form(@form_handle)

      # Fallback defaults if form not found
      form_config ||= { "collection" => @form_handle, "blueprint" => "default", "honeypot_enabled" => false, "fields" => [] }

      collection_handle = form_config["collection"] || @form_handle
      blueprint_handle = form_config["blueprint"] || "default"
      redirect_url = @options["redirect"] || form_config["redirect_url"] || ""
      success_message = @options["success_message"] || form_config["success_message"] || "Thank you for your submission!"
      honeypot_enabled = form_config["honeypot_enabled"] || false
      fields_config = form_config["fields"] || []

      form_id = @options["id"] || "form_#{@form_handle}_#{SecureRandom.hex(4)}"

      # Get errors/values from registers (set by form submission handler)
      form_errors = context.registers[:form_errors] || {}
      form_values = context.registers[:form_values] || {}

      form_drop = FormDrop.new(
        form_id,
        collection_handle,
        blueprint_handle,
        fields_config,
        form_errors,
        form_values
      )

      context.stack do
        context["form"] = form_drop

        output << render_form_open(context, form_id, redirect_url, success_message, honeypot_enabled)
        super
        output << "</form>"
      end
    end

    private

    def render_form_open(context, form_id, redirect_url, success_message, honeypot_enabled)
      csrf_token = context.registers["csrf_token"]
      form_class = @options["class"] || ""

      hidden_fields = []
      if csrf_token
        hidden_fields << %(<input type="hidden" name="authenticity_token" value="#{csrf_token}" autocomplete="off">)
      end
      hidden_fields << %(<input type="hidden" name="redirect_url" value="#{redirect_url}">) unless redirect_url.empty?
      unless success_message.empty?
        hidden_fields << %(<input type="hidden" name="success_message" value="#{escape_html(success_message)}">)
      end

      if honeypot_enabled
        hidden_fields << <<~HONEYPOT
          <div style="position: absolute; left: -9999px;" aria-hidden="true">
            <input type="text" name="website" tabindex="-1" autocomplete="off">
          </div>
        HONEYPOT
      end

      <<~HTML
        <form id="#{form_id}" class="#{form_class}" method="post" action="/forms/#{@form_handle}/submit" enctype="multipart/form-data" data-controller="collection-form" data-collection-form-target="form">
          #{hidden_fields.join("\n    ")}
      HTML
    end

    def escape_html(text)
      text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
    end
  end

  # ---------------------------------------------------------------------------
  # CmsScripts tag — mirrors CMS Liquid::LngExtensions::CmsScripts
  # ---------------------------------------------------------------------------

  class CmsScripts < Liquid::Tag
    def initialize(tag_name, markup, parse_context)
      super
      @options = {}
      markup.scan(Liquid::TagAttributes) do |key, value|
        @options[key] = value.delete('"')
      end
    end

    def render_to_output_buffer(_context, output)
      include_css = @options["css"] != "false"
      include_js = @options["js"] != "false"

      output << %(<link rel="stylesheet" href="/cms/cms.css">\n) if include_css
      output << %(<script type="module" src="/cms/cms.js"></script>\n) if include_js

      output
    end
  end

  # ---------------------------------------------------------------------------
  # Paginate block tag — mirrors CMS Liquid::LngExtensions::Paginate
  # Client-side pagination over arrays
  # ---------------------------------------------------------------------------

  class Paginate < Liquid::Block
    SYNTAX = /(#{Liquid::QuotedFragment})\s*(by\s*(\d+))?/

    def initialize(tag_name, markup, options)
      super

      unless markup =~ SYNTAX
        raise SyntaxError, "Syntax Error in tag 'paginate' - Valid syntax: paginate [collection] by number"
      end

      @collection_name = Regexp.last_match(1)
      @page_size = if Regexp.last_match(2)
        Regexp.last_match(3).to_i
      else
        20
      end

      @attributes = { "window_size" => 3 }
      markup.scan(Liquid::TagAttributes) do |key, value|
        @attributes[key] = value
      end
    end

    def render_to_output_buffer(context, output)
      @context = context

      context.stack do
        collection = context[@collection_name]

        raise ArgumentError, "Cannot paginate '#{@collection_name}'. Not found." if collection.nil?

        collection = collection.is_a?(Array) ? collection : []
        collection_size = collection.size

        current_page = (context["current_page"] || context["page"] || 1).to_i
        current_page = 1 if current_page < 1

        total_pages = (collection_size > 0) ? (collection_size.to_f / @page_size).ceil : 1
        current_page = total_pages if current_page > total_pages

        offset = (current_page - 1) * @page_size
        current_items = collection.slice(offset, @page_size) || []

        current_path = context["current_path"] || "/"

        pagination = {
          "items" => current_items,
          "page_size" => @page_size,
          "current_page" => current_page,
          "current_offset" => offset,
          "total_pages" => total_pages,
          "total_entries" => collection_size,
          "total_count" => collection_size,
          "per_page" => @page_size,
          "pages" => total_pages,
          "has_previous" => current_page > 1,
          "has_next" => current_page < total_pages,
          "previous_url" => (current_page > 1) ? build_page_url(current_path, current_page - 1) : nil,
          "next_url" => (current_page < total_pages) ? build_page_url(current_path, current_page + 1) : nil,
          "parts" => []
        }

        # Build pagination parts (page number links)
        if total_pages > 1
          window_size = (@attributes["window_size"] || 3).to_i
          hellip_break = false

          1.upto(total_pages) do |page|
            if current_page == page
              pagination["parts"] << no_link(page)
            elsif page == 1
              pagination["parts"] << link(page, page, current_path)
            elsif page == total_pages
              pagination["parts"] << link(page, page, current_path)
            elsif page <= current_page - window_size || page >= current_page + window_size
              next if hellip_break

              pagination["parts"] << no_link("&hellip;")
              hellip_break = true
              next
            else
              pagination["parts"] << link(page, page, current_path)
            end

            hellip_break = false
          end
        end

        # Shopify-style previous/next objects
        if current_page > 1
          pagination["previous"] = {
            "title" => "&laquo; Previous",
            "url" => build_page_url(current_path, current_page - 1),
            "is_link" => true
          }
        end

        if current_page < total_pages
          pagination["next"] = {
            "title" => "Next &raquo;",
            "url" => build_page_url(current_path, current_page + 1),
            "is_link" => true
          }
        end

        context["paginate"] = pagination

        super
      end
    end

    private

    def build_page_url(base_path, page)
      return base_path if page == 1
      clean_path = base_path.sub(%r{/page/\d+$}, "")
      "#{clean_path}/page/#{page}"
    end

    def no_link(title)
      { "title" => title, "is_link" => false }
    end

    def link(title, page, current_path)
      { "title" => title, "url" => build_page_url(current_path, page), "is_link" => true }
    end
  end

  # ---------------------------------------------------------------------------
  # QueryTag — mirrors CMS lib/liquid/tags/query_tag.rb
  # Backed by SQLite via Database.query_entries instead of ActiveRecord.
  # ---------------------------------------------------------------------------

  class QueryTag < Liquid::Block
    def initialize(tag_name, markup, parse_context)
      super
      @options = {}
      @raw_filter_markup = nil

      remaining_markup = extract_filter_markup(markup)

      remaining_markup.scan(Liquid::TagAttributes) do |key, value|
        @options[key] = value.gsub(/\A['"]|['"]\z/, "")
      end
    end

    def render_to_output_buffer(context, output)
      collection_handle = resolve_value(@options["collection"], context)
      return "" unless collection_handle&.then { |v| !v.empty? }

      page = resolve_value(@options["page"], context)&.to_i || context["page"]&.to_i || 1
      per_page = resolve_value(@options["per_page"], context)&.to_i || 25
      order_by = resolve_value(@options["order_by"], context) || "published_at"
      order_dir = resolve_value(@options["order_dir"], context) || "desc"

      published_only = if @options.key?("published")
        to_boolean(resolve_value(@options["published"], context))
      else
        true
      end

      field_filters = @raw_filter_markup.then { |fm| fm ? resolve_filter_fields(fm, context) : [] }

      result = Database.query_entries(
        collection_handle,
        field_filters: field_filters,
        order_by: order_by,
        order_dir: order_dir.to_sym,
        page: page,
        per_page: per_page,
        published_only: published_only
      )

      query_data = build_query_data(result)

      context.stack do
        context["query"] = query_data
        super
      end
    end

    private

    def extract_filter_markup(markup)
      filter_match = markup.match(/\bfilter:\s*(\{)/)
      return markup unless filter_match

      start_pos = filter_match.begin(1)
      depth = 0
      end_pos = start_pos

      markup[start_pos..].each_char.with_index do |char, i|
        case char
        when "{" then depth += 1
        when "}"
          depth -= 1
          if depth == 0
            end_pos = start_pos + i
            break
          end
        end
      end

      @raw_filter_markup = markup[start_pos..end_pos]
      markup.sub(/\bfilter:\s*\{[^}]*(?:\{[^}]*\}[^}]*)?\}/, "")
    end

    def resolve_filter_fields(filter_markup, context)
      fields = []
      field_pattern = /\{\s*path:\s*['"]([^'"]+)['"]\s*,\s*op:\s*['"]([^'"]+)['"]\s*,\s*value:\s*([^}]+?)\s*\}/
      filter_markup.scan(field_pattern) do |path, op, raw_value|
        value = resolve_filter_value(raw_value.strip, context)
        fields << { path: path, op: op, value: value } unless value.nil?
      end
      fields
    end

    def resolve_filter_value(token, context)
      return token.gsub(/\A['"]|['"]\z/, "") if token.match?(/\A['"].*['"]\z/)
      return token.to_i if token.match?(/\A\d+\z/)
      return token.to_f if token.match?(/\A\d+\.\d+\z/)

      resolve_liquid_variable(token, context)
    end

    def resolve_liquid_variable(path, context)
      parts = path.split(".")
      value = context[parts.shift]
      parts.each do |part|
        break if value.nil?
        value = value.respond_to?(:[]) ? value[part] : nil
      end
      value
    end

    def resolve_value(value, context)
      return nil if value.nil?
      context[value].then { |v| (v.nil? || (v.respond_to?(:empty?) && v.empty?)) ? value : v }
    end

    def to_boolean(value)
      case value
      when true, "true", "1", "yes", 1 then true
      when false, "false", "0", "no", 0, nil then false
      else value.respond_to?(:empty?) ? !value.empty? : !!value
      end
    end

    def build_query_data(result)
      entries = result[:items]
      {
        "entries" => entries,
        "results" => entries,
        "total" => result[:total],
        "pagination" => {
          "current_page" => result[:page],
          "total_pages" => result[:total_pages],
          "total_count" => result[:total],
          "per_page" => result[:per_page],
          "has_previous" => result[:page] > 1,
          "has_next" => result[:page] < result[:total_pages],
          "previous_page" => (result[:page] > 1) ? result[:page] - 1 : nil,
          "next_page" => (result[:page] < result[:total_pages]) ? result[:page] + 1 : nil
        }
      }
    end
  end

  # ---------------------------------------------------------------------------
  # Stub tags — legacy/e-commerce, not needed for template preview
  # ---------------------------------------------------------------------------

  class GithubOauthLogin < Liquid::Tag
    def initialize(tag_name, markup, parse_context)
      super
      @options = {}
      markup.scan(Liquid::TagAttributes) do |key, value|
        @options[key] = value.delete('"')
      end
    end

    def render_to_output_buffer(_context, output)
      output << "<!-- github_oauth_login: not available in Liquiditor -->"
    end
  end

  class OneClickButton < Liquid::Tag
    def initialize(tag_name, markup, parse_context)
      super
      @options = {}
      markup.scan(Liquid::TagAttributes) do |key, value|
        @options[key] = value.delete('"')
      end
    end

    def render_to_output_buffer(_context, output)
      output << "<!-- one_click_button: not available in Liquiditor -->"
    end
  end

  class Locale < Liquid::Tag
    def render_to_output_buffer(_context, output)
      output << "en-us"
    end
  end

  class ContentForLayout < Liquid::Tag
    def render(context)
      "ZZZSPLITEHEREXYZ"
    end
  end

  class CollectionForm < Liquid::Block
    def initialize(tag_name, markup, parse_context)
      super
      @options = {}
      markup.scan(Liquid::TagAttributes) do |key, value|
        @options[key] = value.delete('"')
      end
      @collection_handle = @options.delete("collection") || @options.delete("for")
    end

    def render_to_output_buffer(context, output)
      return "" unless @collection_handle
      output << "<!-- collection_form for #{@collection_handle}: use form_for instead -->"
      super
    end
  end
end
