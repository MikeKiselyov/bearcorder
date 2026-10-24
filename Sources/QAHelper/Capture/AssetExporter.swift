import AVFoundation
import QAHelperCore

/// Renders an asset (with an optional video composition) to H.264 + AAC MP4.
/// Unlike AVAssetExportSession it mixes every audio track (system + microphone) into one,
/// so the result plays everywhere with both sources audible.
enum AssetExporter {
    struct Options {
        var renderSize: CGSize
        var framesPerSecond: Int = 30
        var timeRange: CMTimeRange?
        /// Fixed video bitrate (bits/s) for a size limit; nil picks one from the frame size.
        var videoBitrate: Int?
    }

    static func export(asset: AVAsset, videoComposition: AVVideoComposition?, options: Options, to url: URL, progress: ((Double) -> Void)? = nil) async throws {
        try? FileManager.default.removeItem(at: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !videoTracks.isEmpty else {
            throw BufferError.exportFailed("No video in the clip")
        }
        let duration = try await asset.load(.duration)

        let reader = try AVAssetReader(asset: asset)
        if let range = options.timeRange {
            reader.timeRange = range
        }
        let pixelSettings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: pixelSettings)
        if let composition = videoComposition {
            videoOutput.videoComposition = composition
        } else {
            let plain = AVMutableVideoComposition()
            plain.renderSize = options.renderSize
            plain.frameDuration = CMTime(value: 1, timescale: CMTimeScale(options.framesPerSecond))
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
            var layers: [AVMutableVideoCompositionLayerInstruction] = []
            for track in videoTracks {
                layers.append(AVMutableVideoCompositionLayerInstruction(assetTrack: track))
            }
            instruction.layerInstructions = layers
            plain.instructions = [instruction]
            videoOutput.videoComposition = plain
        }
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            throw BufferError.exportFailed("Cannot read video")
        }
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderAudioMixOutput? = nil
        if !audioTracks.isEmpty {
            let pcmSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
            let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: pcmSettings)
            if reader.canAdd(output) {
                reader.add(output)
                audioOutput = output
            }
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let width = Int(options.renderSize.width / 2) * 2
        let height = Int(options.renderSize.height / 2) * 2
        var bitrate = min(25_000_000, max(3_000_000, Double(width * height * options.framesPerSecond) * 0.15))
        if let fixed = options.videoBitrate {
            bitrate = Double(fixed)
        }
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            // Frames larger than the output (quality presets) are scaled down to fit.
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(bitrate),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: options.framesPerSecond,
            ],
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput? = nil
        if audioOutput != nil {
            let aacSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: SizeBudget.audioBitrate,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: aacSettings)
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        guard reader.startReading() else {
            throw BufferError.exportFailed(reader.error?.localizedDescription ?? "reader failed")
        }
        guard writer.startWriting() else {
            throw BufferError.exportFailed(writer.error?.localizedDescription ?? "writer failed")
        }
        let start = options.timeRange?.start ?? .zero
        writer.startSession(atSourceTime: start)
        let total = (options.timeRange?.duration ?? duration).seconds

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            let videoQueue = DispatchQueue(label: "qahelper.export.video")
            let audioQueue = DispatchQueue(label: "qahelper.export.audio")

            group.enter()
            var videoDone = false
            videoInput.requestMediaDataWhenReady(on: videoQueue) {
                while videoInput.isReadyForMoreMediaData && !videoDone {
                    if let sample = videoOutput.copyNextSampleBuffer() {
                        let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds - start.seconds
                        if total > 0 {
                            progress?(min(1, time / total))
                        }
                        if !videoInput.append(sample) {
                            videoDone = true
                            videoInput.markAsFinished()
                            group.leave()
                        }
                    } else {
                        videoDone = true
                        videoInput.markAsFinished()
                        group.leave()
                    }
                }
            }

            if let input = audioInput, let output = audioOutput {
                group.enter()
                var audioDone = false
                input.requestMediaDataWhenReady(on: audioQueue) {
                    while input.isReadyForMoreMediaData && !audioDone {
                        if let sample = output.copyNextSampleBuffer() {
                            if !input.append(sample) {
                                audioDone = true
                                input.markAsFinished()
                                group.leave()
                            }
                        } else {
                            audioDone = true
                            input.markAsFinished()
                            group.leave()
                        }
                    }
                }
            }

            group.notify(queue: .global()) {
                continuation.resume()
            }
        }

        if reader.status == .failed {
            writer.cancelWriting()
            throw BufferError.exportFailed(reader.error?.localizedDescription ?? "reading failed")
        }
        // Cut the file at the requested length; otherwise a long last frame (static screen)
        // stretches the duration.
        if total > 0 {
            writer.endSession(atSourceTime: CMTimeAdd(start, CMTime(seconds: total, preferredTimescale: 600)))
        }
        await writer.finishWriting()
        if writer.status != .completed {
            throw BufferError.exportFailed(writer.error?.localizedDescription ?? "writing failed")
        }
        progress?(1)
    }
}
