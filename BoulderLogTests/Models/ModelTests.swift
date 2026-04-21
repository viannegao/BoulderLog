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

    override func tearDown() {
        context = nil
        container = nil
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
        context.insert(route)
        let attempt = Attempt(assetIdentifier: "test-id", route: route)
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
