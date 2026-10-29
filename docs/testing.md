# Tests and checks

One command runs everything and prints a summary:

```bash
scripts/test/all.sh           # all suites, about 10 minutes (make test-all)
scripts/test/all.sh --quick   # unit tests, self-test, lint and the release check, about 2 minutes, no permissions (make test)
```

| Suite | What it covers | Needs |
|---|---|---|
| `swift test` | `Sources/BugbearCore`: formatters, converters, JWT, time zones, cron, regex, JSON diff and path, HTTP, test data, the video timeline, size limits, reports, crash reports, scrolling-screenshot stitching, disk tree, updates | nothing |
| `--self-test` | a generated clip with sound through the whole editor (trim, cut, slow motion, freeze, text with and without a label, arrows, blur, clicks, keys), MP4 and GIF export, size limits, annotated and cropped screenshots, OCR, QR codes, step guides, before/after comparison, display stitching | nothing |
| `scripts/test/e2e.sh` | the real app: buffer, saves, recording with pause, drawing, editor export, system audio, markers, crash auto-save, update check | Screen Recording, Accessibility |
| `scripts/test/e2e-features.sh` | a Chrome page: scrolling screenshot, window resize, ruler, color picker, design overlay, area recording, shortcuts, Jira and Markdown reports, step guide, comparison, editor sizes, switching between displays, the menu panel, What's New, disk space scan and clean-up | Screen Recording, Accessibility, Chrome |
| `scripts/test/perf.sh` | CPU and memory idle and while recording, save time | Screen Recording |
| `make lint` | `shellcheck` on every script, `actionlint` on the CI workflows, every control has a check | `brew install shellcheck actionlint` |

The scripts drive the real app through a local automation hook (off by default, switched on only for
the run). They move the mouse and open a Chrome window; don't touch the Mac while they run. Logs of
the last run are in `build/test-logs/`.

They test the copy in `build/`, so an installed Bugbear is quit for the run and started again
afterwards, even when a run fails or is stopped with Ctrl-C.

The pictures in the README are rendered off screen from a made-up page, so they can be regenerated
on any Mac without permissions: `scripts/dev/readme-media.sh` (needs `ffmpeg`).

GitHub runs `swift test` and the self-test on every pull request; the other suites need macOS
permissions and run only on your Mac. See [CONTRIBUTING.md](../CONTRIBUTING.md).
