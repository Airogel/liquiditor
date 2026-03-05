# Liquiditor

Liquiditor is a local-first theme development environment for Airogel CMS.
It runs a Sinatra app that renders Liquid templates against a local SQLite database,
with live reload and a built-in AI chat widget.

## What it does

- Previews Airogel CMS themes locally using the same Liquid runtime and custom tags/filters.
- Stores content model and entry data in `themes/{THEME}/database.sqlite3`.
- Watches templates and built assets for automatic browser reload.
- Provides a CLI (`bin/airogelcms`) to sync templates/assets and content with the CMS API.

## Tech stack

- Ruby + Sinatra + Puma
- Liquid 5
- Sequel + SQLite
- Tailwind CSS v4 + esbuild (per-theme frontend pipeline)
- Stimulus for frontend behavior

## Project layout

- `liquiditor.rb` - Sinatra app (rendering, live reload, uploads, Pi chat endpoints)
- `bin/airogelcms` - CLI for download/upload + CMS CRUD + docs generation
- `db/schema.rb` - SQLite schema and seed data
- `themes/{THEME}/templates/` - Liquid templates
- `themes/{THEME}/css/` - Tailwind input CSS
- `themes/{THEME}/js/` - JavaScript entry/controllers
- `themes/{THEME}/assets/` - compiled CSS/JS and static assets
- `themes/{THEME}/database.sqlite3` - local content database
- `themes/{THEME}/docs/liquid_tags.md` - generated Liquid field/tag reference

## Quick start

1. Install Ruby gems:

```bash
bundle install
```

2. Pick an active theme in `.env_vars`:

```bash
THEME=your_theme
```

3. Install theme frontend dependencies:

```bash
cd themes/$THEME && yarn install
```

4. Start the app and asset watchers:

```bash
source .env_vars && bin/dev
```

Then open `http://localhost:4567`.

## Rake tasks

### Theme creation

```bash
# Create a new theme scaffold (directories, templates, SQLite DB)
bundle exec rake "create_theme[my_theme]"

# Create and immediately install JS dependencies + build assets
INSTALL=true bundle exec rake "create_theme[my_theme]"
```

> **zsh users:** always quote the task name — `rake "create_theme[my_theme]"`, not `rake create_theme[my_theme]`.

`create_theme` creates `themes/my_theme/` with:

| Path | Description |
|------|-------------|
| `.env` | API credentials (fill in after running `register`) |
| `package.json` | JS dependencies and build scripts |
| `database.sqlite3` | Local SQLite DB, seeded with default globals, nav, and a sample page |
| `css/application.tailwind.css` | Tailwind v4 CSS input file |
| `js/application.js` | esbuild entry point + Stimulus setup |
| `js/controllers/` | Stimulus controllers directory |
| `templates/theme.liquid` | Main layout (header, nav, footer, `content_for_layout`) |
| `templates/index.liquid` | Homepage template |
| `templates/page.liquid` | Generic page template |
| `assets/` | Built CSS/JS output (written by watchers) |

It also sets `THEME=my_theme` in `.env_vars` so `./bin/dev` picks up the new theme immediately.

### Database tasks

```bash
# Create the SQLite DB for the active theme (idempotent)
bundle exec rake db:create

# Run schema migrations (idempotent — safe to re-run)
bundle exec rake db:migrate

# Seed the DB with default globals, navigation, and a sample page
bundle exec rake db:seed

# Create + seed in one step
bundle exec rake db:create db:seed

# Target a specific theme instead of the one in .env_vars
THEME=other_theme bundle exec rake db:seed
```

### YAML import

```bash
# Import a database.yml file (downloaded from CMS) into SQLite
bundle exec rake "import_yaml[my_theme]"
```

Clears all existing SQLite data and re-imports from `themes/my_theme/database.yml`. Handles collections, entries, globals, navigations, forms, and content paths. Normally you won't need this directly — `bin/airogelcms $THEME download_database` does the download and import in one step.

## Common bin/airogelcms commands

### Account creation & subscription

```bash
# New user: create user + account + API token (no .env needed)
bin/airogelcms $THEME register \
  --name="Jane Doe" --email=jane@example.com \
  --password=secret --account_name="Jane's Site"

# List available subscription plans
bin/airogelcms $THEME list_plans

# Generate a Stripe Checkout URL (open it in a browser to pay)
bin/airogelcms $THEME subscription_checkout --plan=plan_xxx

# Confirm subscription is active (poll after paying)
bin/airogelcms $THEME subscription_status
```

See `docs/ACCOUNT_SETUP.md` for the full walkthrough.

### Sync

```bash
# Pull entire theme from CMS (database + templates + assets)
bin/airogelcms $THEME download_theme

# Push templates to CMS
bin/airogelcms $THEME upload_templates

# Push compiled assets to CMS
bin/airogelcms $THEME upload_assets

# Regenerate Liquid variable reference docs from local SQLite
bin/airogelcms $THEME generate_liquid_docs
```

## Local vs CMS sync

Liquiditor is local-first.

- Editing files in `themes/{THEME}` updates local preview only.
- `upload_templates` and `upload_assets` are required to publish file changes.
- Local SQLite edits do not publish content by themselves.
- For content model/data changes on CMS, use `bin/airogelcms` CRUD actions (`create_entry`, `update_global`, etc.), then run `download_database` to resync local state.

## Reference docs

- `AGENTS.md` - working rules and AI assistant behavior for Liquiditor
- `docs/ACCOUNT_SETUP.md` - creating a new account and subscribing via the CLI
- `docs/CREATING_THEMES.md` - theme creation workflow
- `docs/THEME_DOCUMENTATION.md` - theme structure and conventions
- `docs/TAILWIND_HELP.md` - Tailwind v4 usage guidance
- `docs/AIROGEL_CMS_IMPORT_GUIDE.md` - importing content from CMS sources

## Troubleshooting

- `THEME` not set or wrong: set `THEME=<theme_name>` in `.env_vars`, then run `source .env_vars` before `bin/dev`.
- Theme directory missing: verify `themes/$THEME` exists, or create one with `bundle exec rake create_theme[my_theme]`.
- CMS commands failing auth: check `themes/$THEME/.env` has valid `AIROGEL_API_URL`, `AIROGEL_ACCOUNT_ID`, and `AIROGEL_API_KEY`.
- CSS/JS not updating: ensure watcher processes are running from `bin/dev`; if needed, restart `bin/dev` and rerun `cd themes/$THEME && yarn install`.
- Page shows not found: confirm a matching row exists in `themes/$THEME/database.sqlite3` `content_paths` for the URL.
