# BoulderLog iOS App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an iOS bouldering video documentation app that auto-groups climbing attempt videos by route using on-device color-based hold detection.

**Architecture:** SwiftUI/SwiftData app with a four-unit detection pipeline: FrameExtractor → HoldSegmenter → FingerprintGenerator → RouteMatcher. A thin ImportPipeline orchestrates these units. SwiftUI views bind to @Observable ViewModels that read/write SwiftData models. Videos are never copied — only PHAsset identifiers are stored.

**Tech Stack:** Swift 5.9+, SwiftUI, SwiftData (iOS 17+), CoreImage, AVFoundation, PhotosKit, xcodegen

---

## File Map

```
BoulderLog/
├── BoulderLogApp.swift                   # App entry, ModelContainer setup
├── ContentView.swift                     # Root NavigationStack → LibraryView
├── Models/
│   ├── Route.swift                       # @Model: Route
│   ├── Attempt.swift                     # @Model: Attempt
│   └── RouteFingerprint.swift            # @Model: RouteFingerprint
├── Detection/
│   ├── Types.swift                       # HoldCandidate, RouteDescriptor, FingerprintRecord
│   ├── FrameExtractor.swift              # AVFoundation: PHAsset → [CIImage]
│   ├── HoldSegmenter.swift               # CoreImage pixel analysis → [HoldCandidate]
│   ├── FingerprintGenerator.swift        # [HoldCandidate] → RouteDescriptor
│   ├── RouteMatcher.swift                # RouteDescriptor × [FingerprintRecord] → MatchResult
│   └── ImportPipeline.swift             # Orchestrates detection + SwiftData writes
├── Views/
│   ├── LibraryView.swift                 # Route grid + filter chips
│   ├── RouteDetailView.swift             # Attempt timeline for one route
│   ├── AttemptRowView.swift              # Single attempt row
│   └── ImportFlowView.swift              # PhotosPicker → spinner → confirmation
└── ViewModels/
    ├── LibraryViewModel.swift            # Filter state, route list
    └── ImportViewModel.swift             # Import orchestration, detection state

BoulderLogTests/
├── Detection/
│   ├── HoldSegmenterTests.swift
│   ├── FingerprintGeneratorTests.swift
│   └── RouteMatcherTests.swift
└── Models/
    └── ModelTests.swift
```

---

## Task 1: Project Scaffold

**Files:**
- Create: `project.yml`
- Create: `BoulderLog/BoulderLogApp.swift`
- Create: `BoulderLog/ContentView.swift`
- Create: `.gitignore`

- [ ] **Step 1: Install xcodegen**

```bash
brew install xcodegen
```

Expected: `xcodegen version 2.x.x` on `xcodegen --version`

- [ ] **Step 2: Create project.yml**

```yaml
name: BoulderLog
options:
  bundleIdPrefix: com.boulderlog
  deploymentTarget:
    iOS: "17.0"
targets:
  BoulderLog:
    type: application
    platform: iOS
    sources:
      - BoulderLog
    settings:
      base:
        SWIFT_VERSION: "5.9"
        PRODUCT_BUNDLE_IDENTIFIER: com.boulderlog.BoulderLog
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_NSPhotoLibraryUsageDescription: "BoulderLog needs access to your photo library to import climbing videos."
        INFOPLIST_KEY_UIApplicationSceneManifest_Generation: YES
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
  BoulderLogTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - BoulderLogTests
    dependencies:
      - target: BoulderLog
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.boulderlog.BoulderLogTests
```

- [ ] **Step 3: Create folder structure**

```bash
mkdir -p BoulderLog/Models BoulderLog/Detection BoulderLog/Views BoulderLog/ViewModels
mkdir -p BoulderLogTests/Detection BoulderLogTests/Models
```

- [ ] **Step 4: Create BoulderLog/BoulderLogApp.swift**

```swift
import SwiftUI
import SwiftData

@main
struct BoulderLogApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Route.self, Attempt.self, RouteFingerprint.self])
    }
}
```

- [ ] **Step 5: Create BoulderLog/ContentView.swift**

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            Text("BoulderLog")
        }
    }
}
```

- [ ] **Step 6: Create .gitignore**

```
*.xcuserstate
xcuserdata/
.DS_Store
DerivedData/
.superpowers/
```

- [ ] **Step 7: Generate the Xcode project**

```bash
xcodegen generate
```

Expected: `BoulderLog.xcodeproj` created in the current directory.

- [ ] **Step 8: Verify the project builds**

```bash
xcodebuild build -scheme BoulderLog -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 9: Commit**

```bash
git add project.yml BoulderLog/ BoulderLogTests/ .gitignore BoulderLog.xcodeproj
git commit -m "feat: scaffold BoulderLog iOS project"
```

---

## Task 2: SwiftData Models

