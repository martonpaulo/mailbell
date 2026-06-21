import SwiftUI

enum SettingsStatusTone {
    case success
    case inactive
    case warning
    case error

    var systemImage: String {
        switch self {
        case .success:
            "checkmark.circle.fill"
        case .inactive:
            "minus.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .error:
            "xmark.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .success:
            .green
        case .inactive:
            .secondary
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}

struct SettingsStatusValue: View {
    let title: String
    let tone: SettingsStatusTone
    let accessibilityLabel: String

    init(_ title: String, tone: SettingsStatusTone, context: String) {
        self.title = title
        self.tone = tone
        accessibilityLabel = "\(context): \(title)"
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: tone.systemImage)
                .foregroundStyle(tone.iconColor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct SettingsProgressValue: View {
    let title: String
    let accessibilityLabel: String

    init(_ title: String, context: String) {
        self.title = title
        accessibilityLabel = "\(context): \(title)"
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            ProgressView()
                .controlSize(.small)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}
