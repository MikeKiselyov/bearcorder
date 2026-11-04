import CoreGraphics

/// The screenshot editor lets marks go past the picture's edges into a margin around it;
/// a save grows the picture to hold them. Coordinates are image pixels, origin top-left.
public enum PictureArea {
    /// The picture with room around it to draw: a quarter of its shorter side, at least 200 px.
    public static func editing(imageSize: CGSize) -> CGRect {
        let margin = max(200, (min(imageSize.width, imageSize.height) / 4).rounded())
        return CGRect(origin: .zero, size: imageSize).insetBy(dx: -margin, dy: -margin)
    }

    /// What a save without a crop keeps: the picture grown to the marks, never past the margin.
    /// A side that would grow by less than `slack` stays: a mark that only overshoots the edge a
    /// little is cut off there, as it always was.
    public static func grown(imageSize: CGSize, marks: [CGRect], slack: CGFloat) -> CGRect {
        let picture = CGRect(origin: .zero, size: imageSize)
        var area = picture
        for mark in marks {
            area = area.union(mark.integral)
        }
        area = area.intersection(editing(imageSize: imageSize))
        var minX = area.minX
        var minY = area.minY
        var maxX = area.maxX
        var maxY = area.maxY
        if picture.minX - minX < slack {
            minX = picture.minX
        }
        if picture.minY - minY < slack {
            minY = picture.minY
        }
        if maxX - picture.maxX < slack {
            maxX = picture.maxX
        }
        if maxY - picture.maxY < slack {
            maxY = picture.maxY
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
