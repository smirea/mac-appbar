# MacAppBar

A macOS menu bar dashboard for deployment status.

The app tracks App Store deployment/build health for apps built through Xcode Cloud. The first tracked app is Memeforge, whose source lives at `/Users/stefan/code/ios-keyboard` and whose GitHub remote is `smirea/memeforge`.

Clicking the App Store compass icon opens a compact deployment popup with the latest Xcode Cloud build number, status, branch, date, App Store build processing state when available, workflow rules, and a manual build button.

## Infrastructure

The app uses SwiftUI `MenuBarExtra` with window-style content and builds as a small Swift Package Manager executable. `scripts/build-app.sh` wraps the release binary into `.build/release/MacAppBar.app`, adds the app icon, and sets `LSUIElement` so it runs as a menu bar agent instead of a Dock app.

The App Store-style compass icon comes from the SVG Logos `Apple App Store` icon through Iconify/shadcn, listed as CC0.

Status and actions come from the App Store Connect API:

- `GET /v1/apps` can discover App Store Connect apps.
- `GET /v1/ciProducts` can discover Xcode Cloud products.
- `GET /v1/ciWorkflows/{id}` reads workflow metadata and rules.
- `GET /v1/ciWorkflows/{id}/buildRuns` reads the latest Xcode Cloud build.
- `POST /v1/ciBuildRuns` starts a manual Xcode Cloud build.

The current Memeforge config was pulled from `/Users/stefan/code/ios-keyboard`:

- Xcode Cloud workflow ID: `8A2FE4FD-B115-4866-A097-B6D5247F8ED0`
- Default branch: `master`
- GitHub workflow wrapper: `.github/workflows/testflight-internal.yml`
- Local private key path: `secrets/app-store-connect-api-key.p8`

The GitHub workflow stores `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, and `APP_STORE_CONNECT_PRIVATE_KEY` as GitHub secrets, then calls `scripts/deploy.sh`. GitHub secret values cannot be read back, so the menu bar app needs equivalent App Store Connect credentials configured locally for status polling and manual builds.

## Local Credentials

This repo is set up as the `mac-appbar` project in `env-manager`. The local env-manager files contain the known Xcode Cloud workflow ID, default branch, and copied private-key file path. `APP_STORE_CONNECT_PRIVATE_KEY` is a required `file` value, so env-manager stores the `.p8` contents in the project secret and recreates the file on `env-manager down`.

The setup still needs the App Store Connect key ID and issuer ID. They are stored in GitHub secrets for `smirea/memeforge`, but GitHub does not allow reading secret values back.

Fill the missing values in `.env.local` or create `~/.config/mac-appbar/app-store-connect.env`:

```sh
mkdir -p ~/.config/mac-appbar
$EDITOR ~/.config/mac-appbar/app-store-connect.env
```

Use this format:

```env
APP_STORE_CONNECT_KEY_ID=your-key-id
APP_STORE_CONNECT_ISSUER_ID=your-issuer-id
APP_STORE_CONNECT_PRIVATE_KEY=secrets/app-store-connect-api-key.p8
```

Then sync:

```sh
env-manager up --project mac-appbar
```

The app reads the process environment, `~/.config/mac-appbar/app-store-connect.env`, and this repo's `.env.local`. `APP_STORE_CONNECT_PRIVATE_KEY` can be either inline PEM contents or a path to the `.p8` file. Do not commit App Store Connect keys or private key contents.

## App Discovery

You do not need a separate App Store Connect API key for every app. A team API key is team-scoped and can cover all apps in that App Store Connect team with the selected role permissions. Create separate keys only when you want a separate role, owner, rotation schedule, or blast radius.

You cannot programmatically recover an existing key's private key or GitHub secret value after it has been created. Apple lets you download the private key once, and GitHub secrets are write-only after upload.

Once credentials are complete, all apps can be discovered through App Store Connect:

- `GET /v1/apps` lists apps.
- `GET /v1/ciProducts?include=workflows,app` lists Xcode Cloud products and their workflows.
- `GET /v1/ciProducts/{id}/workflows` lists workflows for one Xcode Cloud product.

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

MacAppBar writes `needs_attention: true` when the latest deployment state differs from the last state seen in the popup. The state file stores both `current_signature` and `seen_signature`, so the app can compute attention correctly after boot. Opening the popup marks the current state as seen automatically. The menu bar icon switches from muted to full color while attention is needed.

When unread state is detected, MacAppBar also asks Bartender to show its menu item with Bartender's AppleScript `show` command. The menu item ID is `dev.stefan.MacAppBar-Item-0`.

For the most reliable setup, keep MacAppBar hidden in Bartender and add a trigger that shows it while this script condition is true:

```sh
/Users/stefan/code/mac-appbar/scripts/bartender-should-show.sh
```

If Bartender asks for AppleScript instead of shell script, use this wrapper:

```applescript
try
	set stateJSON to do shell script "/Users/stefan/code/mac-appbar/scripts/bartender-should-show.sh"
	return stateJSON is "true"
on error
	return false
end try
```
