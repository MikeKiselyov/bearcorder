import AVFoundation

/// Captures the default microphone and hands host-time stamped buffers to a sink.
final class MicrophoneSource: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "bugbear.microphone")
    private var configured = false
    var onSample: ((CMSampleBuffer) -> Void)?

    static var authorization: AVAuthorizationStatus {
        return AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static func requestAccess() async -> Bool {
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    func start() async -> Bool {
        if MicrophoneSource.authorization == .notDetermined {
            _ = await MicrophoneSource.requestAccess()
        }
        guard MicrophoneSource.authorization == .authorized else { return false }
        if !configured {
            guard let device = AVCaptureDevice.default(for: .audio), let input = try? AVCaptureDeviceInput(device: device) else { return false }
            session.beginConfiguration()
            if session.canAddInput(input) {
                session.addInput(input)
            }
            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            session.commitConfiguration()
            configured = true
        }
        if !session.isRunning {
            queue.async {
                self.session.startRunning()
            }
        }
        return true
    }

    func stop() {
        if session.isRunning {
            queue.async {
                self.session.stopRunning()
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onSample?(sampleBuffer)
    }
}
