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

/// A trailing-aligned cluster of actions.
///
/// macOS System Settings places an action by its **scope**:
///
/// - **Row-scoped** (acts on one row's subject): in that row, trailing-aligned,
///   next to the label. Examples: "Siri history" `Delete Siri & Dictation
///   History…`, "Known AirDrop Contacts" `Manage…`, "Recovery Key" `Show`.
///   Build these with `SettingsRow` or `LabeledContent`.
/// - **Section-scoped** (acts on the whole group, or adds to its list): inside
///   the box, as its own last row, trailing-aligned. Examples: `Add User…`,
///   `About AirDrop & Privacy…`.
/// - **Pane-scoped**: below every box, trailing-aligned, outside the boxes.
///   Examples: `Advanced…` in Privacy & Security, `Siri Suggestions &
///   Privacy…`. Build these in the last section's `footer`.
///
/// Buttons are always sized to their content, never leading-aligned across the
/// full row width.
struct SettingsActionRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: Token.Space.sm) {
            Spacer(minLength: 0)
            content
        }
    }
}

/// A row whose explanation sits **under its own label**, the way System
/// Settings explains FileVault, AirDrop, and AirPlay Receiver.
///
/// Apple reserves the section footer for text about the group as a whole; text
/// that explains one control belongs in that control's row, where it cannot be
/// mistaken for something else.
struct SettingsRow<Control: View>: View {
    let title: String
    var description: String?
    @ViewBuilder let control: Control

    var body: some View {
        LabeledContent {
            control
        } label: {
            SettingsRowLabel(title: title, description: description)
        }
    }
}

/// The label half of a settings row: title, with an optional explanation below.
struct SettingsRowLabel: View {
    let title: String
    var description: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Token.Space.xxs) {
            Text(title)
            if let description, !description.isEmpty {
                Text(description)
                    .font(Token.Font.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
