# Dirigera QuickApp — Code Review

**Version reviewed:** v0.1.5 (2026-04-06)
**Files in scope:** [Dirigera.lua](../Dirigera.lua) (228 lines), [Lib.lua](../Lib.lua) (237), [Devices.lua](../Devices.lua) (646), [Auth.lua](../Auth.lua) (108) — total ~1219 LOC.
**Out of scope:** `old/`, deep `scripts/` audit, `.fqa` packaging, live-HC3 testing.

> **Constraint honoured:** No proposed change renames any QuickApp child class (`ChildDimmableLight`, `ChildTempLight`, `ChildColorLight`, `ChildSpeaker`, `ChildMotionSensor`, `ChildLightSensor`, `ChildDoorSensor`, `ChildWaterSensor`, `ChildPM25Sensor`, `ChildVocSensor`, `ChildTempSensor`, `ChildHumiditySensor`, `ChildBinarySwitch`). Existing user children stay valid.

---

## 1. Verdict

A **modular, working bridge** with a clean separation between transport (Lib.lua), auth (Auth.lua), domain mapping (Devices.lua), and orchestration (Dirigera.lua). The PKCE flow, QwikChild-based child management, and WebSocket-driven update model are appropriate choices for the platform.

There are **two confirmed correctness bugs** (one breaks AirSensor children entirely under selection filtering; one disables hub→UI color sync), several **security/logging hygiene issues**, and a number of **robustness gaps** (no JSON pcall guards on hot paths, restart-on-disconnect, undocumented mireds inversion). Nothing is architecturally broken — most fixes are local and low-risk.

Severity scale: **Critical / High / Medium / Low / Nit**.

---

## 2. Findings Table

