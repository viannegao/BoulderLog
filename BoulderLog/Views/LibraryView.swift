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

// Stubs — replaced in Tasks 9 and 10
struct RouteDetailView: View {
    let route: Route
    var body: some View { Text(route.name) }
}

struct ImportFlowView: View {
    var body: some View { Text("Import") }
}
