import SwiftUI
import AppKit

struct StatusView: View {
    private let experience = InstallExperience.current()

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
