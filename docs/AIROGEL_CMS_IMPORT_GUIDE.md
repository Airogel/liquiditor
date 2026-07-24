# Airogel CMS Import Guide

This guide covers the workflow for importing content into Airogel CMS and syncing it with a Liquiditor local theme. It documents the `bin/airogelcms` CLI tool, the SQLite-backed local data model, and the correct order of operations for migrations (e.g., from WordPress).

## Table of Contents

1. [How Liquiditor + CMS Sync Works](#how-liquiditor--cms-sync-works)
2. [Import Order of Operations](#import-order-of-operations)
3. [CLI Tool Reference](#cli-tool-reference)
4. [MCP-Direct Workflow (No CLI/API Key Required)](#mcp-direct-workflow-no-cliapi-key-required)
5. [Template Variables](#template-variables)
6. [Routing Patterns](#routing-patterns)
7. [WordPress Import Workflow](#wordpress-import-workflow)
8. [Handling Missing or Dead Source Media](#handling-missing-or-dead-source-media)
9. [Common Pitfalls](#common-pitfalls)

---

## How Liquiditor + CMS Sync Works

Liquiditor is **local-first**. It renders pages using a local SQLite database (`themes/{THEME}/database.sqlite3`). The live Airogel CMS site is a separate system. You must explicitly sync between them.

```
Local (Liquiditor)                         Remote (Airogel CMS)
──────────────────                         ────────────────────
themes/{THEME}/templates/    ←→  upload_templates / download_templates
themes/{THEME}/assets/       ←→  upload_assets    / download_assets
themes/{THEME}/database.sqlite3            (not directly synced)
       ↑
  imported from database.yml
  (downloaded via download_database)
```

### Key Rules

- `upload_theme` / `upload_templates` / `upload_assets` — push **files** to CMS only (templates + assets). They do NOT push SQLite content rows.
- `download_database` — fetches `database.yml` from CMS and imports it into SQLite.
- Content/data changes (entries, globals, navigation) require `bin/airogelcms` CRUD commands to update the live CMS. Direct SQLite edits stay local unless you also call the API.
- After any `download_database` or content API call, SQLite is updated from `database.yml` automatically.

---

## Import Order of Operations

**Critical: Follow this order. Dependencies flow downward.**

```
1. Parse Source Data (WordPress XML, CSV, etc.)

2. Create Blueprint(s)
   └── Define field schemas before creating collections

3. Create Collection(s)
   └── Reference blueprints via --blueprint_handle
   └── Set routing pattern
   └── Do NOT set template_handle/layout_handle yet

4. Download & Upload Assets
   └── Download remote assets (bin/airogelcms {THEME} download_remote_asset --url=...)
   └── Upload to CMS (bin/airogelcms {THEME} upload_assets)

5. Create Entries
   └── Use bin/airogelcms CRUD (create_entry), not raw SQLite inserts
   └── Include published_at for date-based routing

6. Upload Templates
   └── bin/airogelcms {THEME} upload_templates

7. Update Collections with Templates
   └── NOW set template_handle and layout_handle

8. Create Navigation (optional)
   └── create_navigation first, then create_navigation_item

9. Create/Update Globals (optional)

10. Sync local SQLite
    └── bin/airogelcms {THEME} download_database
```

---

## CLI Tool Reference

### General Usage

```bash
bin/airogelcms <theme_name> <action> [--option=value ...]
```

All CRUD actions output JSON. Theme operations (upload/download) print human-readable progress.

### Theme Sync Operations

```bash
# Pull everything from CMS (database + templates + assets), updates SQLite
bin/airogelcms {THEME} download_theme

# Pull just database.yml and re-import into SQLite
bin/airogelcms {THEME} download_database

# Pull just templates
bin/airogelcms {THEME} download_templates

# Pull just assets
bin/airogelcms {THEME} download_assets

# Push templates + assets to CMS
bin/airogelcms {THEME} upload_theme

# Push only templates
bin/airogelcms {THEME} upload_templates

# Push only assets
bin/airogelcms {THEME} upload_assets
```

**Prefer the narrowest upload.** If only templates changed, run `upload_templates`. If only assets changed, run `upload_assets`.

### Blueprints

```bash
# List all blueprints
bin/airogelcms {THEME} list_blueprints

# Create blueprint with fields
bin/airogelcms {THEME} create_blueprint \
  --handle=blog-post \
  --title="Blog Post" \
  --fields='[
    {"handle":"body","type":"rich_text","position":1},
    {"handle":"excerpt","type":"text","position":2},
    {"handle":"featured_image","type":"image","position":3},
    {"handle":"categories","type":"list","position":4}
  ]'

# Get a blueprint
bin/airogelcms {THEME} get_blueprint --id=blog-post

# Update a blueprint
bin/airogelcms {THEME} update_blueprint --id=blog-post --title="Updated Title"

# Delete a blueprint
bin/airogelcms {THEME} delete_blueprint --id=blog-post
```

**Field Types:**

| Type | Description |
|------|-------------|
| `text` | Plain text |
| `rich_text` | HTML content (Trix/ActionText editor) |
| `raw_html` | Raw HTML — stored and rendered verbatim, no sanitization |
| `image` | Image attachment |
| `video` | Video embed |
| `gallery` | Multiple images |
| `toggle` | Boolean |
| `enumerate` | Select/dropdown |
| `list` | Repeatable items |
| `dictionary` | Key-value pairs |
| `entity` | Reference to another entry |
| `collection` | Dynamic collection query |

### Collections

```bash
# List collections
bin/airogelcms {THEME} list_collections

# Create collection
bin/airogelcms {THEME} create_collection \
  --name="Blog Posts" \
  --handle=posts \
  --routing=":year/:month/:day/:handle" \
  --orderable=descending \
  --blueprint_handle=blog-post

# Create collection with root routing (pages at /)
bin/airogelcms {THEME} create_collection \
  --name="Pages" \
  --handle=page \
  --routing=":handle" \
  --root_routing=true \
  --blueprint_handle=page

# Update collection (add templates AFTER they're uploaded)
bin/airogelcms {THEME} update_collection \
  --id=posts \
  --template_handle=post \
  --layout_handle=theme

# Get / delete
bin/airogelcms {THEME} get_collection --id=posts
bin/airogelcms {THEME} delete_collection --id=posts
```

### Entries

```bash
# List entries in a collection
bin/airogelcms {THEME} list_entries --collection=posts

# Create entry (blueprint fields passed as flat options)
bin/airogelcms {THEME} create_entry \
  --collection=posts \
  --handle=my-first-post \
  --title="My First Post" \
  --published=true \
  --published_at="2024-06-15T10:00:00Z" \
  --body="<p>Content here...</p>" \
  --excerpt="A brief summary"

# Get / update / delete
bin/airogelcms {THEME} get_entry    --collection=posts --id=my-first-post
bin/airogelcms {THEME} update_entry --collection=posts --id=my-first-post --title="Updated"
bin/airogelcms {THEME} delete_entry --collection=posts --id=my-first-post
```

**Key Notes:**
- Entries auto-inherit the blueprint from their collection — no `--blueprint_handle` needed on `create_entry`
- `published_at` is required for date-based routing patterns
- Blueprint field values are passed as flat `--field_handle=value` options
- Response includes `content_path` showing the generated URL

### Navigation

```bash
# List navigations
bin/airogelcms {THEME} list_navigations

# Create navigation (items added separately)
bin/airogelcms {THEME} create_navigation --handle=main --title="Main Menu"

# Add navigation items
bin/airogelcms {THEME} create_navigation_item \
  --navigation=main \
  --title="Home" \
  --url="/"

bin/airogelcms {THEME} create_navigation_item \
  --navigation=main \
  --title="Blog" \
  --url="/blog"

# List / update / delete items
bin/airogelcms {THEME} list_navigation_items --navigation=main
bin/airogelcms {THEME} update_navigation_item --navigation=main --id=<id> --title="New Title"
bin/airogelcms {THEME} delete_navigation_item --navigation=main --id=<id>
```

### Globals

```bash
# List globals
bin/airogelcms {THEME} list_globals

# Create global with fields
bin/airogelcms {THEME} create_global \
  --handle=site \
  --title="Site Settings" \
  --fields='[{"handle":"site_name","type":"text","position":1}]' \
  --site_name="My Website"

# Update global field value
bin/airogelcms {THEME} update_global --id=site --site_name="New Name"
```

### WordPress Parser

```bash
# Parse WordPress XML export (all content types)
bin/airogelcms {THEME} parse_wordpress --file=export.xml --type=all

# Parse specific type
bin/airogelcms {THEME} parse_wordpress --file=export.xml --type=posts
bin/airogelcms {THEME} parse_wordpress --file=export.xml --type=pages
bin/airogelcms {THEME} parse_wordpress --file=export.xml --type=attachments
bin/airogelcms {THEME} parse_wordpress --file=export.xml --type=categories
bin/airogelcms {THEME} parse_wordpress --file=export.xml --type=menus
```

Output is JSON with `posts`, `pages`, `attachments`, `categories`, `tags`, `menus`, and `site` keys.

### Asset Tools

```bash
# Download a single remote asset (preserves path structure by default)
bin/airogelcms {THEME} download_remote_asset \
  --url="https://example.com/wp-content/uploads/2024/photo.jpg"
# → downloaded to themes/{THEME}/assets/wp-content/uploads/2024/photo.jpg

# Extract asset URLs from HTML
bin/airogelcms {THEME} extract_asset_urls --html="<img src='https://example.com/img.jpg'>"
bin/airogelcms {THEME} extract_asset_urls --file=page.html
```

---

## MCP-Direct Workflow (No CLI/API Key Required)

If you (or the agent doing the import) have an authenticated Airogel CMS MCP connection, you can skip `bin/airogelcms` and the `.env` API key entirely and call the MCP tools directly: `blueprints_save`, `collections_save`, `templates_save`, `assets_upload_from_url`, `entries_save`, `navigation_items_save`, `globals_save`. This is usually faster for a one-off import because there's no theme scaffold or credential setup required first.

Still parse the WordPress export locally first — `lib/wordpress_parser.rb` (see below) has no MCP dependency, so run it with plain `ruby`/`bin/airogelcms parse_wordpress` regardless of which path you use for the CMS side.

**Before writing anything:**

1. `accounts_list` — confirm the target account and note whether it already has starter/boilerplate content (a fresh account is usually pre-seeded with a generic template: Contact, Events, Newsletter, News collections, a `page` collection with placeholder entries, `main_navigation`, and a `site` global). List `collections_list`, `blueprints_list`, `entries_list` for `page`, and `navigation_items_list` for `main_navigation` before creating anything, so you don't collide with or blindly overwrite existing handles (e.g. an `about` page entry may already exist — update it in place rather than creating a duplicate).
2. `templates_get` for `theme` (the layout) and any existing content template (e.g. `news_post`/`news_index`) to learn the site's actual CSS class vocabulary (e.g. `card-grid`, `page-header`, `prose`, `text-link`). Reuse those classes in new templates instead of inventing new ones or assuming a Tailwind utility-class setup — starter themes here use hand-written semantic classes, not utility classes.
3. `theme_generate_liquid_docs` — canonical, per-account reference for exact global/collection/navigation/form variable names. Always regenerate and read this before writing new Liquid, per the account's own MCP server instructions.

**Creation order** mirrors the CLI order of operations: blueprint(s) → collection → assets → templates → link templates onto the collection (`collections_save` again with `template_handle`/`index_template_handle`) → entries → navigation → globals.

**QC before calling it done:**

- `theme_validate` — flags missing templates, orphaned entries, missing `published_at` on date-routed collections, missing index config, duplicate content paths. Re-run after entries are created.
- `preview_render_path` for the index page, at least one normal entry, and any edge-case entry (e.g. one missing an optional field like an image) — check `status: "ok"` and eyeball the rendered HTML. This is more trustworthy than the raw `entries_save`/`entries_get` response for verifying field values actually resolve (see the image-field gotcha below).

---

## Template Variables

### Critical: Variable Name = Collection Handle

The entry variable name in templates **must match the collection handle**. There is no error — it just renders blank.

| Collection Handle | Correct Variable | Wrong Variable |
|------------------|-----------------|----------------|
| `posts` | `{{ posts.title }}` | `{{ post.title }}` |
| `page` | `{{ page.title }}` | `{{ pages.title }}` |
| `products` | `{{ products.price }}` | `{{ product.price }}` |

### Single Entry Template Example

For a collection with handle `posts`:

```liquid
<article>
  <h1>{{ posts.title }}</h1>
  <time>{{ posts.published_at | date: "%B %d, %Y" }}</time>
  <div class="content">{{ posts.body }}</div>
</article>
```

### Index Page — Entries Array

On collection index pages, entries are in an array accessible via `{handle}.entries`:

```liquid
{% for post in posts.entries %}
  <a href="{{ post.content_path }}">{{ post.title }}</a>
{% endfor %}
```

With pagination:

```liquid
{% paginate posts.entries by 10 %}
  {% for post in paginate.items %}
    <a href="{{ post.content_path }}">{{ post.title }}</a>
  {% endfor %}
  {{ paginate.links }}
{% endpaginate %}
```

### Always-Available Variables

```liquid
{{ content_for_layout }}    <!-- In layouts: pre-rendered content template -->
{{ content_for_header }}    <!-- Meta tags, SEO -->
{{ current_path }}          <!-- e.g., /blog/my-post -->
{{ navigation.main }}       <!-- Navigation items by handle -->
{{ site.title }}            <!-- From 'site' global -->
```

### Layout Template (theme.liquid)

```liquid
<!DOCTYPE html>
<html>
<head>
  {{ content_for_header }}
  {{ 'application.css' | asset_url | stylesheet_tag }}
</head>
<body>
  {% render 'header', navigation: navigation, site: site %}
  <main>
    {{ content_for_layout }}
  </main>
  {% render 'footer', site: site %}
  {{ 'application.js' | asset_url | script_tag }}
  {% cms_scripts %}
</body>
</html>
```

---

## Routing Patterns

### Supported Placeholders

| Placeholder | Source | Example |
|-------------|--------|---------|
| `:handle` | Entry handle | `my-post` |
| `:year` | Year from `published_at` | `2024` |
| `:month` | Month from `published_at` | `06` |
| `:day` | Day from `published_at` | `15` |

### Examples

| Routing Pattern | Entry Handle | published_at | Generated URL |
|-----------------|-------------|--------------|---------------|
| `blog/:handle` | `my-post` | any | `/blog/my-post` |
| `:handle` + `root_routing=true` | `about` | any | `/about` |
| `:year/:month/:day/:handle` | `hello` | 2024-06-15 | `/2024/06/15/hello` |

---

## WordPress Import Workflow

### Complete Step-by-Step

```bash
# Step 1: Parse WordPress export and review
bin/airogelcms myblog parse_wordpress --file=export.xml --type=all

# Step 2: Create blueprint
bin/airogelcms myblog create_blueprint \
  --handle=blog-post \
  --title="Blog Post" \
  --fields='[
    {"handle":"body","type":"rich_text","position":1},
    {"handle":"excerpt","type":"text","position":2},
    {"handle":"featured_image","type":"image","position":3},
    {"handle":"categories","type":"list","position":4}
  ]'

# Step 3: Create collection (date-based routing like WordPress)
bin/airogelcms myblog create_collection \
  --name="Blog Posts" \
  --handle=posts \
  --routing=":year/:month/:day/:handle" \
  --orderable=descending \
  --blueprint_handle=blog-post

# Step 4: Download assets from WordPress CDN, then upload
# (Use Ruby script for bulk — see below — then:)
bin/airogelcms myblog upload_assets

# Step 5: Create entries (use Ruby script for bulk — see below)

# Step 6: Upload templates
bin/airogelcms myblog upload_templates

# Step 7: Link templates to collection
bin/airogelcms myblog update_collection \
  --id=posts \
  --template_handle=post \
  --layout_handle=theme

# Step 8: Sync local SQLite
bin/airogelcms myblog download_database
```

### Ruby Script for Bulk Entry Import

```ruby
require_relative '../airogel_cms_client'
require_relative '../lib/wordpress_parser'

theme_path = './themes/myblog'
env = AirogelCmsClient.load_theme_env(theme_path)
client = AirogelCmsClient.new(env[:api_url], env[:api_key])
account_id = env[:account_id]

parser = WordPressParser.new("#{theme_path}/export.xml")
data = parser.parse(type: :posts)

data[:posts].each do |post|
  # Strip WordPress block comments
  body = post[:body]
    .gsub(/<!-- wp:.*?-->/m, '')
    .gsub(/<!-- \/wp:.*?-->/m, '')
    .strip

  result = client.create_entry(account_id, 'posts',
    handle: post[:handle],
    title: post[:title],
    published: true,
    published_at: post[:published_at],
    body: body,
    excerpt: post[:excerpt],
    categories: post[:categories]
  )

  puts "#{result['success'] ? 'OK' : 'FAIL'}: #{post[:handle]}"
end
```

---

## Handling Missing or Dead Source Media

A WordPress XML/WXR export contains only **metadata and URLs** for attachments — never the binary files. If the exported site is offline (common for old blogs), every `<wp:attachment_url>` and every inline `<img src>` in `content:encoded` points at a domain that will 404 or fail to resolve. Don't assume `assets_upload_from_url` will work against those URLs; check first.

**1. Check whether the source domain is actually alive:**

```bash
curl -s -o /dev/null -w "%{http_code}\n" --max-time 10 "https://old-site.example.com/wp-content/uploads/2020/01/cover.jpg"
```

Exit code 6 / connection failure means DNS doesn't resolve at all — the domain is gone, not just the file.

**2. If the domain is dead, try the Wayback Machine** before giving up on an image. The plain availability API works with an **unencoded** URL (percent-encoding the URL in the query string causes false "not archived" results):

```bash
curl -s "http://archive.org/wayback/available?url=https://old-site.example.com/wp-content/uploads/2020/01/cover.jpg"
```

If `archived_snapshots.closest.url` is present, insert `id_` right after the timestamp segment to get the **raw file** instead of a wayback-toolbar-wrapped HTML page:

```
http://web.archive.org/web/20220410182347/https://old-site.example.com/...      ← wrapped page
http://web.archive.org/web/20220410182347id_/https://old-site.example.com/...   ← raw file (use this)
```

WordPress often resizes images and rewrites the filename with a `-WIDTHxHEIGHT` suffix (e.g. `Cover-672x1024.jpg`) that the Wayback Machine may not have crawled even when the original full-size file was archived. Try stripping that suffix and re-checking before concluding an image is unrecoverable.

**3. If it's a known published work (book cover, movie poster, product photo), a subject-specific API is often more reliable than either the dead domain or Wayback.** For book covers specifically:

```bash
# Open Library — no API key required
curl -s "https://openlibrary.org/search.json?q=TITLE+AUTHOR&limit=1"
# → take doc.cover_i, then fetch:
# https://covers.openlibrary.org/b/id/{cover_i}-L.jpg
```

Google Books' `volumes` API is a similar fallback but is aggressively rate-limited per-project and may return `429 RESOURCE_EXHAUSTED` with no advance warning — don't rely on it as the only path.

**4. Verify every substitute URL resolves before uploading**, in one pass, rather than discovering failures mid-import:

```python
import urllib.request
req = urllib.request.Request(url, method='HEAD', headers={'User-Agent': 'Mozilla/5.0'})
with urllib.request.urlopen(req, timeout=15) as resp:
    print(resp.status, resp.headers.get('Content-Type'))
```

**5. Strip now-dead `<img>` references out of body HTML** — don't leave them in even though the surrounding text is otherwise fine. A broken inline image is worse than no image. If a post embeds one image that duplicates whatever you set as `featured_image`, drop the inline copy entirely (the template already renders the featured image above the body). If a post has a multi-image gallery you couldn't individually re-source, strip the `<img>` tags but leave any surrounding captions/text — better to lose a decorative image than fabricate one, and better than leaving a broken-image icon in the middle of the article.

**6. Tell the user what you couldn't recover.** Don't silently drop content. If some percentage of images couldn't be sourced from any of the above, say so and name which entries are affected, so they can supply a file directly if they have one squirreled away.

---

## Common Pitfalls

### 1. Template variable doesn't match collection handle

`{{ post.title }}` when collection is `posts` → renders blank, no error. Use `{{ posts.title }}`.

### 2. Setting template_handle before uploading templates

Upload templates first, then update the collection:
```bash
bin/airogelcms {THEME} upload_templates
bin/airogelcms {THEME} update_collection --id=posts --template_handle=post --layout_handle=theme
```

### 3. Missing blueprint_handle on collection creation

Always include it:
```bash
bin/airogelcms {THEME} create_collection --name="Posts" --handle=posts --blueprint_handle=blog-post
```

### 4. Date-based routing without published_at

```bash
# Always include published_at for :year/:month/:day/:handle routing
bin/airogelcms {THEME} create_entry --collection=posts --published_at="2024-06-15T10:00:00Z" ...
```

### 5. Navigation items not appearing

Items must be added separately after creating the navigation:
```bash
bin/airogelcms {THEME} create_navigation --handle=main --title="Main Menu"
bin/airogelcms {THEME} create_navigation_item --navigation=main --title="Home" --url="/"
```

### 6. Forgetting to sync SQLite after API changes

After any content API operation (create/update/delete entries, globals, navigation), run:
```bash
bin/airogelcms {THEME} download_database
```
This pulls the latest `database.yml` from CMS and re-imports it into SQLite so the local preview reflects the change.

### 7. Direct SQLite edits don't reach the live site

SQLite is the local preview database. Edits made directly with `sqlite3` commands are visible in Liquiditor but are NOT sent to the live CMS. To update the live site, use `bin/airogelcms` CRUD commands, then `download_database` to sync local SQLite.

### 8. Passing variables to partials

Variables are NOT automatically available inside `{% render %}` partials. Pass them explicitly:
```liquid
{% render 'header', navigation: navigation, site: site %}
```

### 9. Image blueprint field looks empty after `entries_save`/`entries_get` — it may not be

For a blueprint field of type `image`, set the value to the asset's **`full_path`** (e.g. `"reviews/cover.jpg"`, from the `assets_upload_from_url`/`assets_list` response) — not the asset's `id` (`actast_...`) and not its `url`. Both of those alternatives silently fail to attach.

The confusing part: even when set correctly, the `fields` object in the `entries_save`/`entries_get` JSON response shows the image field as `{"name":"image","record":{...,"data":{}}}` — indistinguishable from an unset field by eye. **Don't trust that response to verify an image field.** Use `preview_render_path` on the entry and check that the rendered `<img src>` is a real asset URL — that's the only reliable confirmation.

### 10. `bin/airogelcms parse_wordpress` requires `lib/wordpress_parser.rb`, which may not exist

The CLI (`bin/airogelcms`) and this doc both reference `lib/wordpress_parser.rb`, but depending on the state of the repo it may not actually be present — check before assuming `parse_wordpress` works. It needs to expose:

```ruby
WordPressParser.new(file_path).parse(type: :all) # or :posts, :pages, :attachments, :categories, :tags, :menus, :site
# => { posts: [...], pages: [...], attachments: [...], categories: [...], tags: [...], menus: [...], site: {...} }
```

Built on `nokogiri` (already in the `Gemfile`) against the WXR namespaces (`wp:`, `content:`, `excerpt:`, `dc:`). Key extraction points:

- Posts/pages: `wp:post_type`, `wp:status` (`publish` → `published: true`), `wp:post_name` (fall back to a slugified title if blank — WordPress sometimes leaves this empty or stuck on a default like `sample-page`), `content:encoded` (body), `excerpt:encoded`, `category[@domain='category']` / `category[@domain='post_tag']` for taxonomy.
- Attachments: `wp:attachment_url`, `wp:post_parent` (links an attachment back to the post that used it).
- Menus: `nav_menu_item` posts, with target info spread across `wp:postmeta` key/value pairs (`_menu_item_type`, `_menu_item_object_id`, `_menu_item_url`, `_menu_item_menu_item_parent`) rather than plain fields.
- Strip Gutenberg block comments (`<!-- wp:... -->` / `<!-- /wp:... -->`) from `content:encoded` before using it as HTML — they're WordPress editor metadata, not meant to render.
