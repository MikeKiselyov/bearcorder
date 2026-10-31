<p align="center">
  <img src="docs/images/logo.png" width="128" alt="Bearcorder logo: a bear looking at a bug through a magnifying glass">
</p>

<h1 align="center">Bearcorder</h1>

<p align="center">
  A macOS menu bar app. The last minutes of your screen are always kept,<br>
  so whatever you just saw is already recorded.
</p>

<p align="center">
  <a href="https://github.com/MikeKiselyov/bearcorder/releases/latest"><img src="https://img.shields.io/github/v/release/MikeKiselyov/bearcorder" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14 or later">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT license"></a>
</p>

<p align="center">
  <img src="docs/images/buffer-save.gif" width="820" alt="Saving the last minute from the menu, the clip in the editor, then the other display">
</p>

Bearcorder is a screen recorder and screenshot tool for anyone who needs to show what happened on screen: developers, designers, testers, support. It also has tools for everyday work:

- Screenshots with markup, a video editor and bug reports with steps, expected and actual result.
- Layout checks: window sizes, measure, color and contrast, design overlay.
- A dev toolbox: JSON, JWT, time zones, test data, regex and more.
- Space, a disk clean-up for the files that builds and tests leave behind.

<p align="center">
  <img src="docs/images/screenshot-editor.gif" width="820" alt="Marking up a screenshot: numbered steps, blur, box, arrow, label">
</p>

Everything runs on your Mac. Nothing is uploaded anywhere.

To install, open **Terminal** and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/MikeKiselyov/bearcorder/main/scripts/install.sh | bash
```

More in [Install](#install). All features, with pictures: **[docs/features.md](docs/features.md)**.

## Contents

- [Install](#install)
- [First start](#first-start)
- [Shortcuts](#shortcuts)
- [What it does](#what-it-does)
- [Updates](#updates)
- [Permissions](#permissions)
- [More: uninstall, help, development](#more)

## Install

You need macOS 14 Sonoma or later (Apple silicon or Intel). Open **Terminal** and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/MikeKiselyov/bearcorder/main/scripts/install.sh | bash
```

<p align="center">
  <img src="docs/images/install.gif" width="720" alt="The installer in Terminal">
</p>

What happens:

1. The installer checks macOS and Apple's free Command Line Tools (Xcode is not needed). If the tools
   are missing, macOS shows a dialog to install them (about 5 minutes); run the command again afterwards.
2. The source is downloaded to `~/.bearcorder`.
3. The app is built on your Mac (the first build takes a few minutes) and copied to `/Applications`
   (or `~/Applications` without an admin account).
4. Bearcorder starts. Look for the **bear icon** in the menu bar. There is no Dock icon.

Nothing is downloaded except the source code: every copy is built and signed on the Mac that runs it.
Want to read the script first? It is [`scripts/install.sh`](scripts/install.sh).

Installed before 0.15.0? That copy has the app's old name and does not update. Remove it first with
`curl -fsSL https://raw.githubusercontent.com/MikeKiselyov/bearcorder/v0.14.0/scripts/uninstall.sh | bash`,
then install as usual.

## First start

A short guide opens on first launch:

1. **Screen buffer**: keep the last 1, 2, 3 or 5 minutes of the screen, or turn it off. With it off nothing
   runs in the background; screenshots, recordings and the toolbox work the same.
