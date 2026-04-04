import MarkdownRendering
import SwiftUI

struct StatusView: View {
    private let experience = InstallExperience.current()
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: experience.state == .installed ? "checkmark.circle.fill" : "arrow.down.app.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(experience.state == .installed ? .green : .orange)

            Text(experience.headline)
                .font(.system(.title, design: .rounded).weight(.bold))

            Text(experience.bodyText)
                .font(.body)
                .foregroundStyle(.secondary)

            Text(experience.reassuranceText)
                .font(.body.weight(.medium))

            VStack(alignment: .leading, spacing: 8) {
                Text(experience.stepsTitle)
                .font(.headline)

                ForEach(experience.usageSteps, id: \.self) { step in
                    Text("• \(step)")
                        .font(.body)
                }
            }

            Text(experience.caveatText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()

            DisclosureGroup("Preview Settings", isExpanded: $showSettings) {
                if showSettings {
                    SettingsPanel()
                }
            }
            .font(.headline)

            Button(experience.primaryActionTitle) {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(28)
        .frame(width: 560)
    }
}

private struct SettingsPanel: View {
    @StateObject private var settingsStore = MarkdownSettingsStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Aa")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { Double(settingsStore.settings.textSizeLevel.rawValue) },
                            set: { settingsStore.settings.textSizeLevel = TextSizeLevel(rawValue: Int($0)) ?? .medium }
                        ),
                        in: 0...6,
                        step: 1
                    )
                    Text("Aa")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }

                Text(settingsStore.settings.textSizeLevel.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Font", selection: $settingsStore.settings.fontFamily) {
                ForEach(FontFamily.allCases, id: \.self) { family in
                    Text(family.displayName).tag(family)
                }
            }
            .pickerStyle(.segmented)

            previewSnippet
        }
        .padding(.top, 4)
    }

    private var fontDesign: Font.Design {
        switch settingsStore.settings.fontFamily {
        case .system: return .default
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }

    private var previewSnippet: some View {
        let scale = settingsStore.settings.textSizeLevel.scaleFactor

        return GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Text("Heading")
                    .font(.system(size: 20 * scale, weight: .semibold, design: fontDesign))
                Text("The quick brown fox jumps over the lazy dog.")
                    .font(.system(size: 15 * scale, design: fontDesign))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
