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
