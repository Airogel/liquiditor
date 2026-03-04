# frozen_string_literal: true

# SQLite schema for Liquiditor
# Run via: rake db:create or Database.ensure_schema!

module Schema
  def self.create!(db)
    db.run "PRAGMA journal_mode = WAL"
    db.run "PRAGMA foreign_keys = ON"
    db.run "PRAGMA busy_timeout = 5000"
    db.run "PRAGMA synchronous = NORMAL"
    db.run "PRAGMA cache_size = -64000"

    db.create_table?(:content_paths) do
      primary_key :id
      String :path, null: false, unique: true
      String :collection_handle, null: false
      String :entry_handle
      String :template_handle, null: false
      String :layout_handle, null: false, default: "theme"
      TrueClass :is_index, null: false, default: false
    end

    db.create_table?(:collections) do
      primary_key :id
      String :handle, null: false, unique: true
      String :name, null: false
      String :routing
      String :index_routing
      String :index_template_handle
      String :template_handle
      String :layout_handle, default: "theme"
      String :orderable, null: false, default: "no"
      String :schema_type
      TrueClass :feed_enabled, null: false, default: false
      String :feed_path
      String :feed_title
      String :feed_description
      Integer :feed_limit, null: false, default: 20
    end

    db.create_table?(:entries) do
      primary_key :id
      String :prefix_id, unique: true
      String :collection_handle, null: false
      String :handle, null: false
      String :title, null: false
      TrueClass :published, null: false, default: true
      String :published_at
      Integer :position, null: false, default: 0
      String :data, null: false, default: "{}"
      String :created_at, null: false, default: Sequel.lit("datetime('now')")
      String :updated_at, null: false, default: Sequel.lit("datetime('now')")

      unique [ :collection_handle, :handle ]
      index :collection_handle
      index [ :collection_handle, :published, :published_at ]
    end

    db.create_table?(:globals) do
      primary_key :id
      String :handle, null: false, unique: true
      String :name, null: false
      String :data, null: false, default: "{}"
    end

    db.create_table?(:navigations) do
      primary_key :id
      String :handle, null: false, unique: true
      String :title, null: false
    end

    db.create_table?(:navigation_items) do
      primary_key :id
      String :navigation_handle, null: false
      Integer :parent_id
      String :title, null: false
      String :url
      String :collection_handle
      String :entry_handle
      Integer :position, null: false, default: 0
      String :data, null: false, default: "{}"

      index :navigation_handle
      index :parent_id
    end

    db.create_table?(:forms) do
      primary_key :id
      String :handle, null: false, unique: true
      String :title, null: false
      String :collection_handle, null: false
      String :blueprint_handle
      TrueClass :honeypot_enabled, null: false, default: false
      String :redirect_url, null: false, default: ""
      String :success_message, null: false, default: ""
      TrueClass :notification_enabled, null: false, default: false
      String :notification_emails, null: false, default: ""
      String :fields, null: false, default: "[]"
    end
  end

  def self.seed!(db)
    # Default globals
    db[:globals].insert_conflict(:replace).insert(
      handle: "site", name: "Site",
      data: '{"title": "My Site", "description": "A new Liquiditor site"}'
    )

    # Default navigation
    db[:navigations].insert_conflict(:replace).insert(handle: "menu", title: "Main Menu")
    db[:navigation_items].insert(navigation_handle: "menu", title: "Home", url: "/", position: 0)
    db[:navigation_items].insert(navigation_handle: "menu", title: "About", url: "/about", position: 1)

    # Default collection
    db[:collections].insert_conflict(:replace).insert(handle: "page", name: "Pages", routing: ":handle")

    # Default entries
    db[:entries].insert(
      prefix_id: "cnety_#{SecureRandom.hex(12)}",
      collection_handle: "page", handle: "index", title: "Home",
      data: '{"body": "<div>Welcome to your new site!</div>"}',
      published: true
    )
    db[:entries].insert(
      prefix_id: "cnety_#{SecureRandom.hex(12)}",
      collection_handle: "page", handle: "about", title: "About",
      data: '{"body": "<div>About this site.</div>"}',
      published: true
    )

    # Content paths
    db[:content_paths].insert(path: "index", collection_handle: "page", entry_handle: "index", template_handle: "index", layout_handle: "theme")
    db[:content_paths].insert(path: "about", collection_handle: "page", entry_handle: "about", template_handle: "page", layout_handle: "theme")
  end
end
