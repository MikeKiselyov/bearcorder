import QAHelperCore

/// Release notes for people. Add a release with the next id when you ship something worth showing;
/// it appears once on every Mac that updates to a build containing it.
enum WhatsNewCatalog {
    static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(id: 3, title: "Reports for Jira, checks on screen, more tools", items: [
            WhatsNewRelease.Item(symbol: "list.number", title: "Bug report in Jira wiki", text: "Copy bug report now also gives Jira markup: h2 headings, # steps, {{code}}. The last format you pick becomes the default.", shortcut: "Copy bug report ▾"),
            WhatsNewRelease.Item(symbol: "tag", title: "Your fields in every capture", text: "Stand, build, test account, feature flag: set them once and they go into the environment, the badge and the report.", shortcut: "Settings → Bug reports"),
            WhatsNewRelease.Item(symbol: "list.bullet.rectangle.portrait", title: "Step-by-step guide", text: "Select screenshots in All captures and make one numbered guide with captions, as PNG or PDF.", shortcut: "All captures → Select"),
            WhatsNewRelease.Item(symbol: "rectangle.split.2x1", title: "Before and after", text: "Compare two screenshots side by side, with a slider, or with changes boxed in red. Two clips play in sync.", shortcut: "All captures → Select"),
            WhatsNewRelease.Item(symbol: "arrow.down.to.line.compact", title: "Scrolling screenshot", text: "Pick an area: the app scrolls it and glues one long image. Sticky headers and footers appear once.", shortcut: "Capture tab"),
            WhatsNewRelease.Item(symbol: "ruler", title: "Measure, pick colors, check contrast", text: "A ruler in points and pixels, a color picker that copies hex, and a WCAG contrast checker.", shortcut: "Record tab · Toolbox"),
            WhatsNewRelease.Item(symbol: "square.on.square.dashed", title: "Design overlay", text: "Float a Figma export over the real app, set opacity, nudge it with the arrows, click through it.", shortcut: "Record tab"),
            WhatsNewRelease.Item(symbol: "macwindow", title: "Window sizes", text: "Resize the app you test to 1280×720, 1440×900, phone or tablet widths in one click.", shortcut: "Record tab"),
            WhatsNewRelease.Item(symbol: "curlybraces", title: "Five new tools", text: "JSON diff, JSONPath, HTTP request/response parser, cron explainer and exact-length strings for field limits.", shortcut: "Toolbox"),
            WhatsNewRelease.Item(symbol: "keyboard", title: "Your own shortcuts", text: "Change any global shortcut or add new ones, for example for the ruler or the color picker.", shortcut: "Settings → Shortcuts"),
            WhatsNewRelease.Item(symbol: "externaldrive", title: "Automatic clean-up", text: "Delete captures older than 7, 30 or 90 days, or keep them under a size limit.", shortcut: "Settings → Storage"),
        ]),
        WhatsNewRelease(id: 2, title: "Sizes in the editors, clear recording area", items: [
            WhatsNewRelease.Item(symbol: "textformat.size", title: "Bigger and bolder marks", text: "Seven line thicknesses and text from 12 to 100 pt in the screenshot editor. + and - resize the selected mark or the current tool.", shortcut: "+  -"),
            WhatsNewRelease.Item(symbol: "plus.magnifyingglass", title: "Resize marks in videos", text: "Select a text, arrow or box in the video editor and press + or - (50% to 400%). New marks keep the last size.", shortcut: "+  -"),
            WhatsNewRelease.Item(symbol: "rectangle.dashed", title: "Pick the recording size", text: "Record an area at 720p, 1080p, 1440×900, 16:9, 4:3, 1:1, phone size or full screen, or drag your own.", shortcut: "Record → Area…"),
            WhatsNewRelease.Item(symbol: "eye", title: "See what is recorded", text: "While recording, a solid frame marks what is in the video, everything else is dimmed and other displays say Not recorded. None of it is in the video.", shortcut: "While recording"),
        ]),
        WhatsNewRelease(id: 1, title: "Catch, explain and share bugs faster", items: [
            WhatsNewRelease.Item(symbol: "flag.fill", title: "Mark the moment", text: "Saw the bug? Press ⌥⇧M. The next save reaches back to that moment and the editor opens right on it.", shortcut: "⌥⇧M"),
            WhatsNewRelease.Item(symbol: "exclamationmark.triangle.fill", title: "Clips of crashes", text: "When an app you were using crashes, the minute before it is saved to Recent with the crash report. Nothing to press.", shortcut: "Automatic"),
            WhatsNewRelease.Item(symbol: "list.number", title: "Bug report in one click", text: "Copy bug report gives Markdown with steps from your clicks and keys, Expected / Actual, the environment and files.", shortcut: "In the editors"),
            WhatsNewRelease.Item(symbol: "text.viewfinder", title: "Copy text from the screen", text: "Select an area and its text goes to the clipboard: errors, IDs, logs. A QR code in the area copies its link.", shortcut: "⌥⇧O"),
            WhatsNewRelease.Item(symbol: "doc.text.magnifyingglass", title: "System logs with every clip", text: "The recorded app's log for the same seconds is saved next to the clip and listed in the bug report.", shortcut: "Automatic"),
            WhatsNewRelease.Item(symbol: "arrow.down.right.and.arrow.up.left", title: "Exports that fit", text: "Pick a size limit (10, 25, 50 or 100 MB) and the video is encoded to fit the ticket's attachment limit.", shortcut: "Video editor → Export"),
            WhatsNewRelease.Item(symbol: "person.text.rectangle", title: "Test data", text: "People with safe emails and phones, cards that pass Luhn, valid IBANs, passwords by rules and tricky inputs.", shortcut: "Toolbox → Test data"),
            WhatsNewRelease.Item(symbol: "text.magnifyingglass", title: "Regex tester", text: "Live highlighting, named groups, flags and a replace preview.", shortcut: "Toolbox → Regex"),
            WhatsNewRelease.Item(symbol: "qrcode", title: "QR codes", text: "Turn a staging link into a QR code for your phone, or read a code from the screen.", shortcut: "Toolbox → QR"),
            WhatsNewRelease.Item(symbol: "arrow.down.circle.fill", title: "Updates in the app", text: "An Update badge appears in the menu when there is a new version. One click rebuilds and restarts.", shortcut: "Menu bar panel"),
        ]),
    ]
}
