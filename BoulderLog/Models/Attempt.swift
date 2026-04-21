import SwiftData
import Foundation

@Model
final class Attempt {
    var id: UUID
    var assetIdentifier: String
    var date: Date
    var isSend: Bool
    var notes: String
    var route: Route

    init(assetIdentifier: String, route: Route, isSend: Bool = false, notes: String = "") {
        self.id = UUID()
        self.assetIdentifier = assetIdentifier
        self.date = Date()
        self.isSend = isSend
        self.notes = notes
        self.route = route
    }
}