**Files:**
- Create: `BoulderLog/Models/Route.swift`
- Create: `BoulderLog/Models/Attempt.swift`
- Create: `BoulderLog/Models/RouteFingerprint.swift`
- Create: `BoulderLogTests/Models/ModelTests.swift`

- [ ] **Step 1: Write the failing tests**

`BoulderLogTests/Models/ModelTests.swift`:

```swift
import XCTest
import SwiftData
@testable import BoulderLog

final class ModelTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Route.self, Attempt.self, RouteFingerprint.self,
                                       configurations: config)
        context = ModelContext(container)
    }

    func test_route_defaultsToNotSent() throws {
        let route = Route(dominantColor: "#1A6BFF")
        context.insert(route)
        try context.save()
        XCTAssertFalse(route.isSent)
        XCTAssertNil(route.grade)
    }

    func test_attempt_linksToRoute() throws {
        let route = Route(dominantColor: "#FF6B35")
        let attempt = Attempt(assetIdentifier: "test-id", route: route)
        context.insert(route)
        context.insert(attempt)
        try context.save()
        XCTAssertEqual(attempt.route.id, route.id)
        XCTAssertEqual(route.attempts.count, 1)
    }

    func test_routeFingerprint_storesDescriptor() throws {
        let fp = RouteFingerprint(routeId: UUID(), descriptor: [0.1, 0.2, 0.3], dominantHue: 0.6)
        context.insert(fp)
        try context.save()
        XCTAssertEqual(fp.descriptor, [0.1, 0.2, 0.3])
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
xcodebuild test -scheme BoulderLog -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:BoulderLogTests/ModelTests 2>&1 | grep -E "FAILED|error:|passed|failed"
```

Expected: compile error — `Route`, `Attempt`, `RouteFingerprint` not defined.

- [ ] **Step 3: Create BoulderLog/Models/Route.swift**

```swift
import SwiftData
import Foundation

@Model
final class Route {
    var id: UUID
    var dominantColor: String
    var name: String
    var createdAt: Date
    var lastAttemptAt: Date
    var isSent: Bool
    var grade: String?
    @Relationship(deleteRule: .cascade, inverse: \Attempt.route)
    var attempts: [Attempt]

    init(dominantColor: String) {
        self.id = UUID()
        self.dominantColor = dominantColor
        self.name = "\(colorName(for: dominantColor)) route"
        self.createdAt = Date()
        self.lastAttemptAt = Date()
        self.isSent = false
        self.attempts = []
    }
}

private func colorName(for hex: String) -> String {
    // Rough hue-based label from hex color string
    let knownColors: [(prefix: String, name: String)] = [
        ("#FF", "Red"), ("#F0", "Orange"), ("#FF6", "Yellow"),
        ("#0", "Green"), ("#1", "Blue"), ("#6", "Purple"), ("#9", "Pink"),
    ]
    let upper = hex.uppercased()
    return knownColors.first { upper.hasPrefix($0.prefix) }?.name ?? "Unknown"
}
```

- [ ] **Step 4: Create BoulderLog/Models/Attempt.swift**

```swift
import SwiftData
import Foundation

@Model
final class Attempt {
    var id: UUID
    var assetIdentifier: String
    var date: Date
    var isSend: Bool
    var notes: String
    var route: Route

    init(assetIdentifier: String, route: Route, isSend: Bool = false, notes: String = "") {
        self.id = UUID()
        self.assetIdentifier = assetIdentifier
        self.date = Date()
        self.isSend = isSend
        self.notes = notes
        self.route = route
    }
}
```

- [ ] **Step 5: Create BoulderLog/Models/RouteFingerprint.swift**

```swift
import SwiftData
import Foundation

@Model
final class RouteFingerprint {
    var routeId: UUID
    var descriptor: [Float]
    var dominantHue: Float

    init(routeId: UUID, descriptor: [Float], dominantHue: Float) {
        self.routeId = routeId
        self.descriptor = descriptor
        self.dominantHue = dominantHue
    }
}
```

- [ ] **Step 6: Run tests to confirm they pass**

```bash
xcodebuild test -scheme BoulderLog -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:BoulderLogTests/ModelTests 2>&1 | grep -E "passed|failed|error:"
```

Expected: `Test Suite 'ModelTests' passed`

- [ ] **Step 7: Commit**

```bash
git add BoulderLog/Models/ BoulderLogTests/Models/
git commit -m "feat: add SwiftData models (Route, Attempt, RouteFingerprint)"
```

---

## Task 3: Detection Types + FrameExtractor

**Files:**
- Create: `BoulderLog/Detection/Types.swift`
- Create: `BoulderLog/Detection/FrameExtractor.swift`
- Create: `BoulderLogTests/Detection/FrameExtractorTests.swift`

- [ ] **Step 1: Create BoulderLog/Detection/Types.swift**

