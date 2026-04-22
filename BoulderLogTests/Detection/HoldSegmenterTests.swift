import XCTest
import CoreImage
@testable import BoulderLog

final class HoldSegmenterTests: XCTestCase {

    private func makeImage(r: UInt8, g: UInt8, b: UInt8,
                           width: Int = 160, height: Int = 120) -> CIImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            pixels[i*4] = r; pixels[i*4+1] = g
            pixels[i*4+2] = b; pixels[i*4+3] = 255
        }
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        let cg = CGImage(width: width, height: height,
                         bitsPerComponent: 8, bitsPerPixel: 32,
                         bytesPerRow: width * 4,
                         space: CGColorSpaceCreateDeviceRGB(),
                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                         provider: provider,
                         decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return CIImage(cgImage: cg)
    }

    func test_solidBlueImage_detectsOneBlob() throws {
        let image = makeImage(r: 0, g: 0, b: 255)
        let (candidates, hue) = try HoldSegmenter.detectHolds(in: image)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertGreaterThan(hue, 0.55)
        XCTAssertLessThan(hue, 0.7)
    }

    func test_greyImage_detectsNoBlobs() throws {
        let image = makeImage(r: 128, g: 128, b: 128)
        let (candidates, _) = try HoldSegmenter.detectHolds(in: image)
        XCTAssertEqual(candidates.count, 0)
    }

    func test_centroidOfSingleBlob_isApproximatelyCenter() throws {
        let image = makeImage(r: 0, g: 0, b: 255, width: 160, height: 120)
        let (candidates, _) = try HoldSegmenter.detectHolds(in: image)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].centroid.x, 0.5, accuracy: 0.1)
        XCTAssertEqual(candidates[0].centroid.y, 0.5, accuracy: 0.1)
    }
}
