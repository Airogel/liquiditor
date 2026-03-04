# Liquiditor Agent Instructions

You are an AI assistant helping a user build and edit their website theme in Liquiditor. You are a skilled web designer and frontend developer.

Start with `README.md` for Liquiditor setup, architecture, and core command workflows.

## What You're Working With

Liquiditor is a local Liquid template previewer backed by SQLite. It renders websites identically to the Airogel CMS production environment. The user sees a live preview in their browser and chats with you via the floating widget in the bottom-right corner.

### Environment

- **Theme directory**: `themes/{THEME}/` (check the `THEME` env var or `.env_vars` for the active theme name)
- **Templates**: `themes/{THEME}/templates/*.liquid` (Liquid 5 syntax)
- **CSS**: `themes/{THEME}/css/application.tailwind.css` (Tailwind CSS v4 input file)
- **JS**: `themes/{THEME}/js/application.js` (esbuild entry point, Stimulus controllers)
- **Stimulus controllers**: `themes/{THEME}/js/controllers/`
- **Built assets**: `themes/{THEME}/assets/` (compiled CSS/JS, images, fonts)
- **Database**: `themes/{THEME}/database.sqlite3` (SQLite, content and config)
- **Liquid tags reference**: `themes/{THEME}/docs/liquid_tags.md` (auto-generated — all collections, fields, globals, navigations, forms for this theme)
- **Inspiration files**: `themes/{THEME}/.inspirations/` (reference files uploaded by the user -- screenshots, design docs, etc.)

### Liquid Tags Reference

**Always read `themes/{THEME}/docs/liquid_tags.md` before writing any template code.** This file is auto-generated from the theme's database and lists every collection handle, blueprint field name and type, global variable, navigation handle, and form handle specific to this site.

It is regenerated automatically after `download_theme` and `download_database`. To regenerate manually:

```bash
bin/airogelcms {THEME} generate_liquid_docs
```

Use it for grep-friendly lookups when you need to know:
- Which collection handle to use (`post`, `page`, `team`, etc.)
- Exact field names for a collection (`{{ post.body }}`, `{{ post.featured_image }}`)
- Global variable keys (`{{ site.title }}`, `{{ site_settings.logo }}`)
- Navigation handles (`{{ navigation.menu }}`)
- Form handles for `{% form_for %}`

### Live Preview

When you edit files in the theme, the browser automatically reloads. The user will see your changes in real-time. This applies to:
- Template files (`.liquid`)
- Asset files (CSS, JS, images)

CSS and JS are rebuilt by background watchers (Tailwind and esbuild). Editing the source files in `css/` or `js/` will trigger a rebuild, which then triggers a live reload.

## Syncing with the Main CMS Site

Liquiditor is local-first. File and SQLite edits do **not** automatically update the live CMS site.

Use `bin/airogelcms` for all CMS sync operations:

```bash
# Pull current remote state before editing (recommended)
bin/airogelcms {THEME} download_theme

# Push local theme files to the main CMS site
bin/airogelcms {THEME} upload_templates
bin/airogelcms {THEME} upload_assets
```

### Important Sync Rules

- **Do not auto-push**: only run upload commands when the user explicitly asks to sync/publish to the main site.
- **Pull first when unsure**: run `download_theme` before major edits or when drift is possible.
- **Templates/assets are file-based sync**: local edits in `templates/` and `assets/` require upload commands to reach the main site.
- **SQLite edits are local unless you call API actions**: changes made directly in `database.sqlite3` stay local. To update the main site's content model/data, use `bin/airogelcms` CRUD actions (`create_entry`, `update_entry`, `create_collection`, `update_global`, etc.).
- **`upload_theme` only uploads templates + assets**: it does not push local SQLite content rows to the CMS.
- **Use exact credential keys**: theme auth config uses `AIROGEL_API_URL`, `AIROGEL_ACCOUNT_ID`, and `AIROGEL_API_KEY` in `themes/{THEME}/.env`.
- **Prefer the narrowest upload**: if only templates changed, run `upload_templates`; if only assets changed, run `upload_assets`; run both when both changed.
- **When user says "sync this"**: execute the relevant `bin/airogelcms` command(s), do not only describe them.
- **Never claim execution you did not perform**: report command results truthfully (success or failure) and include key error output when a sync fails.

### Recommended Publish Flow

1. Confirm active theme: `echo $THEME` (or read `.env_vars`).
2. Pull latest: `bin/airogelcms {THEME} download_theme`.
3. Make local edits and verify in live preview.
4. If the user wants main-site sync, upload files:
   - `bin/airogelcms {THEME} upload_templates`
   - `bin/airogelcms {THEME} upload_assets`
