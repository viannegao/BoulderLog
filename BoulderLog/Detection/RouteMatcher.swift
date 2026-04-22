import Foundation

struct RouteMatcher {
    static let matchThreshold: Float = 0.25
    static let hueGate: Float = 0.10

    struct MatchResult {
        let routeId: UUID
        let confidence: Float  // 0–1, higher is better
    }

    static func match(descriptor: [Float], hue: Float,
                      against fingerprints: [FingerprintRecord]) -> MatchResult? {
        var bestDistance: Float = .infinity
        var bestId: UUID?

        for fp in fingerprints {
            // Hue gate: skip if dominant hues differ (with wraparound for red at 0/1)
            let diff = abs(fp.dominantHue - hue)
            let wrappedDiff = min(diff, 1 - diff)
            guard wrappedDiff < hueGate else { continue }

            let dist = l2Distance(descriptor, fp.descriptor)
            if dist < bestDistance {
                bestDistance = dist
                bestId = fp.routeId
            }
        }

        guard let id = bestId, bestDistance < matchThreshold else { return nil }
        let confidence = 1.0 - (bestDistance / matchThreshold)
        return MatchResult(routeId: id, confidence: confidence)
    }

    // Normalised L2 distance, padding shorter array with 0.0
    private static func l2Distance(_ a: [Float], _ b: [Float]) -> Float {
        let len = max(a.count, b.count)
        guard len > 0 else { return 0 }
        let paddedA = a + [Float](repeating: 0.0, count: len - a.count)
        let paddedB = b + [Float](repeating: 0.0, count: len - b.count)
        let sumSq = zip(paddedA, paddedB).reduce(Float(0)) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
        return sqrt(sumSq / Float(len))
    }
}
