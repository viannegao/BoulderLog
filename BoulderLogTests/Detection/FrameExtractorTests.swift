import XCTest
import AVFoundation
import CoreImage
@testable import BoulderLog

final class FrameExtractorTests: XCTestCase {
    private var createdURLs: [URL] = []

    override func tearDown() {
        for url in createdURLs {
            try? FileManager.default.removeItem(at: url)
        }
        createdURLs = []
        super.tearDown()
    }

    func test_extractFrames_returnsRequestedCount() async throws {
        let asset = try await makeSyntheticVideoAsset(duration: 1.0)
        let frames = try await FrameExtractor.extractFrames(from: asset, count: 5)
        XCTAssertEqual(frames.count, 5)
    }

    func test_extractFrames_returnsNonEmptyImages() async throws {
        let asset = try await makeSyntheticVideoAsset(duration: 2.0)
        let frames = try await FrameExtractor.extractFrames(from: asset, count: 3)
        for frame in frames {
            XCTAssertFalse(frame.extent.isEmpty)
        }
    }

    private func makeSyntheticVideoAsset(duration: Double) async throws -> AVAsset {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        createdURLs.append(url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320,
            AVVideoHeightKey: 240,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 320,
                kCVPixelBufferHeightKey as String: 240,
            ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameCount = Int(duration * 30)
        for i in 0..<frameCount {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(10)) }
            var buffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(nil, 320, 240, kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let buffer, status == kCVReturnSuccess else {
                throw NSError(domain: "FrameExtractorTests", code: Int(status),
                              userInfo: [NSLocalizedDescriptionKey: "CVPixelBufferCreate failed: \(status)"])
            }
            let time = CMTime(value: CMTimeValue(i), timescale: 30)
            adaptor.append(buffer, withPresentationTime: time)
        }
        input.markAsFinished()
        await writer.finishWriting()
        return AVURLAsset(url: url)
    }
}
