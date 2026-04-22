import SwiftUI
import AVKit
import Photos

struct RouteDetailView: View {
    @Bindable var route: Route
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
        NavigationStack {
            Group {
                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else {
                    ProgressView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { player = await makePlayer() }
    }

    private func makePlayer() async -> AVPlayer? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = fetch.firstObject else { return nil }
        return await withCheckedContinuation { continuation in
            let opts = PHVideoRequestOptions()
            opts.isNetworkAccessAllowed = false
            var resumed = false
            PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { avAsset, _, _ in
                guard !resumed else { return }
                resumed = true
                if let avAsset {
                    continuation.resume(returning: AVPlayer(playerItem: AVPlayerItem(asset: avAsset)))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
