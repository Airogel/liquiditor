# [Theme Name] Documentation

> **Note:** This is a template. Replace all `[bracketed placeholders]` with your theme's specific information.

## Overview

**Theme Name:** [Theme Name]
**Purpose:** [e.g., "Portfolio for a freelance designer" or "Real estate listings site"]
**Version:** 1.0.0
**Last Updated:** [Date]

[High-level summary: who is this for, what are the primary goals, what makes it unique.]

---

## Table of Contents

1. [Installation](#installation)
2. [Configuration](#configuration)
3. [Project Structure](#project-structure)
4. [Collections & Data Models](#collections--data-models)
5. [Templates & Layouts](#templates--layouts)
6. [Components & Partials](#components--partials)
7. [Stimulus Controllers](#stimulus-controllers)
8. [CSS Architecture](#css-architecture)
9. [Forms](#forms)
10. [Development Workflow](#development-workflow)

---

## Installation

```bash
# Create and install
INSTALL=true rake "create_theme[[theme-name]]"

# Set credentials
# Edit themes/[theme-name]/.env with AIROGEL_API_URL, AIROGEL_ACCOUNT_ID, AIROGEL_API_KEY

# Start dev server
./bin/dev
```

See `docs/CREATING_THEMES.md` for the full setup walkthrough.

---

## Configuration

### Globals

| Handle | Template Access | Fields |
|--------|----------------|--------|
| `site` | `{{ site.title }}` | title, description, [list fields] |
| `[other_global]` | `{{ [handle].[field] }}` | [fields] |

### Navigation Menus

| Handle | Template Access | Purpose |
|--------|----------------|---------|
| `menu` | `{{ navigation.menu }}` | Primary navigation |
| `[other_nav]` | `{{ navigation.[handle] }}` | [Purpose] |

---

## Project Structure

```
themes/[theme-name]/
├── assets/                    # Built files (do not edit directly)
│   ├── application.css        # Compiled Tailwind CSS
│   └── application.js         # Bundled JavaScript
├── css/
│   └── application.tailwind.css  # Tailwind v4 config + custom styles
├── js/
│   ├── application.js         # Stimulus app + imports
│   └── controllers/
│       ├── [name]_controller.js
│       └── ...
├── templates/
│   ├── theme.liquid           # Main layout
│   ├── [page].liquid          # Page templates
│   └── [partial].liquid       # Partials (rendered via {% render %})
├── .env                       # API credentials (gitignored)
├── database.sqlite3           # Local content database
└── package.json
```

---

## Collections & Data Models

### [Collection Name] (`[handle]`)

- **Routing:** `[e.g., blog/:handle]`
- **Template:** `[template].liquid`
- **Layout:** `theme`
- **Purpose:** [Description]

**Key Fields:**

| Field Handle | Type | Description |
|-------------|------|-------------|
| `title` | text | Entry title |
| `body` | rich_text | Main content |
| `[field]` | [type] | [Description] |

**Template access:**
```liquid
<!-- Single entry page -->
{{ [handle].title }}
{{ [handle].body }}

<!-- Index page -->
{% for entry in [handle].entries %}
  <a href="{{ entry.content_path }}">{{ entry.title }}</a>
{% endfor %}
```

*(Repeat for each collection)*

---

## Templates & Layouts

### Layouts

#### `theme.liquid` — Main Layout

Used by: all pages except [exceptions if any].

```liquid
<!doctype html>
<html>
<head>
  {{ content_for_header }}
  {{ 'application.css' | asset_url | stylesheet_tag }}
  {{ 'application.js' | asset_url | script_tag: 'default' }}
</head>
<body>
  {% render 'header', navigation: navigation, site: site %}
  <main>{{ content_for_layout }}</main>
  {% render 'footer', site: site %}
  {% cms_scripts %}
</body>
</html>
```

### Page Templates

| Template | Collection | Purpose |
|----------|-----------|---------|
| `index.liquid` | `page` (handle: `index`) | Homepage |
| `page.liquid` | `page` | Generic pages |
| `[name].liquid` | `[collection]` | [Purpose] |

---

## Components & Partials

| File | Render call | Required variables | Purpose |
|------|------------|-------------------|---------|
| `header.liquid` | `{% render 'header', navigation: navigation, site: site %}` | `navigation`, `site` | Site header and nav |
| `footer.liquid` | `{% render 'footer', site: site %}` | `site` | Site footer |
| `[name].liquid` | `{% render '[name]', [var]: [var] %}` | `[var]` | [Purpose] |

**Important:** Variables are NOT automatically available inside partials. Always pass them explicitly in the `{% render %}` call.

---

## Stimulus Controllers

| File | Controller ID (`data-controller`) | Purpose |
|------|----------------------------------|---------|
| `[name]_controller.js` | `[name]` | [What it does] |

### Passing Data from Liquid to Controllers

Use `data-*-value` attributes — never embed `{{ }}` tags inside JS files:

```liquid
<div data-controller="[name]"
     data-[name]-url-value="{{ some_liquid_variable }}">
```

```javascript
// In the controller
connect() {
  console.log(this.urlValue); // the Liquid value
}
```

---

## CSS Architecture

- **Framework:** Tailwind CSS v4 (CSS-native config)
- **Entry point:** `css/application.tailwind.css`
- **Build output:** `assets/application.css`

### Design Tokens (in `@theme {}`)

```css
@theme {
  --color-brand:   [hex];   /* Primary brand color */
  --color-accent:  [hex];   /* Accent color */
  --font-sans:     [stack]; /* Body font */
  --font-display:  [stack]; /* Heading font */
}
```

### Custom Components

[List any reusable CSS component classes defined in the CSS file, e.g.:]

```css
/* Example */
.btn-primary { @apply rounded-full bg-brand px-6 py-2 text-white; }
```

---

## Forms

### [Form Name] (`[form-handle]`)

- **Collection:** `[collection_handle]`
- **Blueprint:** `[blueprint-handle]`
- **Fields:** [field1 (type), field2 (type), ...]
- **Honeypot:** Enabled / Disabled
- **Redirect:** `[URL]`
- **Success message:** `"[Message]"`

```liquid
{% form_for form: "[form-handle]", class: "space-y-4" %}
  {% if form.has_errors %}
    <p class="text-red-600">Please correct the errors below.</p>
  {% endif %}

  <input
    type="text"
    name="fields[name]"
    value="{{ form.values.name }}"
    required
  >

  <button type="submit" data-collection-form-target="submit">Submit</button>
{% endform_for %}
```

**Remember:** `{% cms_scripts %}` must be in the layout for forms to work.

---

## Development Workflow

### Local Development

```bash
./bin/dev
# → http://localhost:4567
```

### Making Changes

| What changed | Action needed |
|-------------|---------------|
| `.liquid` template | Browser reloads automatically |
| `css/` source | Tailwind watcher rebuilds → browser reloads |
| `js/` source | esbuild watcher rebuilds → browser reloads |
| Content (SQLite) | Reload page; or run `download_database` after API changes |

### Syncing to Live CMS

```bash
# After template/asset changes
bin/airogelcms [theme-name] upload_templates
bin/airogelcms [theme-name] upload_assets

# After content API changes, sync local SQLite
bin/airogelcms [theme-name] download_database
```

### Useful Debug Commands

```bash
# Check what templates are on the live CMS
bin/airogelcms [theme-name] list_templates

# Check local SQLite content
sqlite3 themes/[theme-name]/database.sqlite3 "SELECT collection_handle, handle, title FROM entries"

# Check content paths (URL → template mapping)
sqlite3 themes/[theme-name]/database.sqlite3 "SELECT path, template_handle FROM content_paths"
```

---

## Troubleshooting

### Content renders blank

The entry variable name must match the collection handle exactly. If the collection handle is `posts`, use `{{ posts.title }}`, not `{{ post.title }}`.

### Partial renders blank

Pass all required variables to the partial:
```liquid
{% render 'my_partial', navigation: navigation, site: site %}
```

### Form doesn't appear

Verify `{% cms_scripts %}` is in `theme.liquid` and the form handle in `{% form_for form: "handle" %}` exactly matches the CMS form handle (underscores vs hyphens matter).

### Local preview doesn't match live site

Run a full sync: `bin/airogelcms [theme-name] download_theme`. This refreshes templates, assets, and the local SQLite database from the live CMS.
