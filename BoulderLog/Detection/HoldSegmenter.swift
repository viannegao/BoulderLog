import CoreImage
import CoreGraphics

struct HoldSegmenter {
    private static let targetWidth = 320
    private static let targetHeight = 240
    private static let minimumBlobPixels = 5
    private static let saturationThreshold: Float = 0.30
    private static let brightnessThreshold: Float  = 0.20
    private static let hueBinCount = 20
    private static let ciContext = CIContext()

    // Original single-route detection used by ImportPipeline
    static func detectHolds(in image: CIImage) throws -> (candidates: [HoldCandidate], dominantHue: Float) {
        let groups = try detectAllHoldGroups(in: image)
        guard let top = groups.first else { return ([], 0) }
        return (top.candidates, top.hue)
    }

    // Detects every distinct color group — used by the visualization UI
    static func detectAllHoldGroups(in image: CIImage) throws -> [HoldGroup] {
        let (pixels, w, h) = try rasterize(image)

        // Classify every saturated pixel into a hue bin
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

        // For each bin with enough pixels, segment into blobs and collect groups
        var groups: [HoldGroup] = []
        for (binIdx, binPixels) in hueBins.enumerated() {
            guard binPixels.count >= minimumBlobPixels else { continue }
            let hue = (Float(binIdx) + 0.5) / Float(hueBinCount)
            let blobs = findBlobs(pixels: binPixels, w: w, h: h)
            let candidates: [HoldCandidate] = blobs.map { blob in
                let xSum = blob.reduce(0) { $0 + ($1 % w) }
                let ySum = blob.reduce(0) { $0 + ($1 / w) }
                let cx = Float(xSum) / Float(blob.count) / Float(w)
                let cy = Float(ySum) / Float(blob.count) / Float(h)
                return HoldCandidate(centroid: SIMD2<Float>(cx, cy),
                                     hue: hue,
                                     pixelCount: blob.count)
            }
            if !candidates.isEmpty {
                groups.append(HoldGroup(hue: hue, candidates: candidates))
            }
        }
        // Most holds first so the likely route color appears at the front of the picker
        return groups.sorted { $0.candidates.count > $1.candidates.count }
    }

    // BFS connected-component labelling within a set of pre-classified pixels
    private static func findBlobs(pixels: [Int], w: Int, h: Int) -> [[Int]] {
        let pixelSet = Set(pixels)
        var visited = Set<Int>()
        var blobs: [[Int]] = []
        for start in pixels {
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
        return blobs
    }

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

        guard let cg = ciContext.createCGImage(scaled, from: scaled.extent) else {
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
