import SwiftUI
import SwiftData
import PhotosUI
import Photos

struct ImportFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Route.lastAttemptAt, order: .reverse) private var routes: [Route]
    @State private var viewModel = ImportViewModel()
    @State private var selectedItem: PhotosPickerItem?
    @State private var photosStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

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
                .onChange(of: selectedItem) { _, item in
                    guard let item else { return }
                    Task { await viewModel.processSelection(itemIdentifier: item.itemIdentifier, context: modelContext) }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            idleView

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

        case .noHoldsDetected(let descriptor):
            manualPickView(message: "Couldn't detect holds — pick manually", descriptor: descriptor)

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

    private var idleView: some View {
        Group {
            if photosStatus == .limited {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text("Full Photo Library access required")
                        .font(.headline)
                    Text("BoulderLog stores a reference to your video rather than copying it, which requires Full Access to your photo library.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(32)
            } else {
                PhotosPicker(selection: $selectedItem, matching: .videos) {
                    Label("Choose Video", systemImage: "video.badge.plus")
                        .font(.title3)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if photosStatus == .notDetermined {
                photosStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            }
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
                    guard let id = viewModel.currentAssetIdentifier else { return }
                    if viewModel.confirm(assetIdentifier: id, route: route,
                                        descriptor: descriptor, context: modelContext) {
                        dismiss()
                    }
                }
                .frame(maxWidth: .infinity)
                .bold()

                if isAmbiguous {
                    Button("Create New Route Instead") {
                        guard let id = viewModel.currentAssetIdentifier else { return }
                        if viewModel.confirmNewRoute(assetIdentifier: id,
                                                    descriptor: descriptor, context: modelContext) {
                            dismiss()
                        }
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
                    guard let id = viewModel.currentAssetIdentifier else { return }
                    if viewModel.confirmNewRoute(assetIdentifier: id,
                                                descriptor: descriptor, context: modelContext) {
                        dismiss()
                    }
                }
                .frame(maxWidth: .infinity)
                .bold()
            }
        }
    }

    private func manualPickView(message: String, descriptor: RouteDescriptor?) -> some View {
        List {
            Section {
                Text(message).foregroundStyle(.secondary).font(.caption)
            }
            Section("Pick Route") {
                ForEach(routes) { route in
                    Button {
                        let desc = RouteDescriptor(centroidDistances: [],
                                                   dominantHue: 0,
                                                   normalizedCentroids: [])
                        guard let id = viewModel.currentAssetIdentifier else { return }
                        if viewModel.confirm(assetIdentifier: id, route: route,
                                             descriptor: desc, context: modelContext) {
                            dismiss()
                        }
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
                    guard let id = viewModel.currentAssetIdentifier else { return }
                    if viewModel.confirmNewRoute(assetIdentifier: id,
                                                descriptor: desc, context: modelContext) {
                        dismiss()
                    }
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
