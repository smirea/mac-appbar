# MacAppBar

A tiny macOS menu bar app starter.

It uses SwiftUI `MenuBarExtra`, which is the current first-party API for simple menu bar extras on macOS 13 and newer. The app is built with Swift Package Manager to keep the repo small, then `scripts/build-app.sh` wraps the release executable in a local `.app` bundle with `LSUIElement` so it runs as a menu bar agent instead of showing in the Dock.

Build the app:

```sh
./scripts/build-app.sh
```

Run it, building first if needed:

```sh
./scripts/run.sh
```

The menu bar item uses a generic `A` symbol. Clicking it opens a dropdown with a todo message and a Quit command.