These shared types are used across all detection units.

```swift
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
```

- [ ] **Step 2: Write the failing test**

`BoulderLogTests/Detection/FrameExtractorTests.swift`:

```swift
import XCTest
import AVFoundation
import CoreImage
@testable import BoulderLog

final class FrameExtractorTests: XCTestCase {
    func test_extractFrames_returnsRequestedCount() async throws {
        // Create a 1-second synthetic video asset
        let asset = try makeSyntheticVideoAsset(duration: 1.0)
        let frames = try await FrameExtractor.extractFrames(from: asset, count: 5)
        XCTAssertEqual(frames.count, 5)
    }

    func test_extractFrames_returnsNonEmptyImages() async throws {
        let asset = try makeSyntheticVideoAsset(duration: 2.0)
        let frames = try await FrameExtractor.extractFrames(from: asset, count: 3)
        for frame in frames {
            XCTAssertFalse(frame.extent.isEmpty)
        }
    }

    // Creates a minimal AVAsset from a single solid-color JPEG written to a temp file.
    // This avoids needing Photos permissions in tests.
    private func makeSyntheticVideoAsset(duration: Double) throws -> AVAsset {
        // Generate a temp video file using AVAssetWriter
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
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
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 320, 240, kCVPixelFormatType_32BGRA, nil, &buffer)
            let time = CMTime(value: CMTimeValue(i), timescale: 30)
            adaptor.append(buffer!, withPresentationTime: time)
        }
        input.markAsFinished()
        await writer.finishWriting()
        return AVURLAsset(url: url)
    }
}
```

- [ ] **Step 3: Run test to confirm it fails**

```bash
xcodebuild test -scheme BoulderLog -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:BoulderLogTests/FrameExtractorTests 2>&1 | grep -E "passed|failed|error:"
```

Expected: compile error — `FrameExtractor` not defined.

- [ ] **Step 4: Create BoulderLog/Detection/FrameExtractor.swift**

```swift
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
            options.isNetworkAccessAllowed = false
            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { asset, _, _ in
                if let asset {
                    continuation.resume(returning: asset)
                } else {
                    continuation.resume(throwing: DetectionError.couldNotLoadAsset)
                }
            }
        }
    }
}
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
xcodebuild test -scheme BoulderLog -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:BoulderLogTests/FrameExtractorTests 2>&1 | grep -E "passed|failed|error:"
```

Expected: `Test Suite 'FrameExtractorTests' passed`

- [ ] **Step 6: Commit**

```bash
git add BoulderLog/Detection/Types.swift BoulderLog/Detection/FrameExtractor.swift \
        BoulderLogTests/Detection/FrameExtractorTests.swift
git commit -m "feat: add detection types and FrameExtractor"
```

---

## Task 4: HoldSegmenter

**Files:**
- Create: `BoulderLog/Detection/HoldSegmenter.swift`
- Create: `BoulderLogTests/Detection/HoldSegmenterTests.swift`

- [ ] **Step 1: Write the failing tests**

`BoulderLogTests/Detection/HoldSegmenterTests.swift`:

```swift
import XCTest
import CoreImage
@testable import BoulderLog

final class HoldSegmenterTests: XCTestCase {

    // Helpers to create solid-color test images
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
        // Pure saturated blue: RGB(0, 0, 255)
        let image = makeImage(r: 0, g: 0, b: 255)
        let (candidates, hue) = try HoldSegmenter.detectHolds(in: image)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertGreaterThan(hue, 0.55)
        XCTAssertLessThan(hue, 0.7)
    }

    func test_greyImage_detectsNoBlobs() throws {
        // Unsaturated grey: RGB(128, 128, 128)
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
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
xcodebuild test -scheme BoulderLog -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:BoulderLogTests/HoldSegmenterTests 2>&1 | grep -E "passed|failed|error:"
```

Expected: compile error — `HoldSegmenter` not defined.

- [ ] **Step 3: Create BoulderLog/Detection/HoldSegmenter.swift**

