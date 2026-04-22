import AVFoundation
import CoreImage
import Photos

struct FrameExtractor {
    static func extractFrames(fromAssetIdentifier identifier: String, count: Int = 5) async throws -> [CIImage] {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let phAsset = fetchResult.firstObject else {
            throw DetectionError.assetNotFound
        }
        let avAsset = try await loadAVAsset(from: phAsset)
        return try await extractFrames(from: avAsset, count: count)
    }

    static func extractFrames(from avAsset: AVAsset, count: Int = 5) async throws -> [CIImage] {
        let duration = try await avAsset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds > 0 else { return [] }

        let generator = AVAssetImageGenerator(asset: avAsset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 480)

        let times: [CMTime] = (0..<count).map { i in
            CMTime(seconds: seconds * Double(i) / Double(max(count - 1, 1)),
                   preferredTimescale: 600)
        }

        var frames: [CIImage] = []
        for time in times {
            let (cgImage, _) = try await generator.image(at: time)
            frames.append(CIImage(cgImage: cgImage))
        }
        return frames
    }

    private static func loadAVAsset(from phAsset: PHAsset) async throws -> AVAsset {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true   // allow iCloud download if video isn't on device
            options.deliveryMode = .highQualityFormat
            var resumed = false
            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { asset, _, info in
                guard !resumed else { return }
                resumed = true
                if let asset {
                    continuation.resume(returning: asset)
                } else {
                    let err = (info?[PHImageErrorKey] as? Error) ?? DetectionError.couldNotLoadAsset
                    continuation.resume(throwing: err)
                }
            }
        }
    }
}
