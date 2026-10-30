import AppKit
import CoreImage
import Vision

/// Makes QR codes (Core Image) and reads them from images (Vision). All on the Mac.
enum QRCode {
    static func image(for text: String, size: CGFloat = 512) -> NSImage? {
        if text.isEmpty { return nil }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        // Scale by whole pixels so modules stay sharp.
        let scale = max(1, (size / output.extent.width).rounded(.down))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: CGSize(width: scaled.extent.width, height: scaled.extent.height))
    }

    /// Payloads of every QR code (and other common barcodes) in the image.
    static func read(_ image: CGImage) async -> [String] {
        let task = Task.detached(priority: .userInitiated) { () -> [String] in
            let request = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return []
            }
            var payloads: [String] = []
            for observation in request.results ?? [] {
                if let payload = observation.payloadStringValue, !payloads.contains(payload) {
                    payloads.append(payload)
                }
            }
            return payloads
        }
        return await task.value
    }

    static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
