import XCTest
import simd
@testable import BoulderLog

final class FingerprintGeneratorTests: XCTestCase {

    func test_emptyCandidates_returnsEmptyDescriptor() {
        let desc = FingerprintGenerator.generate(from: [], dominantHue: 0.6)
        XCTAssertTrue(desc.centroidDistances.isEmpty)
        XCTAssertTrue(desc.normalizedCentroids.isEmpty)
    }

    func test_singleCandidate_returnsEmptyDistances() {
        let c = HoldCandidate(centroid: SIMD2<Float>(0.5, 0.5), hue: 0.6, pixelCount: 100)
        let desc = FingerprintGenerator.generate(from: [c], dominantHue: 0.6)
        XCTAssertTrue(desc.centroidDistances.isEmpty)
        XCTAssertEqual(desc.normalizedCentroids.count, 1)
    }

    func test_twoCandidates_returnsOneDistance() {
        let a = HoldCandidate(centroid: SIMD2<Float>(0.0, 0.0), hue: 0.6, pixelCount: 50)
        let b = HoldCandidate(centroid: SIMD2<Float>(1.0, 1.0), hue: 0.6, pixelCount: 50)
        let desc = FingerprintGenerator.generate(from: [a, b], dominantHue: 0.6)
        XCTAssertEqual(desc.centroidDistances.count, 1)
        XCTAssertEqual(desc.centroidDistances[0], sqrt(2.0), accuracy: 0.01)
    }

    func test_descriptorIsSorted() {
        let candidates = [
            HoldCandidate(centroid: SIMD2<Float>(0.0, 0.0), hue: 0.3, pixelCount: 30),
            HoldCandidate(centroid: SIMD2<Float>(0.5, 0.0), hue: 0.3, pixelCount: 30),
            HoldCandidate(centroid: SIMD2<Float>(1.0, 1.0), hue: 0.3, pixelCount: 30),
        ]
        let desc = FingerprintGenerator.generate(from: candidates, dominantHue: 0.3)
        let sorted = desc.centroidDistances.sorted()
        XCTAssertEqual(desc.centroidDistances, sorted)
    }
}
