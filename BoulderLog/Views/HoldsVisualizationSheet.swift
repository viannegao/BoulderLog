import SwiftUI
import CoreImage

struct HoldsVisualizationSheet: View {
    let assetIdentifier: String
    @Environment(\.dismiss) private var dismiss

    private enum ViewState {
        case loading
        case loaded(UIImage, [HoldGroup])
        case failed(String)
    }
    @State private var viewState: ViewState = .loading
    @State private var selectedGroupID: UUID? = nil

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

                case .loaded(let image, let groups):
                    loadedView(image: image, groups: groups)

                case .failed(let msg):
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.largeTitle).foregroundStyle(.orange)
                        Text(msg).multilineTextAlignment(.center).foregroundStyle(.secondary)
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

    private func loadedView(image: UIImage, groups: [HoldGroup]) -> some View {
        let selected = groups.first(where: { $0.id == selectedGroupID })
        let holdCount = selected?.candidates.count ?? groups.flatMap(\.candidates).count
        return VStack(spacing: 0) {
            annotatedImage(image: image, groups: groups, selectedID: selectedGroupID)
                .padding([.horizontal, .top])

            Text(selected == nil
                 ? "\(holdCount) holds across all colors"
                 : "\(holdCount) holds in selected color")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            colorPicker(groups: groups)
                .padding()
        }
    }

    private func annotatedImage(image: UIImage, groups: [HoldGroup], selectedID: UUID?) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .overlay(
                GeometryReader { geo in
                    ForEach(groups) { group in
                        let isHighlighted = selectedID == nil || selectedID == group.id
                        let color = Color(hue: Double(group.hue), saturation: 0.85, brightness: 0.95)
                        ForEach(Array(group.candidates.enumerated()), id: \.offset) { _, c in
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .background(Circle().fill(color.opacity(isHighlighted ? 0.75 : 0.12)))
                                .frame(width: 22, height: 22)
                                .position(
                                    x: CGFloat(c.centroid.x) * geo.size.width,
                                    y: CGFloat(c.centroid.y) * geo.size.height
                                )
                        }
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func colorPicker(groups: [HoldGroup]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tap a color to isolate that route's holds")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // "All" pill
                    Button { selectedGroupID = nil } label: {
                        Text("All")
                            .font(.caption.bold())
                            .foregroundStyle(selectedGroupID == nil ? .white : .primary)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(selectedGroupID == nil ? Color.primary : Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    // One pill per detected color group
                    ForEach(groups) { group in
                        let color = Color(hue: Double(group.hue), saturation: 0.85, brightness: 0.95)
                        let isSelected = selectedGroupID == group.id
                        Button { selectedGroupID = isSelected ? nil : group.id } label: {
                            HStack(spacing: 6) {
                                Circle().fill(color).frame(width: 12, height: 12)
                                Text("\(group.candidates.count)")
                                    .font(.caption.bold())
                            }
                            .foregroundStyle(isSelected ? .white : .primary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(isSelected ? color : Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func detect() async {
        do {
            let frames = try await FrameExtractor.extractFrames(
                fromAssetIdentifier: assetIdentifier, count: 3)
            guard let frame = frames.dropFirst().first ?? frames.first else {
                viewState = .failed("Could not extract video frame")
                return
            }
            let groups = try HoldSegmenter.detectAllHoldGroups(in: frame)
            let ctx = CIContext()
            guard let cgImage = ctx.createCGImage(frame, from: frame.extent) else {
                viewState = .failed("Could not render frame")
                return
            }
            if groups.isEmpty {
                viewState = .failed("No colored holds detected. Try a brighter frame.")
            } else {
                viewState = .loaded(UIImage(cgImage: cgImage), groups)
            }
        } catch {
            viewState = .failed(error.localizedDescription)
        }
    }
}