| # | Sev | Location | Issue | Recommendation |
|---|-----|----------|-------|----------------|
| F1 | **Critical** | [Dirigera.lua#L168-L174](../Dirigera.lua#L168-L174) | `filter()` regex `id:match("(.*_.*)_") or id` requires **two** `_` chars in the child id, then strips the trailing suffix. Dirigera device IDs are UUIDs (no underscores), so AirSensor children with IDs like `<uuid>_pm25`, `<uuid>_voc`, `<uuid>_temp` (one underscore each) **do not match the pattern** and fall back to the full id, which is **not** in the `devices` selection map (keyed by bare `<uuid>`). Result: PM2.5 / VOC / temperature children for AirSensor are filtered out and never instantiated. Only the humidity child (which uses the bare `<uuid>`) survives. | Strip suffix on the *last* `_` regardless of count. Use `id:match("^(.-)_[^_]+$") or id` (or simply check membership of the suffix-stripped form against the selection map and fall back to the full id). Add a unit test with a UUID-shaped id like `abcd-1234_pm25`. |
| F2 | **High** | [Devices.lua#L235](../Devices.lua#L235) | `if self.colorHue and color and self.child.updateColor then` references **undefined global `color`** — this expression is always falsy, so hub-side color changes are never propagated to the HC3 UI. Color updates only flow QA → hub, never back. | Replace `color` with the intended check (likely `self.colorSaturation and self.lightLevel`). Add `Lua.diagnostics.globals` so the language server flags such typos. |
| F3 | **High** | [Auth.lua#L94](../Auth.lua#L94), [Auth.lua#L102](../Auth.lua#L102) | Secrets logged when `debug=test=true`: full `codeVerifier` (PKCE secret) and full `access_token` are passed to `DEBUGF('test', ...)`. PKCE verifier is a one-shot secret bound to a request; access token is long-lived and stored. Anyone reading logs (HC3 system log, support exports) gets the token. | Log lengths or redacted prefixes only: `DEBUGF('test',"verifier len=%d", #codeVerifier)` and `DEBUGF('test',"token=%s…", token:sub(1,6))`. Never print the full token. |
| F4 | **High** | [Auth.lua#L60](../Auth.lua#L60), [Auth.lua#L26](../Auth.lua#L26) | Hardcoded `:8443` in OAuth URLs — `Hub.port` is ignored for auth (only used for WebSocket and REST). If port is ever changed for one path it silently diverges from the others. | Use `Hub.port` consistently: `fmt("https://%s:%s/v1/oauth/...", IP, Hub.port)`. |
| F5 | **High** | [Auth.lua#L62-L63](../Auth.lua#L62-L63) | PKCE `code_challenge` uses **standard base64** (`+/=`) with a hand-rolled `cc:sub(1,-2)` to drop one `=`. RFC 7636 specifies **base64url** with `-_` substitutions and no padding. Works against IKEA today only because (a) SHA256 produces exactly one `=` of padding and (b) hash output rarely contains `+`/`/`. A future hash with `+` or `/` will silently fail auth, and the implementation is non-conformant. | Replace the trailing-char strip with a proper base64url encode: `b64:gsub('+','-'):gsub('/','_'):gsub('=+$','')`. |
| F6 | **High** | [Lib.lua](../Lib.lua) all four wrappers + [Auth.lua](../Auth.lua) both calls | `checkCertificate=false` everywhere. Necessary because the Dirigera hub uses a self-signed cert, but currently undocumented and unconfigurable. | Add a brief comment explaining *why* (self-signed Dirigera cert). Optionally extract a single `httpOptions()` helper so the policy lives in one place; future cert pinning becomes a one-line change. |
| F7 | **Medium** | [Devices.lua#L209-L221](../Devices.lua#L209-L221) | `Light:setTemperature` clamping: writes `colorTemperatureMin` / `colorTemperatureMax` directly. IKEA Dirigera convention is `Min` = warm (high mired / low Kelvin) and `Max` = cool (low mired / high Kelvin), so `Min > Max` numerically. The current code therefore happens to be correct in normal cases, but the lack of a comment + the symmetry with the (correct) inverse logic in `Light:update` make this trap-prone. The same code blindly trusts both attributes are non-nil — if a malformed device omits one, you get a runtime arithmetic error. | Add a 1-line comment: `-- IKEA mireds: Min > Max (Min=warm, Max=cool)`. Guard with `if not (attrs.colorTemperatureMin and attrs.colorTemperatureMax) then return end`. Same for [Devices.lua#L249-L254](../Devices.lua#L249-L254). |
| F8 | **Medium** | [Devices.lua#L191-L201](../Devices.lua#L191-L201) | `Light:setRGB(r,g,b)` declares 3 params but `ChildColorLight:setColor(r,g,b,w)` passes 4 → white channel is silently dropped on the way to the hub. | Either accept and forward `w` (Dirigera supports `colorSaturation`/`lightLevel`, not RGBW directly, so document that w is intentionally ignored), or drop `w` from `setColor`'s call into `setRGB`. Add a comment either way. |
| F9 | **Medium** | [Dirigera.lua#L97-L102](../Dirigera.lua#L97-L102) | WebSocket `disconnected` handler unconditionally `plugin.restart()` after 5 s. This loses runtime state, doubles install/upload friction, and creates an infinite-restart loop if Dirigera is unreachable. No backoff, no max-attempts, no reason logged. | Replace `plugin.restart()` with a re-`connect()` inside `setTimeout`. Add exponential backoff capped at e.g. 60 s. Log the `error` event payload alongside disconnect so root cause is recoverable from logs. |
| F10 | **Medium** | [Lib.lua#L82](../Lib.lua#L82), [Dirigera.lua#L113](../Dirigera.lua#L113), [Auth.lua#L41](../Auth.lua#L41), [Auth.lua#L72](../Auth.lua#L72) | All `json.decode(response.data)` calls on hot paths are unguarded. Malformed payloads (HTML 502 page, truncated body) crash the callback chain silently — only Auth.lua's `getToken` uses `pcall`. | Wrap with `pcall(json.decode, response.data)`; on failure, log via `ERRORF` and abort the callback. Most uniform fix: a `safeDecode(response, name)` helper in Lib.lua used everywhere. |
| F11 | **Medium** | [Devices.lua#L590](../Devices.lua#L590) | `devices.name[d.attributes.customName] = d` — when `customName` is `nil` (some Dirigera devices have none) Lua errors at runtime (`table index is nil`); when it's `""` all empty-named devices collide on the same key. | Skip when nil/empty: `if d.attributes.customName and d.attributes.customName ~= "" then devices.name[d.attributes.customName] = d end`. |
| F12 | **Medium** | [Dirigera.lua#L155-L173](../Dirigera.lua#L155-L173) | `onInit` is a 4-deep nested callback chain (devices → scenes → home → init). If any intermediate fails (network blip, malformed JSON), init silently stalls — no timeout, no recovery, no user-visible error. | Add a single error path: each DGET callback should either proceed or schedule a retry with backoff (and surface the failure on the title label). Optionally linearize via small promise/then helper if comfortable; not required. |
| F13 | **Medium** | [Devices.lua#L334-L351](../Devices.lua#L334-L351) | AirSensor sub-children use ad-hoc id suffix scheme (`id`, `id.."_pm25"`, `id.."_voc"`, `id.."_temp"`). The bare `id` is reused for the **humidity** child — easy to confuse with the parent device id elsewhere (and conflicts conceptually with F1's filter). The suffix scheme is undocumented. | Add a short comment block above `AirSensor:__init` listing the four child ids and which property they map to. Consider standardising: use `id.."_humid"` and avoid the bare `id` reuse — but only if you supply a migration path (since renaming child UIDs **would** orphan existing user children, this is intentionally **not** a rename recommendation; treat as a future-only consideration). |
| F14 | **Low** | [Dirigera.lua#L222-L228](../Dirigera.lua#L222-L228) | Commented-out test calls left at end of file. | Delete or move to a dedicated `tests/` script. |
| F15 | **Low** | [Devices.lua#L597-L630](../Devices.lua#L597-L630) | `QuickApp:createScene` is unused, never tested, and uses a slightly odd pattern (`json.encode` of each trigger before re-encoding the whole). Untested code paths rot. | Remove until needed, or add at least one call site / smoke test. |
| F16 | **Low** | [Dirigera.lua#L40](../Dirigera.lua#L40) | `TOKEN = os.getenv("DIRIGERA_token")` overwrites stored token on every `onInit` ([Dirigera.lua#L150](../Dirigera.lua#L150)). Mixing two auth sources confuses operators ("why did my token reset?"). | Document in README that env var **always wins**; or only use env var when no stored token exists (`if not self.store.token and TOKEN then self.store.token = TOKEN end`). |
| F17 | **Low** | [Lib.lua#L138](../Lib.lua#L138), [Lib.lua#L172](../Lib.lua#L172) | `ERRORF("Error post data: %s", response.status, data or "")` and similar — format string has 1 placeholder, two args passed. The extra `data` is silently dropped, hiding useful debugging info. | Either add the `%s` placeholder for `data`, or drop the extra arg. |
| F18 | **Low** | [Devices.lua#L86-L92](../Devices.lua#L86-L92) | `ChildDimmableLight:updateValue` uses `self.ignoreValue` to suppress one echo from the hub. Multiple updates between `setValue` and the WS echo will reset state unpredictably. | Acceptable as-is for low traffic; consider replacing with a short `lastSetAt` timestamp window if users report flicker. |
| F19 | **Low** | [Lib.lua#L34-L43](../Lib.lua#L34-L43) | `fibaro.getIPaddress` queries an unrelated proxy URL and is not used anywhere in the live code path (only a commented call in Auth.lua). | Remove if dead; otherwise add a comment showing intended use. |
| F20 | **Low** | [Dirigera.lua#L20-L21](../Dirigera.lua#L20-L21) | Stale `--%%uid:UPD896846032517893` and `id=1782` headers — these reference the original author's instance and confuse new installers. | Strip or document as "leave blank for new installs". |
| F21 | **Nit** | [Devices.lua#L16-L20](../Devices.lua#L16-L20) | `DG` is a global mutable namespace and `DG = DG or { childs = {}}` appears in both [Dirigera.lua#L41](../Dirigera.lua#L41) and [Devices.lua#L16](../Devices.lua#L16). Works but obscures load order. | Define once in Lib.lua and require both other files load after it (already true via header order). |
| F22 | **Nit** | Workspace | No `.vscode/settings.json` `Lua.diagnostics.globals` entry visible. The language server can't detect `color`-style typos (see F2). | Add a `settings.json` entry covering: `fibaro`, `api`, `plugin`, `net`, `json`, `QuickApp`, `QwikAppChild`, `class`, `setTimeout`, `quickApp`, `__TAG`, `DG`, `Hub`, `sha`, `printf`, `printc`, `DEBUGF`, `ERRORF`, `urlencode`, `HSV2RGB`, `RGB2HSV`, `MessageHandler`. |
| F23 | **Nit** | `old/` folder | `Devices2.lua`, `Dirigera2.lua` are legacy, identified as deprecated in CHANGELOG. | Delete (git history preserves them). |

---

## 3. What's Already Good

- **Clear module split** by concern — easy to navigate.
- **QwikChild adoption** removes a lot of boilerplate; the `properties.uiView` per-child pattern works cleanly for `ChildTempLight`.
- **PKCE flow** is two-button, matches IKEA's "press hub action button between steps" UX.
- **WebSocket** push model avoids polling — efficient and responsive.
- **Storage metatable** in `setupStorage` is a small, idiomatic abstraction.
- **HSV/RGB helpers** in [Lib.lua#L184-L237](../Lib.lua#L184-L237) are correct standard formulas.
- **Reachability mirror** to `dead` property gives users a meaningful HC3 indicator.
- **Release tooling** (`scripts/`) is unusually thorough for a hobby QA — keep it.

---

## 4. Suggested Follow-up Backlog

Grouped by phase / theme, smallest-first within each group.

### Quick wins (each <30 min, low risk)
1. **F2** — fix `color` global typo (1 line).
2. **F3** — redact secrets from debug logs.
3. **F11** — guard nil `customName`.
4. **F14** — delete commented test calls.
5. **F17** — fix log format/arg mismatches.
6. **F22** — add `Lua.diagnostics.globals` to `.vscode/settings.json`.
7. **F20**, **F23** — strip stale headers, delete `old/`.

### Correctness fixes (target next minor release)
8. **F1** — AirSensor children filter regex (the headline bug). Add a small test fixture if practical.
9. **F4** — switch OAuth URL to `Hub.port`.
10. **F5** — proper base64url for PKCE challenge.
11. **F7** — guard mired clamps + add inversion comment.
12. **F8** — decide & document RGBW `w` handling.
13. **F10** — `safeDecode` helper, applied to all four hot paths.

### Robustness (next refactor cycle)
14. **F9** — WebSocket reconnect with backoff, no `plugin.restart()` on disconnect.
15. **F12** — error path in `onInit` chain (label + retry).
16. **F6** — single HTTP options helper; document cert policy.

### Hygiene / Optional
17. **F15** — drop or test `createScene`.
18. **F16** — env-var token precedence policy.
19. **F18** — replace `ignoreValue` with timestamp window if flicker reported.
20. **F19** — remove dead `fibaro.getIPaddress`.
21. **F21** — single `DG` definition site.
22. **F13** — document AirSensor child id scheme (no rename — preserves existing children).

---

## 5. Out of Scope Notes

- **`old/Devices2.lua`, `old/Dirigera2.lua`** — confirmed legacy per CHANGELOG. Recommend deletion (F23).
- **`scripts/`** — light pass only: scripts are well-structured and reusable; no review issues found.
- **`.fqa` packaging / `--%%save:Dirigera.fqa`** — works as expected, not exercised here.
- **Live HC3 behaviour** — all findings derived from static reading; on-device confirmation recommended for F1, F2, F9 before release.
