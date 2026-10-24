import AppKit
import Vision

/// On-device text recognition (Vision). Nothing leaves the Mac.
enum TextRecognizer {
    struct Line {
        var text: String
        /// Normalized box in image space, origin bottom-left (Vision coordinates).
        var box: CGRect
    }

    static func recognize(_ image: CGImage) async throws -> [Line] {
        let task = Task.detached(priority: .userInitiated) { () throws -> [Line] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US", "ru-RU"]
            // Correction "fixes" IDs, tokens and error codes into words; keep the raw text.
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
            var lines: [Line] = []
            for observation in request.results ?? [] {
                guard let candidate = observation.topCandidates(1).first else { continue }
                lines.append(Line(text: candidate.string, box: observation.boundingBox))
            }
            return lines
        }
        return try await task.value
    }

    /// Lines top to bottom, left to right, joined with newlines.
    static func text(of lines: [Line]) -> String {
        let sorted = lines.sorted { first, second in
            let sameRow = abs(first.box.midY - second.box.midY) < min(first.box.height, second.box.height) / 2
            if sameRow {
                return first.box.minX < second.box.minX
            }
            return first.box.midY > second.box.midY
        }
        var texts: [String] = []
        for line in sorted {
            texts.append(line.text)
        }
        return texts.joined(separator: "\n")
    }
}
