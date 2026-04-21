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
