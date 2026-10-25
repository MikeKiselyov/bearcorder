/// Release notes for people, newest first. Every change that reaches main is a new release:
/// add an entry on top with the next id and a higher version. The app's version comes from the
/// top entry, the update badge compares it with GitHub, and CI refuses a pull request without one.
public enum WhatsNewCatalog {
    public static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(id: 13, version: "0.8.1", title: "Clear clean-up", items: [
            WhatsNewRelease.Item(symbol: "trash", title: "You see what goes", text: "After Clean the question gets its own line: what is deleted, how much, and full Cancel and Delete buttons instead of squeezed ones.", shortcut: "Space tab"),
        ]),
        WhatsNewRelease(id: 12, version: "0.8.0", title: "Pick the quality, see the size", items: [
            WhatsNewRelease.Item(symbol: "photo", title: "Screenshot quality", text: "Save as PNG, PNG at half size, or JPEG in high, medium or small quality. Each choice shows how big the file comes out.", shortcut: "Screenshot editor"),
            WhatsNewRelease.Item(symbol: "film", title: "Video quality with sizes", text: "Original, 1080p, 720p or the new 480p, each with the expected file size for this clip.", shortcut: "Video editor"),
        ]),
        WhatsNewRelease(id: 11, version: "0.7.0", title: "Friendlier editors", items: [
            WhatsNewRelease.Item(symbol: "paintpalette", title: "Any color, the last four kept", text: "Pick any color next to the palette. The last four picked colors stay there, one click away.", shortcut: "Editors"),
            WhatsNewRelease.Item(symbol: "square.dashed", title: "Transparent or filled", text: "Text with or without a label, rectangles and ellipses as outlines or with a see-through fill. Line and text sizes have − and + buttons.", shortcut: "Screenshot editor"),
            WhatsNewRelease.Item(symbol: "crop", title: "Crop by the edges", text: "Drag the edges and corners to shrink the screenshot, drag inside to move the area. The size shows while you drag.", shortcut: "C"),
            WhatsNewRelease.Item(symbol: "delete.left", title: "Delete works everywhere", text: "Delete removes the selected mark wherever you clicked last in the editor. Undo and redo moved to the left of the toolbar.", shortcut: "Delete"),
            WhatsNewRelease.Item(symbol: "stop.circle", title: "Stopped from the macOS menu", text: "Stop in the purple screen recording icon saves what the buffer holds and offers to open it in the editor.", shortcut: "Menu bar"),
            WhatsNewRelease.Item(symbol: "folder", title: "Your folder, and tooltips", text: "Files go to Desktop/Bugbear unless you pick another folder in the guide or Settings. Every button explains itself when you hover over it.", shortcut: "Welcome guide"),
        ]),
        WhatsNewRelease(id: 10, version: "0.6.0", title: "A new look", items: [
            WhatsNewRelease.Item(symbol: "magnifyingglass", title: "The bear goes bug hunting", text: "A new logo: the bear looks at a bug through a magnifying glass. In the menu bar, the app icon and the installer.", shortcut: "Menu bar"),
        ]),
        WhatsNewRelease(id: 9, version: "0.5.4", title: "Windows fit the screen", items: [
            WhatsNewRelease.Item(symbol: "macwindow", title: "Continue stays in reach", text: "The welcome guide and other windows keep their size and open inside the screen. On tall displays the guide used to stretch past the bottom, out of reach of its Continue button.", shortcut: "Welcome guide"),
        ]),
        WhatsNewRelease(id: 8, version: "0.5.3", title: "Tests leave your Bugbear alone", items: [
            WhatsNewRelease.Item(symbol: "arrow.uturn.backward.circle", title: "Your Bugbear comes back", text: "The test scripts quit the test copy when they finish and start your installed Bugbear again, so a test copy no longer keeps recording in the menu bar.", shortcut: "scripts/e2e.sh"),
        ]),
        WhatsNewRelease(id: 7, version: "0.5.2", title: "Clearer installer", items: [
            WhatsNewRelease.Item(symbol: "wrench.and.screwdriver", title: "Says what to update", text: "On macOS 14.0-14.4 the installer now asks to update macOS first, since Swift 6 needs 14.5.", shortcut: "install.sh"),
        ]),
        WhatsNewRelease(id: 6, version: "0.5.1", title: "Permissions stay after updates without Xcode", items: [
            WhatsNewRelease.Item(symbol: "checkmark.seal", title: "A signature of this Mac's own", text: "Macs without Xcode now sign Bugbear with a certificate made just for them, so macOS no longer asks for Screen Recording again after every update.", shortcut: "Automatic"),
        ]),
        WhatsNewRelease(id: 5, version: "0.5.0", title: "Every update is a version", items: [
            WhatsNewRelease.Item(symbol: "number", title: "Versions you can see", text: "Each update has its own version number. This window shows it next to every release, and Settings shows the one you have.", shortcut: "What's new"),
            WhatsNewRelease.Item(symbol: "arrow.down.circle.fill", title: "Update to a version", text: "The menu badge says which version is waiting, and only a real release counts as an update.", shortcut: "Menu bar panel"),
        ]),
        WhatsNewRelease(id: 4, version: "0.4.0", title: "Text without a label, several displays, disk space", items: [
            WhatsNewRelease.Item(symbol: "character", title: "Text on a transparent background", text: "Write on screenshots and videos with outlined letters instead of a colored label. Pick it next to the text size, or under Background in the video editor.", shortcut: "Editors"),
            WhatsNewRelease.Item(symbol: "rectangle.on.rectangle", title: "Every display, your pick", text: "The buffer keeps all displays. In the editor show one display or both side by side, for clips and screenshots.", shortcut: "Editor toolbar"),
            WhatsNewRelease.Item(symbol: "internaldrive", title: "Disk space", text: "See what takes space, clean caches and build leftovers, find the biggest files and move them to the Trash.", shortcut: "Space tab"),
            WhatsNewRelease.Item(symbol: "doc.on.clipboard", title: "Screenshots go to the clipboard", text: "Every screenshot is copied right away, ready to paste into a ticket or a chat.", shortcut: "⌥⇧4"),
        ]),
        WhatsNewRelease(id: 3, version: "0.3.0", title: "Reports for Jira, checks on screen, more tools", items: [
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
        WhatsNewRelease(id: 2, version: "0.2.0", title: "Sizes in the editors, clear recording area", items: [
            WhatsNewRelease.Item(symbol: "textformat.size", title: "Bigger and bolder marks", text: "Seven line thicknesses and text from 12 to 100 pt in the screenshot editor. + and - resize the selected mark or the current tool.", shortcut: "+  -"),
            WhatsNewRelease.Item(symbol: "plus.magnifyingglass", title: "Resize marks in videos", text: "Select a text, arrow or box in the video editor and press + or - (50% to 400%). New marks keep the last size.", shortcut: "+  -"),
            WhatsNewRelease.Item(symbol: "rectangle.dashed", title: "Pick the recording size", text: "Record an area at 720p, 1080p, 1440×900, 16:9, 4:3, 1:1, phone size or full screen, or drag your own.", shortcut: "Record → Area…"),
            WhatsNewRelease.Item(symbol: "eye", title: "See what is recorded", text: "While recording, a solid frame marks what is in the video, everything else is dimmed and other displays say Not recorded. None of it is in the video.", shortcut: "While recording"),
        ]),
        WhatsNewRelease(id: 1, version: "0.1.0", title: "Catch, explain and share bugs faster", items: [
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
