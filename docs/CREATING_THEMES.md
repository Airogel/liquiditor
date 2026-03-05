# Creating Themes in Liquiditor

This guide covers how to scaffold a new theme, configure it, and connect it to an Airogel CMS account.

## Quick Start

```bash
INSTALL=true rake "create_theme[my_theme]"
./bin/dev
```

That's it for local development. Configure `.env` when you're ready to sync with the live CMS.

---

## Step 1: Scaffold the Theme

### Using the Rake Task (recommended)

```bash
rake "create_theme[theme_name]"
```

With automatic dependency install and initial asset build:

```bash
INSTALL=true rake "create_theme[theme_name]"
```

> **Note for zsh users:** Quote the task name to avoid glob errors: `rake "create_theme[my_theme]"`, not `rake create_theme[my_theme]`.

### What Gets Created

```
themes/theme_name/
├── .env                          # API credentials (edit with your values)
├── package.json                  # JS dependencies and build scripts
├── database.sqlite3              # Local SQLite database (seeded with defaults)
├── css/
│   └── application.tailwind.css  # Tailwind v4 CSS input file
├── js/
│   ├── application.js            # esbuild entry point + Stimulus setup
│   └── controllers/              # Stimulus controllers go here
├── templates/
│   ├── theme.liquid              # Main layout (header, footer, content_for_layout)
│   ├── index.liquid              # Homepage template
│   └── page.liquid               # Generic page template
└── assets/                       # Built CSS/JS output (compiled by watchers)
```

The rake task also:
- Updates `.env_vars` with `THEME=theme_name` so `./bin/dev` uses the new theme immediately
- Creates and seeds `database.sqlite3` with default globals, navigation, and a sample page

### Default JS Dependencies

```json
{
  "dependencies": {
    "@hotwired/stimulus": "^3.2.2",
    "@tailwindcss/typography": "^0.5.19",
    "@tailwindplus/elements": "^1.0.19"
  },
  "devDependencies": {
    "@tailwindcss/cli": "^4.2.0",
    "esbuild": "^0.27.0",
    "tailwindcss": "^4.2.0"
  }
}
```

---

## Step 2: Install Dependencies

If you didn't use `INSTALL=true`:

```bash
cd themes/theme_name
yarn install
cd ../..
```

---

## Step 3: Start the Dev Server

```bash
./bin/dev
```

This starts:
- **web** — Sinatra on port 4567 (live preview at `http://localhost:4567`)
- **css** — Tailwind watcher (rebuilds `assets/application.css` on save)
- **js** — esbuild watcher (rebuilds `assets/application.js` on save)
- **pi** — Pi coding agent in RPC mode (powers the floating chat widget)

Edit any file in `templates/` or `css/` or `js/` — the browser reloads automatically.

---

## Step 4: Configure API Credentials

You need `AIROGEL_API_URL`, `AIROGEL_ACCOUNT_ID`, and `AIROGEL_API_KEY` in `themes/theme_name/.env`. There are two ways to get them.

### Option A: Register via the CLI (new users)

If you don't have an Airogel CMS account yet, create one from the command line. No `.env` setup required first — just provide your details:

```bash
bin/airogelcms theme_name register \
  --name="Your Name" \
  --email=you@example.com \
  --password=yourpassword \
  --account_name="Your Site Name"
```

On success, the output includes a ready-to-paste `.env` snippet:

```
AIROGEL_API_URL=https://api.airogelcms.com
AIROGEL_ACCOUNT_ID=acct_xxxxxxxxxxxxx
AIROGEL_API_KEY=tok_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Paste those three lines into `themes/theme_name/.env`, then subscribe to a plan:

```bash
# See available plans
bin/airogelcms theme_name list_plans

# Generate a Stripe Checkout URL (replace plan_xxx with an ID from list_plans)
bin/airogelcms theme_name subscription_checkout --plan=plan_xxx
# → Prints a checkout.stripe.com URL — open it in your browser and pay

# Confirm the subscription is active
bin/airogelcms theme_name subscription_status
```

See `docs/ACCOUNT_SETUP.md` for the full walkthrough including troubleshooting.

### Option B: Use existing credentials (existing users)

Edit `themes/theme_name/.env` directly:

```bash
AIROGEL_API_URL=https://api.airogelcms.com
AIROGEL_ACCOUNT_ID=acct_xxxxxxxxxxxxx
AIROGEL_API_KEY=your_api_key_here
```

**Where to get credentials:**
- `AIROGEL_ACCOUNT_ID`: CMS Dashboard → Settings → API
- `AIROGEL_API_KEY`: CMS Dashboard → Settings → API Tokens → Create New Token

Verify the connection:

```bash
bin/airogelcms theme_name list_collections
```

Should return JSON (empty array is fine for a new account).

---

## Step 5: Build Assets for Production

```bash
# CSS (one-time minified build)
cd themes/theme_name
npx @tailwindcss/cli -i ./css/application.tailwind.css -o ./assets/application.css --minify

