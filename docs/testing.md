# Tests and checks

One command runs everything and prints a summary:

```bash
scripts/test-all.sh           # all suites, about 8 minutes
scripts/test-all.sh --quick   # unit tests and the self-test, about a minute, no permissions needed
```

| Suite | What it covers | Needs |
|---|---|---|
| `swift test` | `Sources/BugbearCore`: formatters, converters, JWT, time zones, cron, regex, JSON diff and path, HTTP, test data, the video timeline, size limits, reports, crash reports, scrolling-screenshot stitching, disk tree, updates | nothing |
| `--self-test` | a generated clip with sound through the whole editor (trim, cut, slow motion, freeze, text with and without a label, arrows, blur, clicks, keys), MP4 and GIF export, size limits, annotated and cropped screenshots, OCR, QR codes, step guides, before/after comparison, display stitching | nothing |
| `scripts/e2e.sh` | the real app: buffer, saves, recording with pause, drawing, editor export, system audio, markers, crash auto-save, update check | Screen Recording, Accessibility |
| `scripts/e2e-features.sh` | a Chrome page: scrolling screenshot, window resize, ruler, color picker, design overlay, area recording, shortcuts, Jira and Markdown reports, step guide, comparison, editor sizes, switching between displays, the menu panel, What's New, disk space scan and clean-up | Screen Recording, Accessibility, Chrome |
| `scripts/perf.sh` | CPU and memory idle and while recording, save time | Screen Recording |

The scripts drive the real app through a local automation hook (off by default, switched on only for
the run). They move the mouse and open a Chrome window; don't touch the Mac while they run. Logs of
the last run are in `build/test-logs/`.

The pictures in the README are rendered off screen from a made-up page, so they can be regenerated
on any Mac without permissions: `scripts/readme-media.sh` (needs `ffmpeg`).

GitHub runs `swift test` and the self-test on every pull request; the other suites need macOS
permissions and run only on your Mac. See [CONTRIBUTING.md](../CONTRIBUTING.md).
