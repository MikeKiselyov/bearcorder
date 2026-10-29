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

`make` lists the everyday tasks (`make app`, `make test`, `make test-all`, `make lint`, `make media`);
each one runs a script in `scripts/`.

## Your own bundle id and signing identity

Personal settings go into `.env`, which is git-ignored and never committed:

```bash
cp .env.example .env
```

| Variable | Meaning |
|---|---|
| `BUGBEAR_BUNDLE_ID` | Bundle identifier of your build. Default `io.github.bugbear.app`. |
| `BUGBEAR_SIGN_IDENTITY` | Code signing identity. Empty: the first "Apple Development" identity in your keychain, otherwise a certificate made for this Mac. `local`: always that certificate. `-`: ad-hoc. |

Why the identity matters: macOS ties the Screen Recording, Camera and Microphone permissions to the
app's signature. With ad-hoc signing every rebuild looks like a new app and macOS asks again.

Without `BUGBEAR_SIGN_IDENTITY` the build uses the first Apple Development certificate (free, from
Xcode → Settings → Accounts). A Mac without one, for example with only the Command Line Tools, gets
a certificate made for it by `scripts/dev/local-signing.sh`: a self-signed code signing certificate in
its own keychain under `~/Library/Application Support/Bugbear/Signing/`, with a random password kept
next to it. That keychain is added to the keychain search list because codesign only looks there.
The certificate signs nothing but Bugbear builds and keeps the same signature between updates.
`scripts/dev/local-signing.sh remove` deletes it.
List your identities with `security find-identity -v -p codesigning`.

## Text and languages

Every text people see comes from `Sources/Bugbear/Resources/Localization/<language>.lproj/`, one table
per part of the app (`menubar.strings`, `settings.strings`, ...). Code asks for it by key:

```swift
Button(L("feedback.button.cancel")) { ... }
Text(L("feedback.logs.zipNote", AppInfo.name, folder))   // "... %1$@ ... %2$@ ..." in the table
```

- A key starts with its table: `feedback.button.cancel` is in `feedback.strings`. Keys are written out,
  never built from parts, so the tests can check them.
- Values go in as printf placeholders: `%@` for text, `%ld` for whole numbers (Int); two or more are numbered
  (`%1$@`) so a translation can put them in another order.
- English (`en.lproj`) has every key. To add a language, copy `en.lproj` to `<code>.lproj` (e.g.
  `de.lproj`, `pt-BR.lproj`) and translate the values. Nothing else changes: the app picks the first of
  the person's languages it has and falls back to English for a missing key.
- Not translated: logs, the release notes (`WhatsNewCatalog`), and what goes into bug reports and issues
  (environment fields, steps), which are written for the team that reads them.
- `RepoTests/LocalizationTests` fails on a key the tables lack, a key nothing uses, a language with
  other keys or placeholders than English, and text written straight into a view or an alert.

## How updates work

- The app reads `Sources/BugbearCore/Support/WhatsNewCatalog.swift` from `raw.githubusercontent.com` on
  the branch it was built from and compares the top release version with its own. Only a higher
  version counts as an update. Then it asks `api.github.com` for the commits since the build to list them.
- **Update now** runs `scripts/update.sh` in the source folder: `git pull --ff-only`, build, replace the
  app, relaunch. If the folder has uncommitted changes, it stops and says so instead of touching them.
- A fork updates from the fork: the repository comes from the clone's `origin`.
- The same by hand: `~/.bugbear/scripts/update.sh`.

## Renaming the app

The name people see lives in `Sources/BugbearCore/Support/AppInfo.swift` (`AppInfo.name`); the app and
the scripts read it from there. Markdown cannot, so rename with:

```bash
scripts/dev/rename-app.sh "New Name"
```

It changes `AppInfo.name`, the installer's copy and the name in `README.md` and `docs/`. Folders with
captures and logs (`AppInfo.storageName`), source folders and the executable keep the old name, so
updates find people's captures. `swift test` fails while the docs show another name. The executable stays
`Bugbear` too: write commands that call it with a path (`.build/debug/Bugbear --self-test`), or the
script renames them.