```swift
import CoreImage
import CoreGraphics

struct HoldSegmenter {
    private static let targetWidth = 160
    private static let targetHeight = 120
    private static let minimumBlobPixels = 8       // in downsampled image
    private static let saturationThreshold: Float = 0.30
    private static let brightnessThreshold: Float  = 0.20
    private static let hueBinCount = 20

    /// Returns (blobs for dominant hue, dominant hue value).
    static func detectHolds(in image: CIImage) throws -> (candidates: [HoldCandidate], dominantHue: Float) {
        let (pixels, w, h) = try rasterize(image)

        // Classify each pixel into a hue bin (ignoring unsaturated/dark pixels)
        var hueBins = [[Int]](repeating: [], count: hueBinCount)
        for i in 0..<(w * h) {
            let r = Float(pixels[i*4])   / 255.0
            let g = Float(pixels[i*4+1]) / 255.0
            let b = Float(pixels[i*4+2]) / 255.0
            let (hue, sat, val) = rgbToHSV(r: r, g: g, b: b)
            guard sat > saturationThreshold && val > brightnessThreshold else { continue }
            let bin = min(Int(hue * Float(hueBinCount)), hueBinCount - 1)
            hueBins[bin].append(i)
        }

        // Find dominant hue bin
        guard let (dominantBinIdx, dominantPixels) = hueBins.enumerated()
            .max(by: { $0.element.count < $1.element.count }),
              dominantPixels.count >= minimumBlobPixels else {
            return ([], 0)
        }

        let dominantHue = (Float(dominantBinIdx) + 0.5) / Float(hueBinCount)
        let pixelSet = Set(dominantPixels)

        // BFS connected components on dominant-hue pixels
        var visited = Set<Int>()
        var blobs: [[Int]] = []

        for start in dominantPixels {
            guard !visited.contains(start) else { continue }
            var blob: [Int] = []
            var queue = [start]
            var head = 0
            while head < queue.count {
                let cur = queue[head]; head += 1
                guard !visited.contains(cur) else { continue }
                visited.insert(cur)
                blob.append(cur)
                let x = cur % w, y = cur / w
                for (dx, dy) in [(-1,0),(1,0),(0,-1),(0,1)] {
                    let nx = x+dx, ny = y+dy
                    guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                    let nb = ny * w + nx
                    if pixelSet.contains(nb) && !visited.contains(nb) {
                        queue.append(nb)
                    }
                }
            }
            if blob.count >= minimumBlobPixels { blobs.append(blob) }
        }

        let candidates: [HoldCandidate] = blobs.map { blob in
            let xSum = blob.reduce(0) { $0 + ($1 % w) }
            let ySum = blob.reduce(0) { $0 + ($1 / w) }
            let cx = Float(xSum) / Float(blob.count) / Float(w)
            let cy = Float(ySum) / Float(blob.count) / Float(h)
            return HoldCandidate(centroid: SIMD2<Float>(cx, cy),
                                 hue: dominantHue,
                                 pixelCount: blob.count)
        }

        return (candidates, dominantHue)
    }

    // Downsample and rasterize to RGBA pixel array
    private static func rasterize(_ image: CIImage) throws -> (pixels: [UInt8], width: Int, height: Int) {
        let scale = min(Float(targetWidth) / Float(image.extent.width),
                        Float(targetHeight) / Float(image.extent.height))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
        let w = Int(scaled.extent.width)
        let h = Int(scaled.extent.height)

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let bitmapCtx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw DetectionError.renderFailed }

        let ciCtx = CIContext()
        guard let cg = ciCtx.createCGImage(scaled, from: scaled.extent) else {
            throw DetectionError.renderFailed
        }
        bitmapCtx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (pixels, w, h)
    }

    private static func rgbToHSV(r: Float, g: Float, b: Float) -> (h: Float, s: Float, v: Float) {
        let maxC = max(r, g, b), minC = min(r, g, b)
        let delta = maxC - minC
        let v = maxC
        let s = maxC == 0 ? Float(0) : delta / maxC
        var h: Float = 0
        if delta > 0 {
            if maxC == r      { h = (g - b) / delta }
            else if maxC == g { h = 2 + (b - r) / delta }
            else              { h = 4 + (r - g) / delta }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, s, v)
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
xcodebuild test -scheme BoulderLog -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:BoulderLogTests/HoldSegmenterTests 2>&1 | grep -E "passed|failed|error:"
```

Expected: `Test Suite 'HoldSegmenterTests' passed`

- [ ] **Step 5: Commit**

```bash
git add BoulderLog/Detection/HoldSegmenter.swift BoulderLogTests/Detection/HoldSegmenterTests.swift
git commit -m "feat: add HoldSegmenter (HSV pixel segmentation + BFS blobs)"
```

---

## Task 5: FingerprintGenerator

**Files:**
- Create: `BoulderLog/Detection/FingerprintGenerator.swift`
- Create: `BoulderLogTests/Detection/FingerprintGeneratorTests.swift`

- [ ] **Step 1: Write the failing tests**

`BoulderLogTests/Detection/FingerprintGeneratorTests.swift`:

```swift
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
        // After bounding-box normalization [0,1]×[0,1], distance = sqrt(2)/2 ≈ 0.707... 
        // but normalization maps (0,0)→(0,0) and (1,1)→(1,1) so distance stays sqrt(2) ≈ 1.414
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
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
xcodebuild test -scheme BoulderLog -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:BoulderLogTests/FingerprintGeneratorTests 2>&1 | grep -E "passed|failed|error:"
```

Expected: compile error — `FingerprintGenerator` not defined.

