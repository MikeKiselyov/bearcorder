# Development

## Build from a clone

```bash
git clone https://github.com/MikeKiselyov/bugbear-app.git
cd bugbear-app
scripts/build-app.sh --run        # builds build/Bugbear.app and launches it
scripts/build-app.sh --install    # or: copies it to /Applications (or ~/Applications) and launches it
```

You need Apple's Command Line Tools or Xcode 16+ (Swift 6). Updates work the same way for a clone:
the app rebuilds from the folder it was built in.

## Your own bundle id and signing identity

Personal settings go into `.env`, which is git-ignored and never committed:

```bash
cp .env.example .env
```

| Variable | Meaning |
|---|---|
| `BUGBEAR_BUNDLE_ID` | Bundle identifier of your build. Default `io.github.bugbear.app`. |
| `BUGBEAR_SIGN_IDENTITY` | Code signing identity. Empty: the first "Apple Development" identity in your keychain. `-`: ad-hoc. |

Why sign with a real identity: macOS ties the Screen Recording, Camera and Microphone permissions to
the app's signature. With ad-hoc signing every rebuild looks like a new app and macOS asks again.
A free Apple Development certificate (Xcode → Settings → Accounts) avoids that.
List your identities with `security find-identity -v -p codesigning`.

## How updates work

- The app reads `Sources/BugbearCore/Support/WhatsNewCatalog.swift` from `raw.githubusercontent.com` on
  the branch it was built from and compares the top release version with its own. Only a higher
  version counts as an update. Then it asks `api.github.com` for the commits since the build to list them.
- **Update now** runs `scripts/update.sh` in the source folder: `git pull --ff-only`, build, replace the
  app, relaunch. If the folder has uncommitted changes, it stops and says so instead of touching them.
- A fork updates from the fork: the repository comes from the clone's `origin`.
- The same by hand: `~/.bugbear/scripts/update.sh`.

## Project layout

```
Sources/BugbearCore/     pure logic, no UI: toolbox, time, timeline math, reports, stitching
Sources/Bugbear/
  App/                    entry point, app state, windows
  Capture/                screen buffer, exporter, screenshots, environment, input events
  Recording/              recording session, HUD, draw-on-screen, camera bubble, area picker, ruler
  Annotations/            annotation model and renderer (shared by editor, export, live overlay)
  Editors/                screenshot and video editors
  Toolbox/                dev toolbox screens
  MenuBar/, History/, Settings/, Onboarding/
scripts/                  install, update, build, e2e and perf checks, README pictures
docs/                     these docs; images/ holds the README pictures
```

The logo (a bear eating a bun) is one flat shape drawn in code in `Support/Logo.swift`: the menu bar
glyph, the in-app logo and the app icon are the same picture. The build script renders the `.icns` from it.

Where the app keeps captures, the buffer and logs: [uninstall.md](uninstall.md#where-bugbear-keeps-things).


See also [Tests and checks](testing.md) and [Contributing](../CONTRIBUTING.md).