## Project layout

```
Package.swift             targets: BugbearCore, Bugbear, BugbearCoreTests, RepoTests
Sources/BugbearCore/      pure logic, no UI: toolbox, time, timeline and crop math, reports, stitching
Sources/Bugbear/
  App/                    entry point; AppState, split by concern (AppState+Buffer, +Recording, ...)
  Capture/                screen buffer, exporter, screenshots, environment, input events
  Recording/              recording session, HUD, draw-on-screen, camera bubble, area picker, ruler
  Annotations/            annotation model and renderer (shared by editor, export, live overlay)
  Editors/                screenshot and video editors
  Toolbox/                dev toolbox screens
  MenuBar/, History/, Onboarding/, Space/
  Settings/               settings model and window, shortcuts, what the editors remember
  Feedback/, Updates/     "Report a problem"; update check and relaunch
  UI/                     theme, tooltips, toasts, pop-up menus, text input, logo
  Support/                resources, log, global hot keys, system actions
  DevTools/               automation, self-test, README and What's New media (debug and test builds only)
  Resources/WhatsNew/     What's New pictures (SwiftPM resources, read through AppResources)
Tests/BugbearCoreTests/   the logic, by area (Capture, Video, Toolbox, Support, Disk)
Tests/RepoTests/          the repository: docs pictures, scripts, packaging, release notes
Packaging/Info.plist      the app's Info.plist; build-app.sh fills in the build's values
scripts/                  what people run: install.sh, update.sh, uninstall.sh, build-app.sh
  lib/                    sourced by the others: common.sh (ROOT, die), app-name.sh, permissions.sh
  test/                   test runs: all.sh, e2e.sh, e2e-features.sh, e2e-section.sh, perf.sh
    lib/                  what the test runs share: test-app.sh, e2e-helpers.sh, window-fits.py
  check/                  CI checks: release.sh, no-automation.sh, control-coverage.py + controls.txt
  dev/                    tools for working on the app: readme-media.sh, rename-app.sh,
                          local-signing.sh, bugbear-run.sh and bugbear-command.sh (automation)
Makefile                  one entry point for the scripts
docs/                     these docs; images/ holds the README pictures
```

`DevTools/` is compiled only with the `AUTOMATION` flag: debug builds have it, and
`BUGBEAR_AUTOMATION=1 scripts/build-app.sh` builds the app the tests drive. A release has no automation
hook, so nothing outside can drive it; `scripts/check/no-automation.sh` checks that (CI too).

Some paths are read by copies of the app that are already installed, so they never move:
`scripts/install.sh` (the install command downloads it), `scripts/update.sh` (Update now runs it in the
source folder) and `Sources/BugbearCore/Support/WhatsNewCatalog.swift` (the update check reads it from
GitHub). `build-app.sh` stays at the top of `scripts/` too: an older `update.sh` calls it after the pull.
`install.sh`, `update.sh` and `uninstall.sh` do not source `scripts/lib`: they run from a
downloaded copy or an older checkout.

Scripts start with `set -euo pipefail`; the test runners use `set -uo pipefail` on purpose, so one
failed check is reported and the run goes on. `shellcheck` (`make lint`, and CI) keeps them clean.

CI (`.github/workflows/ci.yml`) runs with a read-only token; only the `release` job, on a push to `main`
and after the tests pass, can write tags and releases. Actions are pinned to a commit, Dependabot
(`.github/dependabot.yml`) proposes updates, and the shellcheck and actionlint downloads are checked
against their sha256. `actionlint` (`make lint`, and CI) checks the workflows.

The logo (a bear looking at a bug through a magnifying glass) is one flat shape drawn in code in `UI/Logo.swift`: the menu bar
glyph, the in-app logo and the app icon are the same picture. The build script renders the `.icns` from it.

Where the app keeps captures, the buffer and logs: [uninstall.md](uninstall.md#where-bugbear-keeps-things).


See also [Tests and checks](testing.md) and [Contributing](../CONTRIBUTING.md).
