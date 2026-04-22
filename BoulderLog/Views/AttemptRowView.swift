import SwiftUI
import Photos

struct AttemptRowView: View {
    let attempt: Attempt

    private enum AssetState { case loading, loaded(UIImage), unavailable }
    @State private var assetState: AssetState = .loading
    @State private var showingHolds = false

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
            Button {
                showingHolds = true
            } label: {
                Image(systemName: "sparkles")
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            sendBadge
        }
        .task { await loadAsset() }
        .sheet(isPresented: $showingHolds) {
            HoldsVisualizationSheet(assetIdentifier: attempt.assetIdentifier)
        }
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
