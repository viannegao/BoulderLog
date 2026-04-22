import Foundation
import simd

struct FingerprintGenerator {
    static func generate(from candidates: [HoldCandidate], dominantHue: Float) -> RouteDescriptor {
        guard candidates.count >= 2 else {
            return RouteDescriptor(
                centroidDistances: [],
                dominantHue: dominantHue,
                normalizedCentroids: candidates.map { $0.centroid }
            )
        }

        // Normalize centroids to [0,1]×[0,1] bounding box
        let xs = candidates.map { $0.centroid.x }
        let ys = candidates.map { $0.centroid.y }
        let minX = xs.min()!, maxX = xs.max()!
        let minY = ys.min()!, maxY = ys.max()!
        let rangeX = maxX > minX ? maxX - minX : 1.0
        let rangeY = maxY > minY ? maxY - minY : 1.0

        let normalized: [SIMD2<Float>] = candidates.map { c in
            SIMD2<Float>((c.centroid.x - minX) / rangeX,
                         (c.centroid.y - minY) / rangeY)
        }

        // Sorted pairwise distances
        var distances: [Float] = []
        for i in 0..<normalized.count {
            for j in (i+1)..<normalized.count {
                distances.append(simd_distance(normalized[i], normalized[j]))
            }
        }
        distances.sort()

        return RouteDescriptor(centroidDistances: distances,
                               dominantHue: dominantHue,
                               normalizedCentroids: normalized)
    }
}
