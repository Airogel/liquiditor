# frozen_string_literal: true

require "json"
require "yaml"
require "fileutils"
require "sequel"
require "securerandom"

require_relative "db/schema"

# =============================================================================
# Helpers
# =============================================================================

def theme_dir(name = nil)
  name ||= ENV["THEME"] || "default"
  File.join(__dir__, "themes", name)
end

def database_path(name = nil)
  File.join(theme_dir(name), "database.sqlite3")
end

def open_database(name = nil)
  db = Sequel.sqlite(database_path(name))
  Schema.create!(db)
  db
end

# =============================================================================
# Database Tasks
# =============================================================================

namespace :db do
  desc "Create the SQLite database for the current theme"
  task :create do
    name = ENV["THEME"] || "default"
    path = database_path(name)

    if File.exist?(path)
      puts "Database already exists: #{path}"
    else
      FileUtils.mkdir_p(File.dirname(path))
      db = open_database(name)
      db.disconnect
      puts "Created database: #{path}"
    end
  end

  desc "Run schema migrations (idempotent)"
  task :migrate do
    name = ENV["THEME"] || "default"
    db = open_database(name)
    db.disconnect
    puts "Schema up to date: #{database_path(name)}"
  end

  desc "Seed the database with default data"
  task :seed do
    name = ENV["THEME"] || "default"
    db = open_database(name)
    Schema.seed!(db)
    db.disconnect
    puts "Seeded database: #{database_path(name)}"
  end
end

# =============================================================================
# YAML Import
# =============================================================================

desc "Import a database.yml into SQLite for a theme"
task :import_yaml, [ :theme ] do |_t, args|
  name = args[:theme] || ENV["THEME"] || "default"
  yaml_path = File.join(theme_dir(name), "database.yml")

  unless File.exist?(yaml_path)
    puts "Error: No database.yml found at #{yaml_path}"
    exit 1
  end

  puts "Importing #{yaml_path} into SQLite..."

  raw = if YAML.respond_to?(:unsafe_load_file)
    YAML.unsafe_load_file(yaml_path)
  else
    YAML.load_file(yaml_path)
  end

  db = open_database(name)

  # Clear existing data
  [ :content_paths, :entries, :collections, :globals, :navigations, :navigation_items, :forms ].each do |table|
    db[table].delete
  end

  # Known non-collection keys
  skip_keys = %w[content_paths navigation forms site site_settings]

  # -------------------------------------------------------------------------
  # 1. Import content_paths
  # -------------------------------------------------------------------------
  if raw["content_paths"]
    raw["content_paths"].each do |path, config|
      is_index = config["content"] == "_index"
      db[:content_paths].insert(
        path: path,
        collection_handle: config["content_key"],
        entry_handle: is_index ? nil : config["content"],
        template_handle: config["template"],
        layout_handle: config["layout"] || "theme",
        is_index: is_index
      )
    end
    puts "  Imported #{raw["content_paths"].size} content paths"
  end

  # -------------------------------------------------------------------------
  # 2. Import globals (non-array top-level keys that aren't content_paths/navigation/forms)
  # -------------------------------------------------------------------------
  %w[site site_settings].each do |key|
    next unless raw[key]

    data = raw[key]
    if data.is_a?(Hash)
      db[:globals].insert(
        handle: key,
        name: data["title"] || key.tr("_", " ").capitalize,
        data: JSON.dump(data)
      )
      puts "  Imported global: #{key}"
    end
  end

  # -------------------------------------------------------------------------
  # 3. Import navigations
  # -------------------------------------------------------------------------
  raw["navigation"]&.each do |nav_handle, items|
    db[:navigations].insert(handle: nav_handle, title: nav_handle.capitalize)

    next unless items.is_a?(Array)
    items.each_with_index do |item, idx|
      db[:navigation_items].insert(
        navigation_handle: nav_handle,
        title: item["title"],
        url: item["url"],
        position: idx
      )
    end
    puts "  Imported navigation: #{nav_handle} (#{items.size} items)"
  end

  # -------------------------------------------------------------------------
  # 4. Import forms
  # -------------------------------------------------------------------------
  raw["forms"]&.each do |form_handle, config|
    db[:forms].insert(
      handle: form_handle,
      title: config["title"] || form_handle.tr("_", " ").capitalize,
      collection_handle: config["collection"] || form_handle,
      blueprint_handle: config["blueprint"],
      honeypot_enabled: config["honeypot_enabled"] || false,
      redirect_url: config["redirect_url"] || "",
      success_message: config["success_message"] || "",
      fields: JSON.dump(config["fields"] || [])
    )
    puts "  Imported form: #{form_handle}"
  end

  # -------------------------------------------------------------------------
  # 5. Import collections and entries
  # -------------------------------------------------------------------------
  # Build a handle→collection index from content_paths so entity refs in any
  # collection can be resolved without hardcoded path patterns.
  handle_to_collection = {}
  raw["content_paths"]&.each do |_path, config|
    collection = config["content_key"]
    entry_handle = config["content"]
    next if collection.nil? || entry_handle.nil? || entry_handle == "_index"
    handle_to_collection[entry_handle] = collection
  end
  # Also index directly from the YAML collection arrays (covers entries whose
  # content_path may not appear in content_paths, e.g. unpublished entries).
  raw.each do |key, values|
    next if skip_keys.include?(key)
    next unless values.is_a?(Array) && values.first.is_a?(Hash) && values.first.key?("handle")
    values.each { |entry| handle_to_collection[entry["handle"]] = key if entry["handle"] }
  end

  raw.each do |key, values|
    next if skip_keys.include?(key)
    next unless values.is_a?(Array) && values.first.is_a?(Hash) && values.first.key?("handle")

    # Create collection
    db[:collections].insert_conflict(:replace).insert(
      handle: key,
      name: key.tr("_", " ").capitalize,
      routing: "#{key}/:handle"
    )

    values.each do |entry|
      # Separate core fields from data fields
      core_keys = %w[id title handle content_path published_at position]
      data = {}

      entry.each do |field_key, field_value|
        next if core_keys.include?(field_key)

        # Convert entity reference arrays to compact {handle, collection} stubs
        if field_value.is_a?(Array) && field_value.first.is_a?(Hash) && field_value.first.key?("handle")
          data[field_key] = field_value.map do |ref|
            collection_for_ref = handle_to_collection[ref["handle"]] || infer_collection_from_yaml_ref(ref)
            if collection_for_ref
              { "handle" => ref["handle"], "collection" => collection_for_ref }
            else
              ref
            end
          end
        elsif field_value.is_a?(Hash) && field_value.key?("handle") && !field_value.key?("body")
          collection_for_ref = handle_to_collection[field_value["handle"]] || infer_collection_from_yaml_ref(field_value)
          data[field_key] = if collection_for_ref
            { "handle" => field_value["handle"], "collection" => collection_for_ref }
          else
            field_value
          end
        else
          data[field_key] = field_value
        end
      end

      db[:entries].insert(
        prefix_id: entry["id"] || "cnety_#{SecureRandom.hex(12)}",
        collection_handle: key,
        handle: entry["handle"],
        title: entry["title"],
        published: entry.fetch("published", true),
        published_at: entry["published_at"],
        position: entry["position"] || 0,
        data: JSON.dump(data)
      )
    end

    puts "  Imported collection: #{key} (#{values.size} entries)"
  end

  db.disconnect
  puts "\nImport complete! Database at: #{database_path(name)}"
