import SwiftUI
import AppKit

struct StatusView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(.green)

            Text(InstallExperience.headline)
                .font(.system(.title, design: .rounded).weight(.bold))

            Text(InstallExperience.bodyText)
                .font(.body)
                .foregroundStyle(.secondary)

            Text(InstallExperience.reassuranceText)
                .font(.body.weight(.medium))

            VStack(alignment: .leading, spacing: 8) {
                Text("How to use it")
                .font(.headline)

                ForEach(InstallExperience.usageSteps, id: \.self) { step in
                    Text("• \(step)")
                        .font(.body)
                }
            }

            Text(InstallExperience.caveatText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(InstallExperience.primaryActionTitle) {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(28)
        .frame(width: 560)
    }
}
