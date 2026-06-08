# Deploy lyveira-web to Cloudflare Pages (lyveira.com + lyveira.app)

This site is static (HTML/CSS, no build step). It currently lives on GitHub Pages
(https://dwasivalsa.github.io/lyveira-web/). This guide moves it onto **Cloudflare
Pages** and serves it on **both** of your domains.

## Facts (verified 2026-06-08)
- **lyveira.app** — DNS on Cloudflare (`osmar`/`irma.ns.cloudflare.com`). Apex is
  Cloudflare-proxied but serves nothing; subdomains `api.` `auth.` `agents.`
  `notify.` point to Lightsail (leave those alone). `applinks:lyveira.app` is the
  app's universal-link domain.
- **lyveira.com** — also on Cloudflare, registered through Cloudflare 2026-05-12,
  apex currently points nowhere.
- Repo: `DwasiValsa/lyveira-web`, branch `main`, output = repo root, `.nojekyll`.

## Recommended end state
- One Cloudflare Pages project deploying `DwasiValsa/lyveira-web`.
- **Both** apexes attached as custom domains → site answers on `lyveira.com/...`
  **and** `lyveira.app/...`. (The app's in-app Privacy/Terms links point at
  `lyveira.app/privacy` + `/terms` — those start working with no app rebuild.)
- Use **lyveira.com** as the public/marketing canonical (App Store Marketing URL,
  the privacy/support links you give people). Keep **lyveira.app** for app infra +
  deep links (it also serves the site).

---

## Path A — Cloudflare dashboard (no token needed, ~10 min)

1. **Create the Pages project**
   - dash.cloudflare.com → **Workers & Pages** → **Create** → **Pages** →
     **Connect to Git** → authorize GitHub → pick **DwasiValsa/lyveira-web**.
   - Build settings: **Framework preset = None**, **Build command = (empty)**,
     **Build output directory = `/`**. → **Save and Deploy**.
   - You get a `https://lyveira-web.pages.dev` URL once it builds (~1 min).

2. **Attach lyveira.com**
   - Pages project → **Custom domains** → **Set up a custom domain** →
     enter `lyveira.com` → Cloudflare detects the zone is in your account and
     **creates the DNS + SSL automatically**. Repeat for `www.lyveira.com` if you
     want the www variant (it 301s to apex by default).

3. **Attach lyveira.app**
   - Same flow → add `lyveira.app`. Cloudflare will **replace** the placeholder
     apex record with the Pages target. Your `api./auth./agents./notify.`
     subdomains are untouched (they're separate records).

4. **Wait for SSL** (usually < 2 min) then verify:
   `https://lyveira.com/privacy/` and `https://lyveira.app/privacy/` both load.

That's it — no token required because you're acting as the account owner in the UI.

---

## Path B — Scripted (needs a Cloudflare API token)

Use this if you want Claude/CI to do it. The blocker today is that the SSM token
`/lyveira/prod/cloudflare/dns_edit_token` is **invalid** — mint a fresh one first.

### B0. Mint + store a token
- dash.cloudflare.com → **My Profile → API Tokens → Create Token → Custom**.
- Permissions:
  - **Account › Cloudflare Pages › Edit**
  - **Zone › DNS › Edit** (include both zones: lyveira.app, lyveira.com)
  - **Zone › Zone › Read**
- Account Resources: your account. Zone Resources: both zones.
- Save the token, then store it (so automation can use it):
  ```
  aws --profile upliv-prod ssm put-parameter --name /lyveira/prod/cloudflare/dns_edit_token \
    --type SecureString --overwrite --value "<TOKEN>"
  ```

### B1. Create + deploy the Pages project (wrangler)
```
cd lyveira-web
export CLOUDFLARE_API_TOKEN="<TOKEN>"
export CLOUDFLARE_ACCOUNT_ID="<your account id>"   # dash URL or `npx wrangler whoami`
npx wrangler pages project create lyveira-web --production-branch main
npx wrangler pages deploy . --project-name lyveira-web --branch main
```

### B2. Attach both custom domains (API)
```
ACCT=$CLOUDFLARE_ACCOUNT_ID; TOK=$CLOUDFLARE_API_TOKEN
for D in lyveira.com lyveira.app; do
  curl -sS -X POST "https://api.cloudflare.com/client/v4/accounts/$ACCT/pages/projects/lyveira-web/domains" \
    -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" \
    --data "{\"name\":\"$D\"}" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("success"),[e.get("message") for e in d.get("errors",[])])'
done
```
Cloudflare auto-creates the proxied CNAME (apex flattened) for each zone since both
are in the same account. Confirm:
```
for D in lyveira.com lyveira.app; do echo "$D -> $(curl -s -o /dev/null -w '%{http_code}' https://$D/privacy/)"; done
```

---

## After it's live
1. **App Store Connect** → set Privacy Policy URL = `https://lyveira.com/privacy/`,
   Support URL = `https://lyveira.com/support/`, Marketing URL = `https://lyveira.com/`.
2. The in-app paywall links (`lyveira.app/privacy`, `/terms`) now resolve — no app
   rebuild needed.
3. (Optional) retire the GitHub Pages site, or leave it as a backup.

## Optional: one canonical domain
If you'd rather force a single canonical (e.g. everything → lyveira.com), add a
Cloudflare **Redirect Rule**: Zone lyveira.app → Rules → Redirect Rules →
"When hostname equals lyveira.app, 301 to `https://lyveira.com/$1`". Note this would
also redirect `lyveira.app/privacy` — fine for users, but then update the in-app
links to `lyveira.com`. Serving both (no redirect) is simpler and is the default
above.

## Deep links later
When you wire universal links, drop `apple-app-site-association` at
`/.well-known/apple-app-site-association` in this repo (Cloudflare Pages serves it
with the correct `application/json` content type). The app already declares
`applinks:lyveira.app`.

_Last updated 2026-06-08._
