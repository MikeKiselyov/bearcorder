# Development

## Build from a clone

```bash
git clone https://github.com/MikeKiselyov/bearcorder.git
cd bearcorder
scripts/build-app.sh --run        # builds build/Bearcorder.app and launches it
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
| `APP_BUNDLE_ID` | Bundle identifier of your build. Default `io.github.bearcorder.app`. |
| `APP_SIGN_IDENTITY` | Code signing identity. Empty: the first "Apple Development" identity in your keychain, otherwise a certificate made for this Mac. `local`: always that certificate. `-`: ad-hoc. |

Why the identity matters: macOS ties the Screen Recording, Camera and Microphone permissions to the
app's signature. With ad-hoc signing every rebuild looks like a new app and macOS asks again.

Without `APP_SIGN_IDENTITY` the build uses the first Apple Development certificate (free, from
Xcode → Settings → Accounts). A Mac without one, for example with only the Command Line Tools, gets
a certificate made for it by `scripts/dev/local-signing.sh`: a self-signed code signing certificate in
its own keychain under `~/Library/Application Support/Bearcorder/Signing/`, with a random password kept
next to it. That keychain is added to the keychain search list because codesign only looks there.
The certificate signs nothing but Bearcorder builds and keeps the same signature between updates.
`scripts/dev/local-signing.sh remove` deletes it.
List your identities with `security find-identity -v -p codesigning`.

## Text and languages

Every text people see comes from `Sources/App/Resources/Localization/<language>.lproj/`, one table
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

- The app reads `Sources/AppCore/Support/WhatsNewCatalog.swift` from `raw.githubusercontent.com` on
  the branch it was built from and compares the top release version with its own. Only a higher
  version counts as an update. Then it asks `api.github.com` for the commits since the build to list them.
- **Update now** runs `scripts/update.sh` in the source folder: `git pull --ff-only`, build, replace the
  app, relaunch. If the folder has uncommitted changes, it stops and says so instead of touching them.
- A fork updates from the fork: the repository comes from the clone's `origin`.
- The same by hand: `~/.bearcorder/scripts/update.sh`.

## Renaming the app

The name lives in one place, `Sources/AppCore/Support/AppInfo.swift` (`AppInfo.name`). The app and the
scripts (`scripts/lib/app-name.sh`) read it from there, and so does everything that follows from it: the
`.app` and its executable, the folders in `~/Library` and on the Desktop, the GitHub repository, the
installer's bundle id and source folder (`AppInfo.slug`, the name in lower case). Code, folders and
targets have neutral names (`Sources/App`, `AppCore`, `APP_*` variables), so they never change.
Markdown, the installer and the uninstaller cannot read the name, so rename with:

```bash
scripts/dev/rename-app.sh "New Name"
```

It changes `AppInfo.name`, the installer's and uninstaller's copies, and the name, links and paths in
`README.md`, `CONTRIBUTING.md`, `docs/`, the issue forms and `.env.example`. Then make the pictures again
(`scripts/dev/readme-media.sh`, What's New) and rename the repository on GitHub. Nothing is moved on
people's Macs: a copy installed under the old name keeps its folders and is uninstalled with the old
uninstall command. `swift test` fails while the docs show another name (`AppNameTests`) or code says the
name itself (`AppNameInOnePlaceTests`). The executable built from the source is always
`.build/debug/App`; debug builds link `Packaging/Debug-Info.plist`, so its runs keep their settings under
`io.github.<slug>.debug`, not under `App`.

## Project layout

```
Package.swift             targets: AppCore, App, AppCoreTests, RepoTests
Sources/AppCore/          pure logic, no UI: toolbox, time, timeline and crop math, reports, stitching
Sources/App/
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
Tests/AppCoreTests/       the logic, by area (Capture, Video, Toolbox, Support, Disk)
Tests/RepoTests/          the repository: docs pictures, scripts, packaging, release notes
Packaging/Info.plist      the app's Info.plist; build-app.sh fills in the build's values
scripts/                  what people run: install.sh, update.sh, uninstall.sh, build-app.sh
  lib/                    sourced by the others: common.sh (ROOT, die), app-name.sh, permissions.sh,
                          replace-app.sh
  test/                   test runs: all.sh, e2e.sh, e2e-features.sh, e2e-section.sh, perf.sh
    lib/                  what the test runs share: test-app.sh, e2e-helpers.sh, window-fits.py
  check/                  CI checks: release.sh, no-automation.sh, control-coverage.py + controls.txt
  dev/                    tools for working on the app: readme-media.sh, rename-app.sh,
                          local-signing.sh, app-run.sh, app-command.sh and
                          app-send.swift (automation; see docs/testing.md)
Makefile                  one entry point for the scripts
docs/                     these docs; images/ holds the README pictures
```

`DevTools/` is compiled only with the `AUTOMATION` flag: debug builds have it, and
`APP_AUTOMATION=1 scripts/build-app.sh` builds the app the tests drive. A release has no automation
hook, so nothing outside can drive it; `scripts/check/no-automation.sh` checks that (CI too).

Some paths are read by copies of the app that are already installed, so they do not move:
`scripts/install.sh` (the install command downloads it), `scripts/update.sh` (Update now runs it in the
source folder) and `Sources/AppCore/Support/WhatsNewCatalog.swift` (the update check reads it from
GitHub). Moving one leaves the copies installed before it without updates. `build-app.sh` stays at the top of `scripts/` too: an older `update.sh` calls it after the pull.
`install.sh` and `uninstall.sh` do not source `scripts/lib`: they run from a downloaded copy.
`update.sh` sources `scripts/lib/app-name.sh` at the start, before the fetch, from the checkout as it
is, and `scripts/lib/permissions.sh` and `scripts/lib/replace-app.sh` after the pull and the build, from
the updated checkout. Both `update.sh` and `build-app.sh --install` put the app in place through
`replace_app`: the build goes in only when `codesign --verify` passes and its executable reports the
version it was built as; the old copy waits in a temporary folder and comes back if anything fails.

Scripts start with `set -euo pipefail`; the test runners use `set -uo pipefail` on purpose, so one
failed check is reported and the run goes on. `shellcheck` (`make lint`, and CI) keeps them clean.

CI (`.github/workflows/ci.yml`) runs with a read-only token; only the `release` job, on a push to `main`
and after the tests pass, can write tags and releases. Actions are pinned to a commit, Dependabot
(`.github/dependabot.yml`) proposes updates, and the shellcheck and actionlint downloads are checked
against their sha256. `actionlint` (`make lint`, and CI) checks the workflows. The test job caches `.build`
(`actions/cache`); the key has the Swift version and the hash of `Package.resolved`, and an older cache of
the same Swift version is the fallback. The test job also runs with code coverage and writes a table for
`Sources/AppCore` to the job summary; it is information only, with no threshold.

The logo (a bear looking at a bug through a magnifying glass) is one flat shape drawn in code in `UI/Logo.swift`: the menu bar
glyph, the in-app logo and the app icon are the same picture. The build script renders the `.icns` from it.

Where the app keeps captures, the buffer and logs: [uninstall.md](uninstall.md#where-bearcorder-keeps-things).


See also [Tests and checks](testing.md) and [Contributing](../CONTRIBUTING.md).