- [ ] **Step 3: Create BoulderLog/Detection/FingerprintGenerator.swift**

```swift
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
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
xcodebuild test -scheme BoulderLog -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:BoulderLogTests/FingerprintGeneratorTests 2>&1 | grep -E "passed|failed|error:"
```

Expected: `Test Suite 'FingerprintGeneratorTests' passed`

- [ ] **Step 5: Commit**

```bash
git add BoulderLog/Detection/FingerprintGenerator.swift \
        BoulderLogTests/Detection/FingerprintGeneratorTests.swift
git commit -m "feat: add FingerprintGenerator (bounding-box normalization + sorted pairwise distances)"
```

---

## Task 6: RouteMatcher

**Files:**
- Create: `BoulderLog/Detection/RouteMatcher.swift`
- Create: `BoulderLogTests/Detection/RouteMatcherTests.swift`

- [ ] **Step 1: Write the failing tests**

`BoulderLogTests/Detection/RouteMatcherTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
xcodebuild test -scheme BoulderLog -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:BoulderLogTests/RouteMatcherTests 2>&1 | grep -E "passed|failed|error:"
```

Expected: compile error — `RouteMatcher` not defined.

- [ ] **Step 3: Create BoulderLog/Detection/RouteMatcher.swift**

```swift
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

    // Normalised L2 distance, padding shorter array with 1.0
    private static func l2Distance(_ a: [Float], _ b: [Float]) -> Float {
        let len = max(a.count, b.count)
        guard len > 0 else { return 0 }
        let paddedA = a + [Float](repeating: 1.0, count: len - a.count)
        let paddedB = b + [Float](repeating: 1.0, count: len - b.count)
        let sumSq = zip(paddedA, paddedB).reduce(Float(0)) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
        return sqrt(sumSq / Float(len))
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
xcodebuild test -scheme BoulderLog -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:BoulderLogTests/RouteMatcherTests 2>&1 | grep -E "passed|failed|error:"
```

Expected: `Test Suite 'RouteMatcherTests' passed`

- [ ] **Step 5: Commit**

```bash
git add BoulderLog/Detection/RouteMatcher.swift BoulderLogTests/Detection/RouteMatcherTests.swift
git commit -m "feat: add RouteMatcher (hue gate + normalised L2 distance)"
```

---

## Task 7: ImportPipeline

**Files:**
- Create: `BoulderLog/Detection/ImportPipeline.swift`

The pipeline is the seam between the detection units and SwiftData. It is not unit tested directly (it coordinates I/O and model writes), but the units it calls are.

- [ ] **Step 1: Create BoulderLog/Detection/ImportPipeline.swift**

```swift
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

        // Update or create fingerprint (update dominant hue; descriptor stays as-is)
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
    case 0..<60:   r=c; g=x
    case 60..<120: r=x; g=c
    case 120..<180: g=c; b=x
    case 180..<240: g=x; b=c
    case 240..<300: r=x; b=c
    default:        r=c; b=x
    }
    return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
}
```

- [ ] **Step 2: Verify the project still builds**

```bash
xcodebuild build -scheme BoulderLog -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add BoulderLog/Detection/ImportPipeline.swift
git commit -m "feat: add ImportPipeline (orchestrates detection + SwiftData writes)"
```

---

## Task 8: LibraryView + LibraryViewModel

**Files:**
- Create: `BoulderLog/ViewModels/LibraryViewModel.swift`
- Create: `BoulderLog/Views/LibraryView.swift`
- Modify: `BoulderLog/ContentView.swift`

- [ ] **Step 1: Create BoulderLog/ViewModels/LibraryViewModel.swift**

```swift
import SwiftData
import Observation

enum LibraryFilter: String, CaseIterable {
    case all = "All"
    case sent = "Sent"
    case projects = "Projects"
}

@Observable
final class LibraryViewModel {
    var filter: LibraryFilter = .all
    var showingImport = false

    func filtered(_ routes: [Route]) -> [Route] {
        switch filter {
        case .all:      return routes
        case .sent:     return routes.filter { $0.isSent }
        case .projects: return routes.filter { !$0.isSent }
        }
    }
}
```

- [ ] **Step 2: Create BoulderLog/Views/LibraryView.swift**

```swift
import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Route.lastAttemptAt, order: .reverse) private var routes: [Route]
    @State private var viewModel = LibraryViewModel()

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterChips
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(viewModel.filtered(routes)) { route in
                            NavigationLink(destination: RouteDetailView(route: route)) {
                                RouteCardView(route: route)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("My Routes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { viewModel.showingImport = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingImport) {
                ImportFlowView()
            }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryFilter.allCases, id: \.self) { f in
                    Button(f.rawValue) { viewModel.filter = f }
                        .buttonStyle(.bordered)
                        .tint(viewModel.filter == f ? .orange : .secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

struct RouteCardView: View {
    let route: Route

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Color(hex: route.dominantColor).opacity(0.4)
                    .frame(height: 90)
                if route.isSent {
                    Text("SENT")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.green)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(6)
                }
                HStack {
                    Spacer()
                    Text("\(route.attempts.count) clips")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(6)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(route.name)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                Text(route.lastAttemptAt.formatted(.dateTime.month().day()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
```

