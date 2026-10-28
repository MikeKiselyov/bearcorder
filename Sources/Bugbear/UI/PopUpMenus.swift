import AppKit

/// SwiftUI pickers in menu style and `Menu`s are pop-up buttons underneath. Tests choose their
/// items here without opening the menu: an open menu would hold the app until it closes.
@MainActor
enum PopUpMenus {
    /// Every pop-up button inside the view.
    static func all(in view: NSView) -> [NSPopUpButton] {
        var found: [NSPopUpButton] = []
        var stack: [NSView] = [view]
        while let current = stack.popLast() {
            if let button = current as? NSPopUpButton {
                found.append(button)
            }
            for child in current.subviews {
                stack.append(child)
            }
        }
        return found
    }

    /// The pop-up button under a point of the window, in top-left screen points (what
    /// accessibility reports for a control).
    static func button(at point: CGPoint, in window: NSWindow) -> NSPopUpButton? {
        guard let content = window.contentView else { return nil }
        let screenHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let bottomLeft = CGPoint(x: point.x, y: screenHeight - point.y)
        for button in all(in: content) where !button.isHiddenOrHasHiddenAncestor {
            let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
            if frame.contains(bottomLeft) {
                return button
            }
        }
        return nil
    }

    /// The item titles, as the menu shows them when it opens.
    static func items(of button: NSPopUpButton) -> [String] {
        guard let menu = fill(button) else { return [] }
        var titles: [String] = []
        for (index, item) in menu.items.enumerated() {
            // A pull-down menu's first item is its own title, not a choice.
            if button.pullsDown && index == 0 { continue }
            if item.isSeparatorItem || item.isHidden || item.title.isEmpty { continue }
            titles.append(item.title)
        }
        return titles
    }

    /// The menu with its items. A SwiftUI `Menu` adds them only when it is about to show, when its
    /// pop-up cell tells the menu's delegate; a picker has them from the start.
    private static func fill(_ button: NSPopUpButton) -> NSMenu? {
        guard let menu = button.menu else { return nil }
        let willShow = NSSelectorFromString("popUpButtonCell:willShowMenu:")
        if let delegate = menu.delegate as? NSObject, delegate.responds(to: willShow), let cell = button.cell {
            delegate.perform(willShow, with: cell, with: menu)
        }
        menu.update()
        return menu
    }

    /// Picks the item with this title, like a click on it in the open menu.
    static func choose(_ title: String, in button: NSPopUpButton) -> Bool {
        guard let menu = fill(button) else { return false }
        for (index, item) in menu.items.enumerated() where item.title == title && !item.isSeparatorItem {
            if button.pullsDown && index == 0 { continue }
            if !item.isEnabled { return false }
            if !button.pullsDown {
                button.selectItem(at: index)
            }
            menu.performActionForItem(at: index)
            return true
        }
        return false
    }
}
