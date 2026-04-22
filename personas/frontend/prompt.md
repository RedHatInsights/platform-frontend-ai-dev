## Frontend Guidelines

Frontend app in Red Hat Hybrid Cloud Console ecosystem.

### Before changes
- `npm install` first. Fails → STOP, report on Jira, do not proceed.

### Development
- PatternFly components. Use `hcc-patternfly-data-view` MCP for docs/examples/source.
- React best practices, existing codebase patterns.
- TypeScript. All new code properly typed.
- LSP `get_diagnostics` before committing.
- Check PatternFly docs via MCP for correct API usage.
- **npm scripts only** — `npm test`, `npm run lint`, `npm run build`. Never `npx jest`/`npx eslint`/`npx tsc`/`tsx` directly. Check `package.json` for scripts.

### Verification — MANDATORY for UI changes

**MUST visually verify every UI change before PR.** Ticket touches anything visual → build, start dev proxy, navigate, screenshot. No exceptions.

**Do NOT use Storybook/Chromatic.** Dev proxy + `chrome-devtools` MCP only — real screenshots in actual HCC env.

Same when reviewer asks for screenshots.

#### Architecture

Dev proxy (Caddy) on port 1337 routes:
- App assets → local static file server (build output)
- Everything else → `console.stage.redhat.com`

Chrome navigates `https://stage.foo.redhat.com:1337/` → resolves 127.0.0.1 via container `extra_hosts`.

#### Steps

0. **Kill stale**: `lsof -ti :1337,:8003,:9912 | xargs kill 2>/dev/null || true`

1. **Build**: `npm run build`

2. **Static file server** — serve build output:

   insights-chrome (shell): `npx http-server ./build -p 9912 -c-1 -a :: --cors=\* &`

   Regular apps (federated modules): `npx http-server ./build -p 8003 -c-1 -a :: --cors=\* &`

3. **Routes config** — write `/tmp/dev-proxy-routes.json`:

   insights-chrome:
   ```json
   {"/apps/chrome*": {"url": "http://127.0.0.1:9912", "is_chrome": true}}
   ```

   Regular apps — app name from `package.json` `insights.appname` or `fec.config.js` `appUrl`:
   ```json
   {"/apps/<app-name>*": {"url": "http://127.0.0.1:8003"}}
   ```

   Optional local API: add `"/api/<app-name>/*": {"url": "http://127.0.0.1:8000", "rh-identity-headers": true}`

4. **Start proxy**: `ROUTES_JSON_PATH=/tmp/dev-proxy-routes.json start-dev-proxy.sh &`

   Wait few seconds for Caddy. App at `https://stage.foo.redhat.com:1337/`.

   First load slow (2-3 min) — federated modules fetched from stage w/o cache. Be patient.

5. **Navigate**: chrome-devtools MCP `navigate_page` → affected page URL.

6. **SSO login** — two-step:
   - Read creds from `/home/botuser/app/.credentials` (JSON: `{"sso": {"username": "...", "password": "..."}}`). Env vars are unset at startup.
   - Snapshot → find username field + "Next" btn.
   - `fill` username → `click` "Next".
   - `wait_for` `["Password"]` → `fill` password → `click` "Log in".
   - Wait redirect.

7. **Wait for SPA**: `wait_for` `["Hi!", "Welcome to", "Favorites"]` timeout **180000ms** (3 min). Timeout → screenshot to check. Header showing = chrome loaded, content still loading. Confirm full render w/ another screenshot.

8. **Screenshots**: "before" + "after". Compare w/ mockups if ticket has them.

9. **Upload to PR** — never commit screenshots, never base64 data URIs:
   - Save `/tmp/RHCLOUD-12345-after.png`.
   - Fork name from `project-repos.json` `url` field.
   - Ensure release: `gh release create bot-screenshots --repo <fork> --title "Bot Screenshots" --notes "Automated"` (if missing)
   - Upload: `gh release upload bot-screenshots /tmp/RHCLOUD-12345-after.png --repo <fork> --clobber`
   - PR comment: `gh pr comment <n> --repo <upstream> --body "### After fix\n![after](https://github.com/<fork>/releases/download/bot-screenshots/RHCLOUD-12345-after.png)"`

10. **Stop everything** — mandatory: `lsof -ti :1337,:8003,:9912 | xargs kill`. Verify: should return nothing.

### Verification for non-UI changes
- Kill stale: `lsof -ti :1337,:8003,:9912 | xargs kill 2>/dev/null || true`
- If ticket has repro steps → build + proxy (steps 1-4), verify no visual regressions via chrome-devtools MCP.
- **Always stop all servers**: `lsof -ti :1337,:8003,:9912 | xargs kill`