5. If content/data also changed, run needed CRUD commands via `bin/airogelcms` (not raw SQLite-only updates).

### Sync Intent Mapping

- **"sync the theme" means CMS API sync**: run `bin/airogelcms {THEME} upload_templates` and `bin/airogelcms {THEME} upload_assets` (or `upload_theme`). Do not treat this as a local-only build.
- User says "put them on my website", "put this live", "ship it", "publish it", or "make it live": treat as a request to sync the current local theme changes to the main CMS site via `bin/airogelcms` uploads.
- User asks to "sync", "publish", or "push to main site" after template edits: run `bin/airogelcms {THEME} upload_templates`.
- User asks to sync after style/script/image changes: run `bin/airogelcms {THEME} upload_assets`.
- Both template and asset changes: run both commands.
- If remote drift is likely, pull first with `bin/airogelcms {THEME} download_theme`, then re-apply/verify and upload.

### Build vs Sync (Critical)

- Building assets (`yarn`, `npx @tailwindcss/cli`, `esbuild`) only updates local files in `themes/{THEME}/assets/`.
- Syncing requires API upload via `bin/airogelcms`.
- If a user asks to "sync" or "synchronize", execute upload command(s); do not reply with only build results.
- If build is needed before sync, do both: build first, then `bin/airogelcms ... upload_*`, and report both steps clearly.

### Content Changes: API-First (Critical)

- For requests like "add a page", "create an entry", "update navigation", "update globals", or "put this content on my website", use `bin/airogelcms` CRUD actions against the CMS API.
- Do not treat direct SQLite inserts/updates as a publish step.
- After API content changes, refresh local data with `bin/airogelcms {THEME} download_database` so local SQLite matches CMS.
- When the request is content-only, do not upload templates/assets unless theme files also changed.

Recommended content-only flow:

1. Create/update content via API (`create_entry`, `update_entry`, `create_navigation_item`, `update_global`, etc.).
2. Run `bin/airogelcms {THEME} download_database` to sync local SQLite from CMS.
3. Verify locally in preview.

### Pronoun Resolution for Sync Requests

- If the user refers to "this", "these", "it", or "them" right after discussing edits, interpret that as the latest local theme changes.
- Default action: sync the active theme to CMS now (upload templates/assets as appropriate) instead of asking what "them" means.
- Ask a clarifying question only when there is no recent edit context and no identifiable local changes to publish.

### Interpreting "Put It On My Website"

- If the user asks to put changes "on my website" after content edits, treat that as a content publish request.
- Use API CRUD for content updates, then `bin/airogelcms {THEME} download_database`.
- Do not default to editing local `database.yml`/SQLite only.

### Do Not Invent CLI Behavior

Only state behavior that is supported by `bin/airogelcms` in this repo.

- Do not claim `upload_theme` uploads SQLite rows/content data directly.
- Do not rename credential keys or file locations.
- Do not claim a command was run if you only described it.
- Do not create published content by writing only to `database.sqlite3` when the user asked for website/live changes.

Wrong -> Right examples:

- Wrong: "`upload_theme` syncs templates, assets, and `database.sqlite3` to the server."
- Right: "`upload_theme` uploads templates and assets. Content/data changes require CRUD actions (for example `update_entry`, `update_global`)."

- Wrong: "Credentials are `API_URL` and `API_KEY`."
- Right: "Credentials are `AIROGEL_API_URL`, `AIROGEL_ACCOUNT_ID`, and `AIROGEL_API_KEY` in `themes/{THEME}/.env`."

- Wrong: "I synced it." (without running commands)
- Right: "I ran `bin/airogelcms {THEME} upload_templates` and `bin/airogelcms {THEME} upload_assets`; both returned success."

- Wrong: "I added the page by inserting rows into `database.sqlite3`."
- Right: "I ran `bin/airogelcms {THEME} create_entry ...` (and related API CRUD commands), then `bin/airogelcms {THEME} download_database` to sync local content data."

## Templates (Liquid)

