# MacAppBar

A macOS menu bar dashboard for deployment status.

The app tracks App Store deployment/build health for apps built through Xcode Cloud. The first tracked app is Memeforge, whose source lives at `/Users/stefan/code/ios-keyboard` and whose GitHub remote is `smirea/memeforge`.

Clicking the menu bar `A` opens a compact deployment popup with the latest Xcode Cloud build number, status, branch, date, App Store build processing state when available, workflow rules, and a manual build button.

## Infrastructure

The app uses SwiftUI `MenuBarExtra` with window-style content and builds as a small Swift Package Manager executable. `scripts/build-app.sh` wraps the release binary into `.build/release/MacAppBar.app` and sets `LSUIElement` so it runs as a menu bar agent instead of a Dock app.

Status and actions come from the App Store Connect API:

- `GET /v1/ciWorkflows/{id}` reads workflow metadata and rules.
- `GET /v1/ciWorkflows/{id}/buildRuns` reads the latest Xcode Cloud build.
- `POST /v1/ciBuildRuns` starts a manual Xcode Cloud build.

The current Memeforge config was pulled from `/Users/stefan/code/ios-keyboard`:

- Xcode Cloud workflow ID: `8A2FE4FD-B115-4866-A097-B6D5247F8ED0`
- Default branch: `master`
- GitHub workflow wrapper: `.github/workflows/testflight-internal.yml`
- Local default private key path: `/Users/stefan/code/app-store-connect-api-key.p8`

The GitHub workflow stores `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, and `APP_STORE_CONNECT_PRIVATE_KEY` as GitHub secrets, then calls `scripts/deploy.sh`. GitHub secret values cannot be read back, so the menu bar app needs equivalent App Store Connect credentials configured locally for status polling and manual builds.

## Local Credentials

Create `~/.config/mac-appbar/app-store-connect.env`:

```sh
mkdir -p ~/.config/mac-appbar
$EDITOR ~/.config/mac-appbar/app-store-connect.env
```

Use this format:

```env
APP_STORE_CONNECT_KEY_ID=your-key-id
APP_STORE_CONNECT_ISSUER_ID=your-issuer-id
APP_STORE_CONNECT_PRIVATE_KEY_PATH=/Users/stefan/code/app-store-connect-api-key.p8
```

The app also accepts the same values from the process environment. Do not commit App Store Connect keys or private key contents.

Build the app:

```sh
./scripts/build-app.sh
```

Run it, building first if needed:

```sh
./scripts/run.sh
```

## Login Item

Use the `Start at login` toggle at the bottom of the popup to register or unregister the app with macOS Login Items. This uses Apple's `SMAppService.mainApp` API, so the setting is also visible in System Settings under Login Items.

## Bartender

Bartender does not expose a documented push-style API for another app to tell it "show this menu item now." The practical integration is a Bartender AppleScript trigger that polls this app's local state file:

`~/.cache/mac-appbar/bartender-state.json`

MacAppBar writes `needs_attention: true` when a build is running, fails, errors, or when the tracked deployment status changes. The menu bar icon also changes from `a.circle` to `a.circle.fill` until `Mark Seen` is clicked.

Use this AppleScript as a Bartender trigger condition:

```applescript
try
	set stateJSON to do shell script "/usr/bin/python3 - <<'PY'\nimport json\nfrom pathlib import Path\npath = Path.home() / '.cache/mac-appbar/bartender-state.json'\nprint('true' if path.exists() and json.loads(path.read_text()).get('needs_attention') else 'false')\nPY"
	return stateJSON is "true"
on error
	return false
end try
```
