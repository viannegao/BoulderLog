import SwiftData
import Foundation

@Model
final class Route {
    var id: UUID
    var dominantColor: String
    var name: String
    var createdAt: Date
    var lastAttemptAt: Date
    var isSent: Bool
    var grade: String?
    @Relationship(deleteRule: .cascade, inverse: \Attempt.route)
    var attempts: [Attempt]

    init(dominantColor: String) {
        self.id = UUID()
        self.dominantColor = dominantColor
        self.name = "\(colorName(for: dominantColor)) route"
        self.createdAt = Date()
        self.lastAttemptAt = Date()
        self.isSent = false
        self.attempts = []
    }
}

private func colorName(for hex: String) -> String {
    let knownColors: [(prefix: String, name: String)] = [
        ("#FF6", "Yellow"), ("#FF", "Red"), ("#F0", "Orange"),
        ("#0", "Green"), ("#1", "Blue"), ("#6", "Purple"), ("#9", "Pink"),
    ]
    let upper = hex.uppercased()
    return knownColors.first { upper.hasPrefix($0.prefix) }?.name ?? "Unknown"
}