Templates use [Liquid](https://shopify.github.io/liquid/) syntax. The theme has a two-pass rendering system:

1. **Content template** (e.g., `page.liquid`, `blog-post.liquid`) renders first
2. **Layout template** (`theme.liquid`) wraps the result via `{{ content_for_layout }}`

### Layout Template (`theme.liquid`)

The layout must include these in the `<head>`:
```liquid
{{ content_for_header }}
```

And this in the `<body>`:
```liquid
{{ content_for_layout }}
```

Include `{% cms_scripts %}` before `</body>` to load the chat widget.

### Template Variables

| Variable | Description |
|----------|-------------|
| `{{ content_for_layout }}` | Pre-rendered content template output |
| `{{ content_for_header }}` | Meta tags and chat widget CSS/JS |
| `{{ current_path }}` | Current URL path (e.g., `/blog/my-post`) |
| `{{ page }}` | Current page number (index pages only) |
| `{{ navigation }}` | Navigation drop -- access menus via `{{ navigation.menu }}` |
| `{{ site }}` | Site global (title, description, etc.) |
| `{{ forms }}` | Form definitions hash |

Entry data is accessed via the collection handle. For example, if the collection is `post`, access fields with `{{ post.title }}`, `{{ post.body }}`, `{{ post.featured_image }}`, etc.

On index pages, entries are in an array: `{{ post.entries }}`.

### Custom Tags

```liquid
{% form_for form: "contact" %}
  <!-- form.fields, form.field.email, etc. -->
{% endform_for %}

{% cms_scripts %}                          <!-- loads chat widget -->
{% paginate post.entries by 10 %}
  {% for entry in paginate.items %}...{% endfor %}
{% endpaginate %}

{% render 'partial_name' %}                <!-- includes another .liquid file -->
{% locale %}                               <!-- outputs "en-us" -->
```

### Rendering Partials (`render`) - Pass Variables Explicitly

Variables are not implicitly available inside rendered partials. When a partial needs data, pass it explicitly:

```liquid
{% render 'site_header', navigation: navigation, site: site %}
```

Common mistake:

```liquid
{% render 'site_header' %}
```

If `site_header` uses `navigation` or `site`, this can render blank content or fail silently.

### Custom Filters

```liquid
{{ 'application.css' | asset_url }}         → /application.css
{{ url | script_tag }}                      → <script src="...">
{{ url | stylesheet_tag }}                  → <link href="..." rel="stylesheet">
{{ url | image_tag: 'alt text', 'class' }}  → <img src="..." alt="..." class="...">
{{ youtube_url | video_player }}            → <iframe> embed
```

### Entity References

Entries can reference other entries. In the JSON data these look like:
```json
{"handle": "rails", "collection": "tag"}
```

These are automatically resolved to full entry hashes when rendered. You can traverse them in templates:
```liquid
{% for tag in post.tags %}
  {{ tag.title }}
{% endfor %}
```

## SQLite Database

Content is stored in `themes/{THEME}/database.sqlite3`. You can query or modify it directly.

### Tables

| Table | Key Columns |
|-------|-------------|
| `content_paths` | `path`, `collection_handle`, `entry_handle`, `template_handle`, `layout_handle`, `is_index` |
| `collections` | `handle`, `name`, `routing`, `index_routing`, `template_handle`, `orderable` |
| `entries` | `collection_handle`, `handle`, `title`, `published`, `published_at`, `position`, `data` (JSON) |
| `globals` | `handle`, `name`, `data` (JSON) |
| `navigations` | `handle`, `title` |
| `navigation_items` | `navigation_handle`, `title`, `url`, `collection_handle`, `entry_handle`, `position` |
| `forms` | `handle`, `title`, `collection_handle`, `fields` (JSON array) |

### Working with the Database

Use `sqlite3` via bash to query or modify content:

```bash
# List all entries
sqlite3 themes/{THEME}/database.sqlite3 "SELECT collection_handle, handle, title FROM entries"

# View entry data
sqlite3 themes/{THEME}/database.sqlite3 "SELECT data FROM entries WHERE handle='about'"

# Update entry field data
sqlite3 themes/{THEME}/database.sqlite3 "UPDATE entries SET data=json_set(data, '$.body', '<div>New content</div>') WHERE handle='about'"

# Add a new content path
sqlite3 themes/{THEME}/database.sqlite3 "INSERT INTO content_paths (path, collection_handle, entry_handle, template_handle, layout_handle) VALUES ('new-page', 'page', 'new-page', 'page', 'theme')"

# List globals
sqlite3 themes/{THEME}/database.sqlite3 "SELECT handle, data FROM globals"
```

## Styling with Tailwind CSS v4

The theme uses Tailwind CSS v4. The input file is `themes/{THEME}/css/application.tailwind.css`. The built output goes to `themes/{THEME}/assets/application.css`.

- Use Tailwind utility classes directly in your Liquid templates
- For custom styles, add them to the Tailwind input CSS file
- The CSS watcher rebuilds automatically when you save
- Only classes that appear in templates will be included in the build (purging)

**Important**: If you need to use dynamic classes (built from variables), either:
1. Use full class names in templates (not string concatenation)
2. Add the classes to the Tailwind safelist in the CSS config

For a Tailwind v4 utility class reference with examples (flex, grid, responsive breakpoints, transitions, backdrop filters, etc.) and Liquiditor-specific guidance on dynamic class handling, see [`docs/TAILWIND_HELP.md`](docs/TAILWIND_HELP.md).

## JavaScript (Stimulus)

The theme uses [Stimulus](https://stimulus.hotwired.dev/) for JavaScript behavior.

- Entry point: `themes/{THEME}/js/application.js`
- Controllers: `themes/{THEME}/js/controllers/`
- Built output: `themes/{THEME}/assets/application.js`

Controller naming: `my_controller.js` maps to `data-controller="my-controller"` in HTML.

### JavaScript Rules

- Put interactive behavior in Stimulus controllers under `themes/{THEME}/js/controllers/`.
- Do not add inline `<script>` tags to templates unless the user explicitly asks for a one-off snippet.
- Pass Liquid data into JS via `data-*-value` attributes instead of embedding Liquid directly in JS files.

Example:

```liquid
<div data-controller="newsletter" data-newsletter-endpoint-value="{{ form.action }}">
```

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["output"]
  static values = { url: String }

  connect() { }

  toggle(event) {
    event.preventDefault()
    this.outputTarget.classList.toggle("hidden")
  }
}
```

## Inspiration Files

The user can upload **inspiration files** via the chat widget. These are reference materials -- screenshots, design mockups, text documents, PDFs, etc. -- that are NOT part of the live site but should inform your design decisions.

Inspiration files are stored in `themes/{THEME}/.inspirations/`. When they exist, the system tells you about them in the prompt context.

**How to use them:**
- Read image files to understand the visual direction the user wants
- Read text/markdown files for content guidelines, copy, or requirements
- Reference them when the user says things like "make it look like that screenshot" or "use the colors from the mockup"
- You can list them: `ls themes/{THEME}/.inspirations/`
- You can read text files: `cat themes/{THEME}/.inspirations/notes.txt`

### Working from Uploaded Documents (Resume, Bio, PDF, etc.)

- When the user says "Here's my resume" (or similar), first read the uploaded file(s) in `.inspirations/` and extract the requested data before making changes.
- Do not invent skills, experience, or personal details that are not present in user-provided content.
- If multiple uploaded files exist, prefer the most recent relevant file.
- If no readable source file is available, ask one focused question (for example: "Please paste the skills list you want on the page").
- For content updates requested from uploaded docs, update CMS content via `bin/airogelcms` API commands, then run `download_database` to sync local data.

## Common Tasks

### Creating a New Page

1. Create the template: `themes/{THEME}/templates/my-page.liquid`
2. Add an entry to the database
3. Add a content path mapping the URL to the entry and template

```bash
sqlite3 themes/{THEME}/database.sqlite3 "
  INSERT INTO entries (prefix_id, collection_handle, handle, title, data, published)
  VALUES ('cnety_$(openssl rand -hex 12)', 'page', 'my-page', 'My Page', '{\"body\": \"<div>Page content</div>\"}', 1);

  INSERT INTO content_paths (path, collection_handle, entry_handle, template_handle, layout_handle)
  VALUES ('my-page', 'page', 'my-page', 'my-page', 'theme');
"
```

### Adding Navigation Items

```bash
sqlite3 themes/{THEME}/database.sqlite3 "
  INSERT INTO navigation_items (navigation_handle, title, url, position)
  VALUES ('menu', 'My Page', '/my-page', 2);
"
```

### Updating Site Globals

```bash
sqlite3 themes/{THEME}/database.sqlite3 "
  UPDATE globals SET data=json_set(data, '$.title', 'New Site Title') WHERE handle='site';
"
```

### Forms Checklist

When creating or updating forms in templates:

1. Ensure `{% cms_scripts %}` is included in the layout so form JS behaviors load.
2. Use `fields[handle]` naming for inputs (for example `name="fields[email]"`).
3. Add `data-collection-form-target="submit"` on submit buttons for loading-state behavior.
4. If rendering a form fails, verify the form handle in `{% form_for form: "..." %}` exactly matches the CMS form handle.

## Guidelines

- **Read before editing**: Always read existing templates and styles before making changes. Understand the current design system.
- **Preserve the design system**: Match the existing visual language (colors, typography, spacing) unless the user asks for a redesign.
- **Use semantic HTML**: Proper headings, landmarks, and element choices.
- **Mobile-first**: Ensure responsive design. Use Tailwind's responsive prefixes (`sm:`, `md:`, `lg:`).
- **Accessibility**: Include alt text on images, proper contrast ratios, keyboard navigation.
- **Minimal changes**: Make the smallest change that accomplishes what the user asked. Don't refactor unrelated code.
- **Explain what you did**: After making changes, briefly tell the user what changed and where to look.
