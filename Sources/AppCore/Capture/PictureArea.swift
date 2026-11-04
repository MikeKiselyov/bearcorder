import CoreGraphics

/// The screenshot editor lets marks go past the picture's edges into a margin around it;
/// a save grows the picture to hold them. Coordinates are image pixels, origin top-left.
public enum PictureArea {
    /// The picture with room around it to draw: a quarter of its shorter side, at least 200 px.
    public static func editing(imageSize: CGSize) -> CGRect {
        let margin = max(200, (min(imageSize.width, imageSize.height) / 4).rounded())
        return CGRect(origin: .zero, size: imageSize).insetBy(dx: -margin, dy: -margin)
    }

    /// A drawn mark and how far it may pass the picture's edge before the picture grows for it.
    public struct Mark {
        public var rect: CGRect
        public var slack: CGFloat

        public init(rect: CGRect, slack: CGFloat) {
            self.rect = rect
            self.slack = slack
        }
    }

    /// What a save without a crop keeps: the picture grown to the marks, never past the margin.
    /// A mark that passes an edge by less than its slack (an arrow drawn to the edge, a box dragged a
    /// little past it) is cut off at that edge, as it always was.
    public static func grown(imageSize: CGSize, marks: [Mark]) -> CGRect {
        let picture = CGRect(origin: .zero, size: imageSize)
        var area = picture
        for mark in marks {
            let rect = mark.rect.integral
            var minX = rect.minX
            var minY = rect.minY
            var maxX = rect.maxX
            var maxY = rect.maxY
            if picture.minX - minX < mark.slack {
                minX = max(minX, picture.minX)
            }
            if picture.minY - minY < mark.slack {
                minY = max(minY, picture.minY)
            }
            if maxX - picture.maxX < mark.slack {
                maxX = min(maxX, picture.maxX)
            }
            if maxY - picture.maxY < mark.slack {
                maxY = min(maxY, picture.maxY)
            }
            if maxX > minX && maxY > minY {
                area = area.union(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
            }
        }
        return area.intersection(editing(imageSize: imageSize))
    }
}
