import Foundation
import simd

struct HoldCandidate {
    let centroid: SIMD2<Float>   // normalized [0,1]×[0,1] within source image
    let hue: Float               // [0,1] HSV hue
    let pixelCount: Int
}

struct RouteDescriptor {
    let centroidDistances: [Float]           // sorted pairwise distances, normalized
    let dominantHue: Float
    let normalizedCentroids: [SIMD2<Float>]  // for UI hold overlay
}

struct FingerprintRecord {
    let routeId: UUID
    let descriptor: [Float]
    let dominantHue: Float
}

extension RouteFingerprint {
    var record: FingerprintRecord {
        FingerprintRecord(routeId: routeId, descriptor: descriptor, dominantHue: dominantHue)
    }
}

enum DetectionError: Error {
    case assetNotFound
    case couldNotLoadAsset
    case renderFailed
    case noHoldsDetected
}
