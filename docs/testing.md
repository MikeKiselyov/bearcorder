# Tests and checks

One command runs everything and prints a summary:

```bash
scripts/test/all.sh           # all suites, about 10 minutes (make test-all)
scripts/test/all.sh --quick   # unit tests, self-test, lint and the release check, about 2 minutes, no permissions (make test)
```

| Suite | What it covers | Needs |
|---|---|---|
| `swift test` (`--parallel` in `all.sh` and CI) | `Sources/BugbearCore`: formatters, converters, JWT, time zones, cron, regex, JSON diff and path, HTTP, test data, the video timeline, size limits, reports, crash reports, scrolling-screenshot stitching, disk tree, updates | nothing |
| `--self-test` | a generated clip with sound through the whole editor (trim, cut, slow motion, freeze, text with and without a label, arrows, blur, clicks, keys), MP4 and GIF export, size limits, annotated and cropped screenshots, OCR, QR codes, step guides, before/after comparison, display stitching | nothing |
| `scripts/test/e2e.sh` | the real app: buffer, saves, recording with pause, drawing, editor export, system audio, markers, crash auto-save, update check | Screen Recording, Accessibility |
| `scripts/test/e2e-features.sh` | a Chrome page: scrolling screenshot, window resize, ruler, color picker, design overlay, area recording, shortcuts, Jira and Markdown reports, step guide, comparison, editor sizes, switching between displays, the menu panel, What's New, disk space scan and clean-up | Screen Recording, Accessibility, Chrome |
| `scripts/test/perf.sh` | CPU and memory idle and while recording, save time | Screen Recording |
| `make lint` | `shellcheck` on every script, `actionlint` on the CI workflows, every control has a check | `brew install shellcheck actionlint` |

The scripts drive the real app through a local automation hook (off by default, switched on only for
the run). They move the mouse and open a Chrome window; don't touch the Mac while they run. Logs of
the last run are in `build/test-logs/`.

A command goes out through a small sender (`scripts/dev/bugbear-send.swift`, compiled with `swiftc` into
`.build/bugbear-send` the first time and when the source changes; `osascript` is the fallback). The
script that waits for a result (`scripts/dev/bugbear-run.sh`) adds ` #id=<token>` to the command, and the
app writes the result to `~/Library/Application Support/Bugbear/automation/results/<token>`, which the
script reads and deletes (the log line stays). `press-menu:<tab>:<label>` opens the menu panel, picks the
tab and presses the control in one command. `press:<window>:<label>` answers after a moment for the window to
redraw; `press-now:` (and `choose-now:` for pickers) answers right after the press, for steps that then wait
for what the press did (`press_now` in `scripts/test/lib/e2e-helpers.sh`). `e2e-features.sh` prints how long each section took, slowest
first, at the end; `scripts/test/e2e-section.sh "<title>"` runs one section.

`scripts/test/all.sh` (without `--quick`) builds and signs the test app once (`app-build`, with automation) and sets
`BUGBEAR_APP_BUILT=1`; `e2e.sh`, `e2e-features.sh`, `e2e-section.sh` and `perf.sh` then use `build/Bugbear.app` as it is and stop
with "run scripts/build-app.sh first" if it is missing. Run on their own they build it themselves. The welcome-guide
checks in `e2e-features.sh` install that build with `scripts/build-app.sh --install-only` (same install and permission handling
as `--install`, no `swift build`, no signing).

They test the copy in `build/`, so an installed Bugbear is quit for the run and started again
afterwards, even when a run fails or is stopped with Ctrl-C.

The pictures in the README are rendered off screen from a made-up page, so they can be regenerated
on any Mac without permissions: `scripts/dev/readme-media.sh` (needs `ffmpeg`).

GitHub runs `swift test --parallel` and the self-test on every pull request; the other suites need macOS
permissions and run only on your Mac. The parallel runner prints `[n/total]` lines and no "Executed N tests" summary, so `scripts/test/all.sh` counts those lines. The uninstall tests give the script a small file in place of `lsregister -dump` (`BUGBEAR_LSREGISTER_DUMP`), which takes 5-7 s on a real Mac. See [CONTRIBUTING.md](../CONTRIBUTING.md).
