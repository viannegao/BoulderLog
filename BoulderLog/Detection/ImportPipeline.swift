import SwiftData
import CoreImage

struct ImportPipeline {
    enum Result {
        case matched(route: Route, confidence: Float, descriptor: RouteDescriptor)
        case newRoute(descriptor: RouteDescriptor)
        case noHoldsDetected
        case duplicate(existingAttempt: Attempt)
    }

    static func analyze(assetIdentifier: String, context: ModelContext) async throws -> Result {
        // Duplicate check
        let existingAttempts = try context.fetch(FetchDescriptor<Attempt>())
        if let dup = existingAttempts.first(where: { $0.assetIdentifier == assetIdentifier }) {
            return .duplicate(existingAttempt: dup)
        }

        // Extract frames
        let frames = try await FrameExtractor.extractFrames(fromAssetIdentifier: assetIdentifier)

        // Segment holds from each frame, pick the frame with most candidates
        var bestCandidates: [HoldCandidate] = []
        var bestHue: Float = 0
        for frame in frames {
            let (candidates, hue) = try HoldSegmenter.detectHolds(in: frame)
            if candidates.count > bestCandidates.count {
                bestCandidates = candidates
                bestHue = hue
            }
        }

        guard !bestCandidates.isEmpty else { return .noHoldsDetected }

        // Generate fingerprint descriptor
        let descriptor = FingerprintGenerator.generate(from: bestCandidates, dominantHue: bestHue)

        // Match against stored fingerprints
        let storedFingerprints = try context.fetch(FetchDescriptor<RouteFingerprint>())
        let records = storedFingerprints.map { $0.record }
        guard let match = RouteMatcher.match(
            descriptor: descriptor.centroidDistances,
            hue: descriptor.dominantHue,
            against: records)
        else {
            return .newRoute(descriptor: descriptor)
        }

        // Resolve Route from matched routeId
        let routes = try context.fetch(FetchDescriptor<Route>())
        guard let route = routes.first(where: { $0.id == match.routeId }) else {
            return .newRoute(descriptor: descriptor)
        }

        return .matched(route: route, confidence: match.confidence, descriptor: descriptor)
    }

    /// Called after user confirms the import on the confirmation screen.
    static func save(assetIdentifier: String, to route: Route,
                     isSend: Bool, notes: String,
                     descriptor: RouteDescriptor, context: ModelContext) throws {
        // Save attempt
        let attempt = Attempt(assetIdentifier: assetIdentifier, route: route,
                              isSend: isSend, notes: notes)
        context.insert(attempt)
        route.lastAttemptAt = attempt.date
        if isSend { route.isSent = true }

        // Create fingerprint if not already stored for this route
        let fingerprints = try context.fetch(FetchDescriptor<RouteFingerprint>())
        if fingerprints.first(where: { $0.routeId == route.id }) == nil {
            let fp = RouteFingerprint(routeId: route.id,
                                     descriptor: descriptor.centroidDistances,
                                     dominantHue: descriptor.dominantHue)
            context.insert(fp)
        }

        try context.save()
    }

    /// Called when user assigns the video to a brand-new route.
    static func saveAsNewRoute(assetIdentifier: String, descriptor: RouteDescriptor,
                               isSend: Bool, notes: String, context: ModelContext) throws {
        let hexColor = hueToHex(descriptor.dominantHue)
        let route = Route(dominantColor: hexColor)
        context.insert(route)

        let attempt = Attempt(assetIdentifier: assetIdentifier, route: route,
                              isSend: isSend, notes: notes)
        context.insert(attempt)
        route.lastAttemptAt = attempt.date
        if isSend { route.isSent = true }

        let fp = RouteFingerprint(routeId: route.id,
                                  descriptor: descriptor.centroidDistances,
                                  dominantHue: descriptor.dominantHue)
        context.insert(fp)

        try context.save()
    }
}

private func hueToHex(_ hue: Float) -> String {
    // Convert HSV hue (full saturation/value) to hex for display
    let h = Double(hue) * 360
    let c = 1.0, x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
    var r = 0.0, g = 0.0, b = 0.0
    switch h {
    case 0..<60:    r = c; g = x
    case 60..<120:  r = x; g = c
    case 120..<180: g = c; b = x
    case 180..<240: g = x; b = c
    case 240..<300: r = x; b = c
    default:        r = c; b = x
    }
    return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
}