- [ ] **Step 3: Update BoulderLog/ContentView.swift**

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        LibraryView()
    }
}
```

- [ ] **Step 4: Build and verify**

```bash
xcodebuild build -scheme BoulderLog -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add BoulderLog/ViewModels/LibraryViewModel.swift BoulderLog/Views/LibraryView.swift \
        BoulderLog/ContentView.swift
git commit -m "feat: add LibraryView with route grid and filter chips"
```

---

## Task 9: RouteDetailView + AttemptRowView

**Files:**
- Create: `BoulderLog/Views/AttemptRowView.swift`
- Create: `BoulderLog/Views/RouteDetailView.swift`

- [ ] **Step 1: Create BoulderLog/Views/AttemptRowView.swift**

```swift
import SwiftUI
import Photos

struct AttemptRowView: View {
    let attempt: Attempt

    private enum AssetState { case loading, loaded(UIImage), unavailable }
    @State private var assetState: AssetState = .loading

    var body: some View {
        HStack(spacing: 12) {
            thumbnailView
            VStack(alignment: .leading, spacing: 3) {
                Text(attempt.date.formatted(.dateTime.month().day().hour().minute()))
                    .font(.subheadline.bold())
                if case .unavailable = assetState {
                    Text("Video unavailable")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.8))
                } else if !attempt.notes.isEmpty {
                    Text(attempt.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            sendBadge
        }
        .task { await loadAsset() }
    }

    private var thumbnailView: some View {
        Group {
            switch assetState {
            case .loaded(let img):
                Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
            case .unavailable:
                Image(systemName: "video.slash").foregroundStyle(.red.opacity(0.6))
            case .loading:
                Image(systemName: "video").foregroundStyle(.secondary)
            }
        }
        .frame(width: 60, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .background(Color(.quaternarySystemFill), in: RoundedRectangle(cornerRadius: 8))
    }

    private var sendBadge: some View {
        Text(attempt.isSend ? "SEND" : "Attempt")
            .font(.caption2.bold())
            .foregroundStyle(attempt.isSend ? .white : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(attempt.isSend ? Color.green : Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func loadAsset() async {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [attempt.assetIdentifier], options: nil)
        guard let asset = fetch.firstObject else {
            assetState = .unavailable
            return
        }
        let img: UIImage? = await withCheckedContinuation { continuation in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .fastFormat
            opts.isNetworkAccessAllowed = false
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 120, height: 88),
                contentMode: .aspectFill, options: opts
            ) { image, _ in continuation.resume(returning: image) }
        }
        assetState = img.map { .loaded($0) } ?? .unavailable
    }
}
```

- [ ] **Step 2: Create BoulderLog/Views/RouteDetailView.swift**

```swift
import SwiftUI
import AVKit

struct RouteDetailView: View {
    @Bindable var route: Route
    @State private var playerItem: AVPlayerItem?
    @State private var showingPlayer = false
    @State private var selectedAttempt: Attempt?
    @State private var editingName = false
    @State private var draftName = ""

    var body: some View {
        List {
            Section {
                statsBar
            }
            Section("Attempts") {
                ForEach(route.attempts.sorted(by: { $0.date > $1.date })) { attempt in
                    AttemptRowView(attempt: attempt)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedAttempt = attempt }
                }
            }
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Rename") {
                    draftName = route.name
                    editingName = true
                }
            }
        }
        .alert("Rename Route", isPresented: $editingName) {
            TextField("Name", text: $draftName)
            Button("Save") { route.name = draftName }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $selectedAttempt) { attempt in
            VideoPlayerSheet(assetIdentifier: attempt.assetIdentifier)
        }
    }

    private var statsBar: some View {
        HStack {
            statCell(label: "Attempts", value: "\(route.attempts.count)")
            Divider()
            statCell(label: "Sent", value: route.isSent ? "✓" : "–")
            Divider()
            statCell(label: "Grade", value: route.grade ?? "–")
        }
        .frame(height: 56)
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct VideoPlayerSheet: View {
    let assetIdentifier: String
    @State private var player: AVPlayer?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView()
            }
        }
        .task { player = await makePlayer() }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
    }

    private func makePlayer() async -> AVPlayer? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = fetch.firstObject else { return nil }
        return await withCheckedContinuation { continuation in
            let opts = PHVideoRequestOptions()
            opts.isNetworkAccessAllowed = false
            PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { avAsset, _, _ in
                if let avAsset { continuation.resume(returning: AVPlayer(playerItem: AVPlayerItem(asset: avAsset))) }
                else { continuation.resume(returning: nil) }
            }
        }
    }
}
```

- [ ] **Step 3: Build and verify**

```bash
xcodebuild build -scheme BoulderLog -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add BoulderLog/Views/AttemptRowView.swift BoulderLog/Views/RouteDetailView.swift
git commit -m "feat: add RouteDetailView and AttemptRowView with video playback"
```

---

## Task 10: ImportFlowView + ImportViewModel

**Files:**
- Create: `BoulderLog/ViewModels/ImportViewModel.swift`
- Create: `BoulderLog/Views/ImportFlowView.swift`

- [ ] **Step 1: Create BoulderLog/ViewModels/ImportViewModel.swift**

```swift
import SwiftData
import PhotosUI
import Observation

