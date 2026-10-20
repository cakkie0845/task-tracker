import SwiftUI

enum AppTheme {
    static let accent = Color.indigo
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let subtleBackground = Color(uiColor: .systemGroupedBackground)
}

extension Importance {
    var color: Color {
        switch self {
        case .high: .red
        case .medium: .yellow
        case .low: .green
        }
    }

    var symbol: String {
        switch self {
        case .high: "exclamationmark.3"
        case .medium: "exclamationmark.2"
        case .low: "exclamationmark"
        }
    }
}

extension Urgency {
    var color: Color {
        switch self {
        case .immediate: .purple
        case .urgent: .orange
        case .relaxed: .blue
        }
    }

    var symbol: String {
        switch self {
        case .immediate: "bolt.fill"
        case .urgent: "clock.fill"
        case .relaxed: "hourglass"
        }
    }
}
