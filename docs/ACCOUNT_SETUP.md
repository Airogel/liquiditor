# Account Setup via CLI

This guide covers creating a new Airogel CMS account and activating a subscription entirely from the command line using `bin/airogelcms`.

If you already have an account and API credentials, skip to [Connecting an Existing Account](#connecting-an-existing-account).

---

## Full Flow: New User

```
1. register              → creates user + account + API token
2. list_plans            → shows available plans and their IDs
3. subscription_checkout → generates a Stripe Checkout URL to open in browser
4. (pay in browser)
5. subscription_status   → confirms the subscription is active
6. download_theme        → pulls templates and content to start working locally
```

---

## Step 1: Create the Theme Scaffold

If you haven't already, create the local theme directory:

```bash
bundle exec rake "create_theme[my_theme]"
```

This creates `themes/my_theme/` with a blank `.env` file. You'll fill in the credentials in Step 2.

---

## Step 2: Register

The `register` command creates a new user, a new account, and a permanent API token in one request. It does **not** require a populated `.env` — it only needs the API URL (which defaults to production).

```bash
bin/airogelcms my_theme register \
  --name="Jane Doe" \
  --email=jane@example.com \
  --password=yourpassword \
  --account_name="Jane's Site"
```

**Parameters:**

| Flag | Required | Description |
|------|----------|-------------|
| `--name` | yes | Your full name |
| `--email` | yes | Email address (must be unique) |
| `--password` | yes | Account password |
| `--account_name` | yes | Display name for the new account |
| `--api_url` | no | API base URL (default: `https://api.airogelcms.com`) |

**Success output:**

```json
{
  "success": true,
  "data": {
    "user": { "id": "user_xxx", "name": "Jane Doe", "email_address": "jane@example.com" },
    "account": { "id": "acct_xxx", "name": "Jane's Site", "subdomain": "janes-site" },
    "api_token": "a1b2c3d4e5f6..."
  },
  "message": "Account created. Add the following to themes/my_theme/.env:\n\nAIROGEL_API_URL=https://api.airogelcms.com\nAIROGEL_ACCOUNT_ID=acct_xxx\nAIROGEL_API_KEY=a1b2c3d4e5f6..."
}
```

The `message` field contains the exact `.env` block to paste. Copy the three `AIROGEL_*` lines into `themes/my_theme/.env`:

```bash
AIROGEL_API_URL=https://api.airogelcms.com
AIROGEL_ACCOUNT_ID=acct_xxx
AIROGEL_API_KEY=a1b2c3d4e5f6...
```

> **Save the API token now.** It is only returned once. If you lose it, generate a new one from the CMS Dashboard under Settings → API Tokens.

---

## Step 3: List Plans

See what subscription plans are available:

```bash
bin/airogelcms my_theme list_plans
```

Filter by billing interval:

```bash
bin/airogelcms my_theme list_plans --interval=month
bin/airogelcms my_theme list_plans --interval=year
```

**Example output:**

```json
{
  "success": true,
  "data": {
    "plans": [
      {
        "id": "plan_abc123",
        "name": "Basic",
        "tier": "basic",
        "amount": "10.00",
        "amount_cents": 1000,
        "currency": "usd",
        "interval": "month",
        "trial_period_days": 14,
        "features": ["hosting", "content", "analytics", "api"]
      }
    ]
  }
}
```

Note the `id` value (e.g. `plan_abc123`) — you'll need it in the next step.

---

## Step 4: Subscribe

Generate a Stripe Checkout URL and open it in your browser:

```bash
bin/airogelcms my_theme subscription_checkout --plan=plan_abc123
```

With custom redirect URLs (optional):

```bash
bin/airogelcms my_theme subscription_checkout \
  --plan=plan_abc123 \
  --success_url=https://app.airogelcms.com/checkout/return \
  --cancel_url=https://airogelcms.com/pricing
```

**Output:**

```json
{
  "success": true,
  "data": { "checkout_url": "https://checkout.stripe.com/c/pay/cs_live_..." },
  "message": "Open this URL in a browser to complete your subscription:\nhttps://checkout.stripe.com/..."
}
```

Open the `checkout_url` in your browser. Stripe handles card collection. In development, use a [Stripe test card](https://docs.stripe.com/testing#cards):

| Scenario | Card Number |
|----------|-------------|
| Successful payment | `4242 4242 4242 4242` |
| Card declined | `4000 0000 0000 0002` |
| Requires 3DS | `4000 0025 0000 3155` |

Use any future expiry, any 3-digit CVC, any postal code.

---

## Step 5: Confirm the Subscription

After completing payment, confirm the subscription is active:

```bash
bin/airogelcms my_theme subscription_status
```

**Subscribed:**

```json
{
  "success": true,
  "data": {
    "subscribed": true,
    "plan": { "name": "Basic", "tier": "basic", "interval": "month" },
    "subscription": {
      "status": "active",
      "trial_ends_at": null,
      "current_period_end": "2026-04-05T12:00:00Z",
      "cancel_at_period_end": false
    }
  }
}
```

**Not yet active** (webhook still processing — usually a few seconds):

```json
{
  "success": true,
  "data": { "subscribed": false, "plan": null, "subscription": null }
}
```

If it stays `false` for more than a minute, see [Troubleshooting](#troubleshooting) below.

---

## Step 6: Pull the Theme

Now that the account is subscribed, pull the default templates and content:

```bash
bin/airogelcms my_theme download_theme
```

This downloads templates, assets, and the content database into `themes/my_theme/`. From here, the normal Liquiditor development workflow applies — see `docs/CREATING_THEMES.md` and `README.md`.

---

## Connecting an Existing Account

If you already have an Airogel CMS account, skip registration and fill in `.env` directly:

```bash
AIROGEL_API_URL=https://api.airogelcms.com
AIROGEL_ACCOUNT_ID=acct_xxxxxxxxxxxxx
AIROGEL_API_KEY=your_api_key_here
```

Get these values from the CMS Dashboard → Settings → API.

Verify the connection:

```bash
bin/airogelcms my_theme list_collections
```

---

## Creating an Additional Account

Authenticated users (with a valid `.env`) can create extra accounts — useful for managing multiple sites:

```bash
bin/airogelcms my_theme create_account --name="My Second Site"
```

The response includes the new account's `id`. Update `AIROGEL_ACCOUNT_ID` in `.env` (or use a separate theme directory) to work with the new account.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `register` returns `"errors": ["Email address has already been taken"]` | Email already registered | Use a different email, or log in to the CMS Dashboard to retrieve your API key |
| `register` returns `403 Forbidden` | API registration disabled by admin | Contact your Airogel CMS administrator |
| `register` returns `429 Too Many Requests` | Rate limit exceeded (10 req / 3 min) | Wait a few minutes and retry |
| `subscription_checkout` returns `Plan not found` | Invalid plan ID | Run `list_plans` again and copy the `id` exactly |
| `subscription_checkout` returns a Stripe error | Stripe keys not configured on the server | Contact support |
| `subscription_status` stays `subscribed: false` | Webhook not yet processed | Wait 10–30 seconds and retry. In development, run `stripe listen --forward-to localhost:3000/pay/webhooks/stripe` |
| All commands return `401 Unauthorized` after registration | API token not in `.env` | Paste the `AIROGEL_API_KEY` from the registration output into `themes/my_theme/.env` |
| `download_theme` returns `402 Payment Required` | No active subscription | Complete Steps 3–5 first |
