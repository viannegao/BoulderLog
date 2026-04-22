import XCTest
@testable import BoulderLog

final class RouteMatcherTests: XCTestCase {

    func test_emptyFingerprints_returnsNil() {
        let result = RouteMatcher.match(
            descriptor: [0.1, 0.2, 0.3], hue: 0.6, against: [])
        XCTAssertNil(result)
    }

    func test_identicalDescriptor_returnsHighConfidence() {
        let desc: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        let fp = FingerprintRecord(routeId: UUID(), descriptor: desc, dominantHue: 0.6)
        let result = RouteMatcher.match(descriptor: desc, hue: 0.6, against: [fp])
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.confidence, 0.9)
        XCTAssertEqual(result!.routeId, fp.routeId)
    }

    func test_differentHue_skipsFingerprint() {
        let desc: [Float] = [0.1, 0.2, 0.3]
        let fp = FingerprintRecord(routeId: UUID(), descriptor: desc, dominantHue: 0.0) // red
        // Query hue is blue (0.6) — more than 0.1 apart → should be skipped
        let result = RouteMatcher.match(descriptor: desc, hue: 0.6, against: [fp])
        XCTAssertNil(result)
    }

    func test_veryDifferentDescriptor_returnsNil() {
        let stored: [Float] = [0.1, 0.1, 0.1, 0.1]
        let query:  [Float] = [0.9, 0.9, 0.9, 0.9]
        let fp = FingerprintRecord(routeId: UUID(), descriptor: stored, dominantHue: 0.6)
        let result = RouteMatcher.match(descriptor: query, hue: 0.6, against: [fp])
        XCTAssertNil(result)
    }

    func test_returnsClosestMatch_whenMultipleFingerprints() {
        let query: [Float]   = [0.1, 0.2, 0.3]
        let closeId = UUID()
        let farId   = UUID()
        let fingerprints = [
            FingerprintRecord(routeId: closeId, descriptor: [0.1, 0.2, 0.31], dominantHue: 0.6),
            FingerprintRecord(routeId: farId,   descriptor: [0.5, 0.6, 0.70], dominantHue: 0.6),
        ]
        let result = RouteMatcher.match(descriptor: query, hue: 0.6, against: fingerprints)
        XCTAssertEqual(result?.routeId, closeId)
    }
}