enum ImportState {
    case idle
    case processing
    case matched(route: Route, confidence: Float, descriptor: RouteDescriptor)
    case ambiguous(route: Route, confidence: Float, descriptor: RouteDescriptor)
    case newRoute(descriptor: RouteDescriptor)
    case noHoldsDetected(descriptor: RouteDescriptor?)
    case duplicate
    case error(String)
}

@Observable
final class ImportViewModel {
    var selectedItem: PhotosPickerItem?
    var state: ImportState = .idle
    var isSend = false
    var notes = ""

    @MainActor
    func processSelection(_ item: PhotosPickerItem, context: ModelContext) async {
        state = .processing
        guard let identifier = item.itemIdentifier else {
            state = .error("Could not read asset identifier.")
            return
        }
        do {
            let result = try await ImportPipeline.analyze(assetIdentifier: identifier, context: context)
            switch result {
            case .matched(let route, let confidence, let descriptor):
                state = confidence >= 0.7
                    ? .matched(route: route, confidence: confidence, descriptor: descriptor)
                    : .ambiguous(route: route, confidence: confidence, descriptor: descriptor)
            case .newRoute(let descriptor):
                state = .newRoute(descriptor: descriptor)
            case .noHoldsDetected:
                state = .noHoldsDetected(descriptor: nil)
            case .duplicate:
                state = .duplicate
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    @MainActor
    func confirm(assetIdentifier: String, route: Route, descriptor: RouteDescriptor,
                 context: ModelContext) {
        try? ImportPipeline.save(assetIdentifier: assetIdentifier, to: route,
                                 isSend: isSend, notes: notes,
                                 descriptor: descriptor, context: context)
        reset()
    }

    @MainActor
    func confirmNewRoute(assetIdentifier: String, descriptor: RouteDescriptor,
                         context: ModelContext) {
        try? ImportPipeline.saveAsNewRoute(assetIdentifier: assetIdentifier,
                                           descriptor: descriptor,
                                           isSend: isSend, notes: notes,
                                           context: context)
        reset()
    }

    private func reset() {
        selectedItem = nil
        state = .idle
        isSend = false
        notes = ""
    }
}
```

- [ ] **Step 2: Create BoulderLog/Views/ImportFlowView.swift**

```swift
import SwiftUI
import SwiftData
import PhotosUI

struct ImportFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Route.lastAttemptAt, order: .reverse) private var routes: [Route]
    @State private var viewModel = ImportViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Import Video")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .onChange(of: viewModel.selectedItem) { _, item in
                    guard let item else { return }
                    Task { await viewModel.processSelection(item, context: modelContext) }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            PhotosPicker(selection: $viewModel.selectedItem, matching: .videos) {
                Label("Choose Video", systemImage: "video.badge.plus")
                    .font(.title3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .processing:
            VStack(spacing: 16) {
                ProgressView()
                Text("Detecting holds…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .matched(let route, let confidence, let descriptor):
            confirmationView(route: route, confidence: confidence,
                             descriptor: descriptor, isAmbiguous: false)

        case .ambiguous(let route, let confidence, let descriptor):
            confirmationView(route: route, confidence: confidence,
                             descriptor: descriptor, isAmbiguous: true)

        case .newRoute(let descriptor):
            newRouteView(descriptor: descriptor)

        case .noHoldsDetected:
            manualPickView(message: "Couldn't detect holds — pick manually")

        case .duplicate:
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.circle").font(.largeTitle).foregroundStyle(.orange)
                Text("This video is already logged.")
                Button("Done") { dismiss() }.buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .error(let msg):
            VStack(spacing: 16) {
                Image(systemName: "xmark.circle").font(.largeTitle).foregroundStyle(.red)
                Text(msg).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Try Again") { viewModel.state = .idle }.buttonStyle(.bordered)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func confirmationView(route: Route, confidence: Float,
                                   descriptor: RouteDescriptor, isAmbiguous: Bool) -> some View {
        Form {
            Section {
                HStack {
                    Circle().fill(Color(hex: route.dominantColor)).frame(width: 28, height: 28)
                    VStack(alignment: .leading) {
                        Text(route.name).font(.headline)
                        Text("\(Int(confidence * 100))% confidence · \(route.attempts.count) previous attempts")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                holdsOverlay(descriptor: descriptor)
            } header: {
                Text(isAmbiguous ? "Possible Match (low confidence)" : "Matched Route")
            }

            Section("Log") {
                Toggle("This was a send", isOn: $viewModel.isSend)
                TextField("Notes", text: $viewModel.notes, axis: .vertical).lineLimit(3)
            }

            Section {
                Button("Add as Attempt") {
                    guard let id = viewModel.selectedItem?.itemIdentifier else { return }
                    viewModel.confirm(assetIdentifier: id, route: route,
                                     descriptor: descriptor, context: modelContext)
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .bold()

                if isAmbiguous {
                    Button("Create New Route Instead") {
                        guard let id = viewModel.selectedItem?.itemIdentifier else { return }
                        viewModel.confirmNewRoute(assetIdentifier: id,
                                                  descriptor: descriptor, context: modelContext)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func newRouteView(descriptor: RouteDescriptor) -> some View {
        Form {
            Section {
                holdsOverlay(descriptor: descriptor)
                Text("No matching route found. This will create a new route.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("New Route") }

            Section("Log") {
                Toggle("This was a send", isOn: $viewModel.isSend)
                TextField("Notes", text: $viewModel.notes, axis: .vertical).lineLimit(3)
            }

            Section {
                Button("Create Route & Add Attempt") {
                    guard let id = viewModel.selectedItem?.itemIdentifier else { return }
                    viewModel.confirmNewRoute(assetIdentifier: id,
                                              descriptor: descriptor, context: modelContext)
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .bold()
            }
        }
    }

    private func manualPickView(message: String) -> some View {
        List {
            Section {
                Text(message).foregroundStyle(.secondary).font(.caption)
            }
            Section("Pick Route") {
                ForEach(routes) { route in
                    Button {
                        // Create a minimal empty descriptor for manual assignment
                        let desc = RouteDescriptor(centroidDistances: [],
                                                   dominantHue: 0,
                                                   normalizedCentroids: [])
                        guard let id = viewModel.selectedItem?.itemIdentifier else { return }
                        viewModel.confirm(assetIdentifier: id, route: route,
                                          descriptor: desc, context: modelContext)
                        dismiss()
                    } label: {
                        HStack {
                            Circle().fill(Color(hex: route.dominantColor)).frame(width: 20, height: 20)
                            Text(route.name)
                            Spacer()
                            Text("\(route.attempts.count) attempts").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button("Create New Route") {
                    let desc = RouteDescriptor(centroidDistances: [],
                                               dominantHue: 0,
                                               normalizedCentroids: [])
                    guard let id = viewModel.selectedItem?.itemIdentifier else { return }
                    viewModel.confirmNewRoute(assetIdentifier: id,
                                              descriptor: desc, context: modelContext)
                    dismiss()
                }
            }
        }
    }

    private func holdsOverlay(descriptor: RouteDescriptor) -> some View {
        GeometryReader { geo in
            ZStack {
                Color(.secondarySystemGroupedBackground)
                ForEach(Array(descriptor.normalizedCentroids.enumerated()), id: \.offset) { _, pt in
                    Circle()
                        .fill(Color.blue.opacity(0.8))
                        .frame(width: 14, height: 14)
                        .offset(x: CGFloat(pt.x) * geo.size.width - 7,
                                y: CGFloat(pt.y) * geo.size.height - 7)
                }
            }
        }
        .frame(height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
```

- [ ] **Step 3: Build and verify the full project**

```bash
xcodebuild build -scheme BoulderLog -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Run all tests**

```bash
xcodebuild test -scheme BoulderLog -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "passed|failed|error:"
```

Expected: All test suites pass.

- [ ] **Step 5: Commit**

```bash
git add BoulderLog/ViewModels/ImportViewModel.swift BoulderLog/Views/ImportFlowView.swift
git commit -m "feat: add ImportFlowView and ImportViewModel — completes full import flow"
```

---

## Done

All 10 tasks complete. The app is buildable and all unit tests pass. To run in the simulator:

```bash
open BoulderLog.xcodeproj
```

Then select an iPhone 16 simulator and press Run (⌘R).

**Manual verification checklist:**
- [ ] Library screen shows empty state on first launch
- [ ] Tapping "+" opens the import sheet with a PhotosPicker
- [ ] Selecting a video triggers the processing spinner
- [ ] Import flow shows route match or new-route screen
- [ ] Confirming saves the attempt and it appears in Route Detail
- [ ] Tapping an attempt row plays the video
- [ ] Importing the same video twice shows the duplicate warning
