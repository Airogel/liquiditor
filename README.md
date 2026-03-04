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

## Common commands

- Create and seed local DB: `bundle exec rake db:create db:seed`
- Create a new theme scaffold: `bundle exec rake create_theme[my_theme]`
- Pull latest theme from CMS: `bin/airogelcms $THEME download_theme`
- Push templates only: `bin/airogelcms $THEME upload_templates`
- Push assets only: `bin/airogelcms $THEME upload_assets`
- Regenerate Liquid variable docs: `bin/airogelcms $THEME generate_liquid_docs`

## Local vs CMS sync

Liquiditor is local-first.

- Editing files in `themes/{THEME}` updates local preview only.
- `upload_templates` and `upload_assets` are required to publish file changes.
- Local SQLite edits do not publish content by themselves.
- For content model/data changes on CMS, use `bin/airogelcms` CRUD actions (`create_entry`, `update_global`, etc.), then run `download_database` to resync local state.

## Reference docs

- `AGENTS.md` - working rules and AI assistant behavior for Liquiditor
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
