import CoreGraphics

/// Keeps the bear in sight. On a Mac with a notch the menu bar has room only beside it, and macOS
/// hides the items that do not fit, the newest (leftmost) first, behind the notch, without a word.
public enum MenuBarPlacement {
    /// The key macOS keeps an item's place under (what ⌘-dragging an icon writes), for SwiftUI's
    /// first menu bar item.
    public static let positionKey = "NSStatusItem Preferred Position Item-0"
    /// Points from the right end of the menu bar: next to the system icons, well clear of the notch.
    public static let visiblePosition: Double = 260

    /// Whether the item cannot be seen. `rightArea` is the menu bar right of the notch (nil without
    /// a notch); `occlusionVisible` is what macOS says about the item's window.
    public static func isHidden(itemFrame: CGRect, rightArea: CGRect?, occlusionVisible: Bool) -> Bool {
        if !occlusionVisible {
            return true
        }
        guard let right = rightArea, right.width > 0 else { return false }
        // Behind the notch or left of it: the item's middle is not in the area right of the notch.
        return itemFrame.midX < right.minX || itemFrame.midX > right.maxX
    }
}
