# lyveira-web

Static legal + support site for the Lyveira app, hosted on GitHub Pages.

Pages:
- `/` — landing
- `/privacy/` — Privacy Policy (App Store Privacy Policy URL)
- `/terms/` — Terms of Use (EULA)
- `/support/` — Support (App Store Support URL)

## Hosting
Served by GitHub Pages from the `main` branch root. `.nojekyll` disables Jekyll
so files are served as-is.

## Custom domain (lyveira.app)
To serve these at `https://lyveira.app/...` instead of the github.io URL:
1. Add a `CNAME` file at the repo root containing `lyveira.app`.
2. In Cloudflare DNS for lyveira.app, add a CNAME record `@` (or `www`) ->
   `<owner>.github.io` (DNS-only, not proxied), or A/AAAA records to GitHub
   Pages IPs.
3. Enable the custom domain + HTTPS in the repo Pages settings.

The Cloudflare step is the only piece that needs the (currently invalid)
`/lyveira/prod/cloudflare/dns_edit_token` to be refreshed, or a manual DNS edit.

## Contact
support@lyveira.app