2. **Permissions**: the only one the app needs is **Screen & System Audio Recording**. Allow it when macOS
   asks, then press **Relaunch** in the guide. Everything else is optional (see [Permissions](#permissions)).
3. **Shortcuts** and a quick try.

Change any of it later in Settings, and reopen the guide from there.

<p align="center">
  <img src="docs/images/onboarding-2.png" width="520" alt="First-start guide: keep the last minutes of the screen or turn the buffer off">
</p>

Click the bear to open the panel. It has five tabs: **Capture**, **Record**, **Tools**, **Recent** and **Space**.

<p align="center">
  <img src="docs/images/menu.gif" width="300" alt="The menu bar panel tabs">
</p>

## Shortcuts

All of them work from any app. Change them, or give one to the actions that have none, in
**Settings → Shortcuts**.

| Shortcut | Action |
|---|---|
| `⌥⇧1` / `⌥⇧2` / `⌥⇧3` | Save the last 30 s / 1 min / whole buffer and open it in the video editor |
| `⌥⇧M` | Mark the moment the bug happened; the next save reaches back to include it |
| `⌥⇧4` / `⌥⇧5` | Screenshot an area / a window |
| `⌥⇧6` / `⌥⇧7` | Start or stop recording / pause or resume |
| `⌥⇧A` | Draw on the screen while recording |
| `⌥⇧C` | Webcam bubble |
| `⌥⇧O` | Copy text (or a QR code link) from a screen area |
| `⌥⇧D` | Dev toolbox with whatever is on the clipboard |
| not set | Scrolling screenshot, measure on screen, pick a color |

## What it does

### Rolling screen buffer

The app keeps the last 1-5 minutes of the screen on disk; older parts are deleted as it goes.
A bug you could not reproduce is already recorded: press `⌥⇧1` and it opens in the editor.
The buffer is optional: choose it in the first-start guide, pause it from the menu bar, or turn it off in
Settings → Buffer.

- Light on the Mac: a few percent of one CPU core and about 70 MB of memory with two displays.
  Saving 30 seconds is instant.
- System audio and microphone are optional.
- Clicks and shortcut keys are recorded alongside, so the editor can show them on the video.
  What you type is kept as text only if you turn on Show what I type in steps; password fields are
  never read.
- When an app you used in the last 10 minutes crashes, the minute before the crash is saved to
  Recent automatically, with the macOS crash report next to it.
- Each saved clip gets the tested app's system log for the same seconds (`system.log`).

### Several displays

The buffer keeps every connected display. A saved clip holds each display on its own, so saving stays
instant, and the video editor has a switch at the top: one display, another, or all of them side by side.
It opens on the display the pointer was on. Trims, cuts, arrows and text stay when you switch; clicks are
placed for the picture you pick.

Full-screen screenshots work the same way: every display is taken at once, the editor opens on the one
under the pointer (or side by side for "All displays"), and a switch at the bottom changes it. Marks are
drawn on a picture, so each display keeps its own and they come back when you switch back. `⌥⇧4` picks an
area on any display.

| | All displays kept (default) | Main display only (Settings → Buffer) |
|---|---|---|
| Buffer, `⌥⇧1`-`⌥⇧3` | every display; switch in the editor | the main display |
| Recording, full screen | every display; switch in the editor | the display under the pointer |
| Recording an area | the display the area is on | the display the area is on |
| Screenshot, full screen | every display; opens on the one under the pointer | the same |
| Screenshot, all displays | every display; opens side by side | the same |

While recording, displays that are not in the video are dimmed and say "Not recorded". Connecting or
disconnecting a display restarts the buffer with the new set; when every display goes away (a closed lid,
a sleeping Mac), the buffer starts again by itself once one is back. The first-start guide asks whether to keep
all displays when more than one is connected.

### Video editor

<p align="center">
  <img src="docs/images/video-editor.png" width="820" alt="Video editor with timeline, clicks, keys and marks">
</p>

- Trim, cut out parts, slow motion, freeze frame.
- Text, arrows, boxes and blur with their own time ranges on the timeline: drag a bar to move it,
  its edges to make it longer or shorter. Click with Text and type right on the video. `+` and `-`
  resize marks. Text sits on a colored label or, with Background → Transparent, is drawn as outlined
  letters.
- Highlight clicks, show keystrokes, environment badge.
- Crop the video to the part of the screen that matters.
- Export MP4 or GIF with a size limit (10-100 MB) for trackers that cap attachments.

### Recording

<p align="center">
  <img src="docs/images/record-area-picker.png" width="720" alt="Picking a recording area with ready sizes">
</p>

- Record full screen, all displays, or an area: ready sizes (720p, 1080p, 1440×900, 16:9, 4:3, 1:1,
  phone) or your own. The frame can be moved and resized before you start.
- While recording, a frame shows what is in the video and everything else is dimmed. The frame and
  the dimming are not in the video. Pauses are cut out of the result.
- Draw on the screen while recording (`⌥⇧A`): arrows, text, boxes, ellipses, pen, highlighter,
  numbered steps. The marks are part of the video and fade out after a few seconds unless pinned.
- Webcam in a round bubble (`⌥⇧C`): drag it anywhere, scroll to resize.

### Screenshots and the screenshot editor

- `⌥⇧4` area, `⌥⇧5` window, or all displays stitched into one image.
- A new screenshot is on the clipboard right away, ready for `⌘V` in a chat or a ticket, and the
  editor opens in about half a second. Settings → Screenshots turns the copying off.
- **Scrolling screenshot**: pick an area; the app scrolls it and glues one long image.
  Sticky headers and footers appear once.
- Editor: arrow, arrow with text, rectangle, ellipse, line, highlighter, pen, text, numbered steps,
  pixelate blur, magnifier, crop. `+` and `-` change line thickness and text size. The button next to the text size
  switches text between a colored label and outlined letters on a transparent background.
- Combine several screenshots side by side, environment badge, layers, undo and redo.
- Copy (`⌘C`), save to a folder, or drag the result straight into Jira or Slack.

### Bug reports

**Copy bug report** puts a ready report on the clipboard in Markdown or Jira wiki:

- numbered steps built from your clicks and keys (`Click "Submit" button in Safari`, `Press ⌘ Enter`),
  a step for every page you open, and what you typed if you turn that on;
- Expected / Actual placeholders;
- the environment: macOS, display, app and version, browser URL, locale, time; turn fields off or
  rename them in **Settings → Bug reports**;
- your own fields (stand, build, test account…).

No AI, nothing leaves the Mac. Element names need Accessibility access; password fields are never read.

### Recent captures

<p align="center">
  <img src="docs/images/history.png" width="720" alt="Recent captures">
</p>

Search by app or URL, filter screenshots and videos. With **Select** you can:

- make a numbered step guide from screenshots (PNG or PDF);
- compare two screenshots (side by side, slider, changes boxed) or two clips (synced playback).

**Settings → Storage** deletes old captures automatically or keeps them under a size.

### Disk space

The **Space** tab shows how full the disk is and what can be cleaned safely; **Disk Space** opens the
full window.

- **Clean up**: app caches, Xcode DerivedData and device support, simulator caches, npm / Yarn / pnpm,
  Gradle, Homebrew, CocoaPods, pip, uv, Bun, Go, Maven, Hugging Face, pre-commit, Cursor / VS Code and
  Playwright caches, logs. Review… lists what is inside with a checkbox each; tick what goes and confirm.
  Apps and tools make caches again when they need them. Apple's own caches are left alone.
- **Project folders**: Find projects looks for node_modules, Python environments, Pods and build folders in
  your projects; the ones not touched for 30 days are ticked and go to the Trash. Set the folders and the
  days in Settings → Storage.
- **Folders**: scan the home folder and walk down the biggest folders, with a bar for each.
- **Largest files**: files over 50 MB, biggest first, with Show in Finder and Move to Trash (they stay in
  the Trash until you empty it).

The scan skips what macOS guards with a permission prompt or keeps for itself: other apps' private data,
Apple's folders, the Photos and Music libraries, Contacts, Calendars, Mail, Messages and the Trash. macOS
may ask once for Desktop, Documents and Downloads.

### Check the screen

On the **Record** tab:

- resize the window you test to desktop, tablet or phone sizes;
- measure in points and pixels;
- pick a color from anywhere (hex to the clipboard);
- float a design export over the app, with opacity and click-through.

### Dev toolbox

<p align="center">
  <img src="docs/images/toolbox-json.png" width="820" alt="Dev toolbox: JSON formatter">
</p>

`⌥⇧D` opens it with whatever is on the clipboard and picks the right tool.

| Area | Tools |
|---|---|
| Formats | JSON (keeps key order and number text), XML, YAML, HTML, SQL, GraphQL; JSON ↔ YAML ↔ XML ↔ CSV |
| JSON | Diff (added / removed / changed paths, key order ignored), JSONPath (`$..id`, `$.items[*].price`) |
| Decode | JWT (with `exp` / `iat` as dates), Base64, URL, HTML entities, HTTP request / response parser |
| Time | Unix s / ms / µs / ns, ISO 8601, RFC 2822, ObjectId, UUID v1 / v7, `in 3 days`; cron with next runs |
| Time zones | Search by city, country, `PST` or `+5:30`, day / night strips, "compare at" slider, menu bar clock |
| Test data | People with reserved emails, phone numbers, Luhn-valid cards, IBANs, passwords, tricky inputs |
| Strings | Exact-length strings for field limits, length in characters / UTF-16 / UTF-8 bytes, regex tester |
| Other | Number bases, colors, naming case, data sizes, UUID, hashes, QR codes, WCAG contrast |

<p align="center">
  <img src="docs/images/toolbox-timezones.png" width="49%" alt="Time zones">
  <img src="docs/images/toolbox-testdata.png" width="49%" alt="Test data">
</p>

## Updates

Every update is a release with its own version. Bearcorder checks for a new one every 6 hours; when there
is one, an **Update to 0.6.0** badge appears in the menu bar panel. **Update now** rebuilds the app on
your Mac (1-2 minutes) and restarts it, then "What's new" shows what changed.

- Check by hand or turn checks off in Settings → Updates.
- Only the release notes are read from GitHub; nothing about you or your captures is sent.
- All releases: [GitHub releases page](https://github.com/MikeKiselyov/bearcorder/releases).

## Permissions

| Permission | Needed for | When it is asked |
|---|---|---|
| Screen & System Audio Recording | buffer, recordings, screenshots | first start; relaunch the app after allowing |
| Accessibility | keys in videos, element names in reports, window resize, scrolling screenshot (optional) | Settings → Permissions → Allow… |
| Microphone | voice in recordings (optional) | when you turn the mic on |
| Camera | webcam bubble (optional) | when you turn the camera on |
| Automation, per browser | browser URL in the environment (optional) | the first screenshot in that browser; Settings → Permissions shows it |

## More

- [Uninstall](docs/uninstall.md) with one command, and where Bearcorder keeps captures and logs
- Something went wrong? Attach `~/Library/Logs/Bearcorder/Bearcorder.log` to an
  [issue](https://github.com/MikeKiselyov/bearcorder/issues).
- For developers: [build from source](docs/development.md), [tests](docs/testing.md),
  [contributing and releases](CONTRIBUTING.md)

## Support

Bearcorder is free and open source. If it saves you time, you can buy me a coffee:

<a href="https://buymeacoffee.com/mike_kiselyov"><img src="https://img.shields.io/badge/Buy%20me%20a%20coffee-FFDD00?style=for-the-badge&logo=buymeacoffee&logoColor=black" alt="Buy me a coffee"></a>

## License

MIT, see [LICENSE](LICENSE).