# JS (one-time minified build)
npx esbuild js/*.* --bundle --format=iife --outdir=assets --public-path=/ --minify
```

---

## Tailwind CSS v4

This project uses **Tailwind CSS v4** with CSS-native configuration — no `tailwind.config.js`. All config lives in `css/application.tailwind.css`:

```css
@import "tailwindcss";                              /* v4 entry point */
@plugin '@tailwindcss/typography';                  /* plugins via @plugin */
@custom-variant dark (&:where(.dark, .dark *));    /* class-based dark mode */

@theme {
  --color-brand: #4f46e5;                          /* custom design tokens */
  --font-sans: 'Inter', system-ui, sans-serif;
}
```

### Key v4 Differences from v3

| v3 | v4 |
|----|-----|
| `tailwind.config.js` | `@theme {}` block in CSS |
| `@tailwind base; @tailwind utilities;` | `@import "tailwindcss";` |
| `require('@tailwindcss/typography')` in config | `@plugin '@tailwindcss/typography';` in CSS |
| `darkMode: 'class'` in config | `@custom-variant dark (...)` in CSS |
| `npx tailwindcss` | `npx @tailwindcss/cli` |

### Dynamic Classes Warning

Tailwind purges classes it can't find in your templates. If you build class names dynamically (e.g., `"text-" + color`), Tailwind will not include them. Either:
1. Use full class names in templates (preferred)
2. Add them to a safelist in `css/application.tailwind.css`:

```css
@source inline("text-red-500 text-blue-500 text-green-500");
```

---

## Switching Themes

Change the active theme by editing `.env_vars`:

```bash
THEME=other_theme_name
```

Or run with a one-off override:

```bash
THEME=other_theme ./bin/dev
```

---

## Uploading to the Live CMS

When you're ready to push local template/asset changes to the live site:

```bash
# Upload everything
bin/airogelcms theme_name upload_theme

# Or upload selectively (preferred — upload only what changed)
bin/airogelcms theme_name upload_templates
bin/airogelcms theme_name upload_assets
```

> **Note:** `upload_theme` only uploads templates and assets. It does NOT push SQLite content rows to the CMS. For content/data changes, use the CRUD commands (`create_entry`, `update_global`, etc.) — see `docs/AIROGEL_CMS_IMPORT_GUIDE.md`.

---

## Working with Existing Themes

### Pull a Theme from CMS

```bash
# Download database + templates + assets, then re-import into SQLite
bin/airogelcms theme_name download_theme

# Or selectively
bin/airogelcms theme_name download_database    # updates SQLite from CMS
bin/airogelcms theme_name download_templates
bin/airogelcms theme_name download_assets
```

### Typical Edit-Sync Loop

```bash
# 1. Pull latest from CMS before making changes
bin/airogelcms theme_name download_theme

# 2. Edit templates/CSS/JS locally and verify in preview at localhost:4567

# 3. Push changes to the live site
bin/airogelcms theme_name upload_templates
bin/airogelcms theme_name upload_assets
```

---

## Template Authoring Quick Reference

### Layout (`theme.liquid`) — required structure

```liquid
<!doctype html>
<html>
<head>
  {{ content_for_header }}
  {{ 'application.css' | asset_url | stylesheet_tag }}
  {{ 'application.js' | asset_url | script_tag: 'default' }}
</head>
<body>
  {{ content_for_layout }}
  {% cms_scripts %}
</body>
</html>
```

`{% cms_scripts %}` loads the floating chat widget and form JS. Always include it.

### Partials — pass variables explicitly

```liquid
{% render 'header', navigation: navigation, site: site %}
```

Variables are NOT automatically available inside `{% render %}` partials. Always pass what the partial needs.

### Entry variable = collection handle

```liquid
{{  posts.title }}    <!-- collection handle is 'posts' -->
{{ page.title }}     <!-- collection handle is 'page' -->
```

Getting the handle wrong renders blank with no error.

### Filters

```liquid
{{ 'application.css' | asset_url | stylesheet_tag }}
{{ 'hero.jpg' | asset_url | image_tag: 'Hero image', 'w-full' }}
{{ posts.published_at | date: "%B %d, %Y" }}
```

---

## Troubleshooting

### "no matches found" in zsh

```bash
# Wrong
rake create_theme[my_theme]

# Correct
rake "create_theme[my_theme]"
```

### Dependencies not found when running `./bin/dev`

```bash
cd themes/theme_name
yarn install
cd ../..
./bin/dev
```

### Theme not loading in preview

Check `.env_vars` contains the correct theme name:
```
THEME=theme_name
```

### Template change not visible

CSS/JS changes require the watcher to rebuild. If the watcher crashed, restart `./bin/dev`. Template (`.liquid`) changes are picked up immediately on the next request.

### Asset not loading after upload

Assets uploaded with `bin/airogelcms upload_assets` are served from the CMS CDN. Check the CMS dashboard to confirm the asset was received, or run `bin/airogelcms theme_name list_assets`.
