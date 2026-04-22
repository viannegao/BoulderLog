import SwiftUI
import CoreImage

struct HoldsVisualizationSheet: View {
    let assetIdentifier: String
    @Environment(\.dismiss) private var dismiss

    private enum ViewState {
        case loading
        case loaded(UIImage, [HoldCandidate], Float)
        case failed(String)
    }
    @State private var viewState: ViewState = .loading

    var body: some View {
        NavigationStack {
            Group {
                switch viewState {
                case .loading:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Detecting holds…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .loaded(let image, let candidates, let hue):
                    ScrollView {
                        VStack(spacing: 12) {
                            annotatedImage(image: image, candidates: candidates, dominantHue: hue)
                                .padding(.horizontal)
                            Text("\(candidates.count) holds detected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical)
                    }

                case .failed(let msg):
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.largeTitle).foregroundStyle(.orange)
                        Text(msg)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Detected Holds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await detect() }
    }

    private func annotatedImage(image: UIImage, candidates: [HoldCandidate], dominantHue: Float) -> some View {
        let holdColor = Color(hue: Double(dominantHue), saturation: 0.85, brightness: 0.95)
        return Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .overlay(
                GeometryReader { geo in
                    ForEach(Array(candidates.enumerated()), id: \.offset) { _, c in
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .background(Circle().fill(holdColor.opacity(0.55)))
                            .frame(width: 22, height: 22)
                            .position(
                                x: CGFloat(c.centroid.x) * geo.size.width,
                                y: CGFloat(c.centroid.y) * geo.size.height
                            )
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func detect() async {
        do {
            // 3 frames at 0%, 50%, 100% — use the middle one
            let frames = try await FrameExtractor.extractFrames(
                fromAssetIdentifier: assetIdentifier, count: 3)
            guard let frame = frames.dropFirst().first ?? frames.first else {
                viewState = .failed("Could not extract video frame")
                return
            }
            let (candidates, dominantHue) = try HoldSegmenter.detectHolds(in: frame)
            let ctx = CIContext()
            guard let cgImage = ctx.createCGImage(frame, from: frame.extent) else {
                viewState = .failed("Could not render frame")
                return
            }
            viewState = .loaded(UIImage(cgImage: cgImage), candidates, dominantHue)
        } catch {
            viewState = .failed(error.localizedDescription)
        }
    }
}