end

def infer_collection_from_yaml_ref(ref)
  content_path = ref["content_path"]
  return nil unless content_path

  case content_path
  when %r{^/tag/} then "tag"
  when %r{^/blog/} then "post"
  when %r{^/news/} then "news"
  when %r{^/testimonial/} then "testimonial"
  when %r{^/team/} then "team"
  when %r{^/properties/} then "properties"
  when %r{^/service/} then "service"
  when %r{^/neighborhoods/} then "neighborhood"
  when %r{^/stats/} then "stats"
  when %r{^/[^/]+$} then "page"
  end
end

# =============================================================================
# Theme Creation
# =============================================================================

desc "Create a new theme with basic structure (use INSTALL=true to auto-install dependencies)"
task :create_theme, [ :name ] do |_t, args|
  if args[:name].nil? || args[:name].strip.empty?
    puts "Usage: rake create_theme[theme_name]"
    puts "       INSTALL=true rake create_theme[my_new_theme]"
    exit 1
  end

  theme_name = args[:name].strip
  td = theme_dir(theme_name)
  auto_install = ENV["INSTALL"] == "true"

  if File.exist?(td)
    puts "Error: Theme '#{theme_name}' already exists at #{td}"
    exit 1
  end

  puts "Creating theme: #{theme_name}"

  # Create directory structure
  dirs = [
    td,
    File.join(td, "css"),
    File.join(td, "js"),
    File.join(td, "js", "controllers"),
    File.join(td, "templates"),
    File.join(td, "assets")
  ]

  dirs.each do |dir|
    FileUtils.mkdir_p(dir)
    puts "  Created #{dir}"
  end

  # Create package.json
  package_json = {
    "scripts" => {
      "css" => "npx @tailwindcss/cli -i ./css/application.tailwind.css -o ./assets/application.css --watch",
      "js" => "esbuild js/*.* --bundle --format=iife --outdir=assets --public-path=/"
    },
    "dependencies" => {
      "@hotwired/stimulus" => "^3.2.2",
      "@tailwindcss/typography" => "^0.5.19",
      "@tailwindplus/elements" => "^1.0.19"
    },
    "devDependencies" => {
      "@tailwindcss/cli" => "^4.2.0",
      "esbuild" => "^0.27.0",
      "tailwindcss" => "^4.2.0"
    }
  }

  File.write(File.join(td, "package.json"), JSON.pretty_generate(package_json) + "\n")
  puts "  Created package.json"

  # Create application.tailwind.css
  css_content = <<~CSS
    @import "tailwindcss";

    @theme {
      --bg-primary: var(--color-stone-600);
    }
  CSS
  File.write(File.join(td, "css", "application.tailwind.css"), css_content)
  puts "  Created css/application.tailwind.css"

  # Create application.js
  js_content = <<~JS
    console.log("#{theme_name} theme loaded!");
    import "@tailwindplus/elements";
    import { Application } from "@hotwired/stimulus";

    window.Stimulus = Application.start();
  JS
  File.write(File.join(td, "js", "application.js"), js_content)
  puts "  Created js/application.js"

  # Create .env
  env_content = <<~ENV
    # AIROGEL CMS API Configuration
    AIROGEL_API_URL=https://api.airogelcms.com
    AIROGEL_ACCOUNT_ID=acct_xxx
    AIROGEL_API_KEY=your_api_key_here
  ENV
  File.write(File.join(td, ".env"), env_content)
  puts "  Created .env"

  # Update .env_vars
  File.write(File.join(__dir__, ".env_vars"), "THEME=#{theme_name}\n")
  puts "  Updated .env_vars with THEME=#{theme_name}"

  # Create theme.liquid (layout)
  theme_liquid = <<~LIQUID
    <!doctype html>
    <html lang="en" class="h-full scroll-smooth bg-stone-50 antialiased">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>{{ site.title }}</title>
        {{ 'application.js' | asset_url | script_tag: 'default' }}
        {{ 'application.css' | asset_url | stylesheet_tag }}
        {{ content_for_header }}
        {% cms_scripts %}
      </head>
      <body class="flex h-full flex-col">
        <header class="border-b border-stone-200 bg-white">
          <nav class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
            <div class="flex h-16 items-center justify-between">
              <a href="/" class="text-xl font-bold text-stone-900">{{ site.title }}</a>
              <div class="flex gap-6">
                {% for item in navigation.menu %}
                  <a href="{{ item.url }}" class="text-sm font-medium text-stone-600 hover:text-stone-900">{{ item.title }}</a>
                {% endfor %}
              </div>
            </div>
          </nav>
        </header>

        <main class="flex-1">
          {{ content_for_layout }}
        </main>

        <footer class="border-t border-stone-200 bg-stone-50 py-8">
          <div class="mx-auto max-w-7xl px-4 text-center text-sm text-stone-500">
            &copy; {{ "now" | date: "%Y" }} {{ site.title }}
          </div>
        </footer>
      </body>
    </html>
  LIQUID
  File.write(File.join(td, "templates", "theme.liquid"), theme_liquid)
  puts "  Created templates/theme.liquid"

  # Create index.liquid
  index_liquid = <<~LIQUID
    <div class="mx-auto max-w-7xl px-4 py-12 sm:px-6 lg:px-8">
      <h1 class="text-4xl font-bold text-stone-900 mb-4">{{ page.title }}</h1>

      {% if page.body %}
        <div class="prose prose-stone max-w-none mb-12">
          {{ page.body }}
        </div>
      {% endif %}
    </div>
  LIQUID
  File.write(File.join(td, "templates", "index.liquid"), index_liquid)
  puts "  Created templates/index.liquid"

  # Create page.liquid
  page_liquid = <<~LIQUID
    <div class="mx-auto max-w-3xl px-4 py-12 sm:px-6 lg:px-8">
      <h1 class="text-3xl font-bold text-stone-900 mb-6">{{ page.title }}</h1>

      {% if page.body %}
        <div class="prose prose-stone max-w-none">
          {{ page.body }}
        </div>
      {% endif %}
    </div>
  LIQUID
  File.write(File.join(td, "templates", "page.liquid"), page_liquid)
  puts "  Created templates/page.liquid"

  # Create SQLite database with seed data
  db = open_database(theme_name)
  Schema.seed!(db)
  db.disconnect
  puts "  Created and seeded database.sqlite3"

  puts "\nTheme '#{theme_name}' created successfully!"

  if auto_install
    puts "\nInstalling dependencies..."
    Dir.chdir(td) do
      system("yarn install") || puts("  WARNING: yarn install failed")
      system("yarn js") || puts("  WARNING: yarn js failed")
      system("npx @tailwindcss/cli -i ./css/application.tailwind.css -o ./assets/application.css --minify") || puts("  WARNING: tailwind build failed")
    end
    puts "\nReady! Start with: ./bin/dev"
  else
    puts "\nNext steps:"
    puts "  1. cd themes/#{theme_name} && yarn install && cd ../.."
    puts "  2. ./bin/dev"
  end
end
