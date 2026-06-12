import SwiftUI

struct SettingsStatusLabel: View {
    enum Tone {
        case secondary
        case warning
    }

    let message: String
    let systemImage: String
    var tone: Tone = .secondary

    var body: some View {
        label
            .font(.caption)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private var label: some View {
        switch tone {
        case .secondary:
            Label(message, systemImage: systemImage)
                .foregroundStyle(.secondary)
        case .warning:
            Label(message, systemImage: systemImage)
                .foregroundStyle(.orange)
        }
    }
}
