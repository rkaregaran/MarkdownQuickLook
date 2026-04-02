import SwiftUI

struct StatusView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Markdown Quick Look")
                .font(.largeTitle.weight(.semibold))

            Text("This app installs a Quick Look Preview Extension that best-effort targets standard .md files.")

            Text("Target content type: net.daringfireball.markdown")
                .font(.system(.body, design: .monospaced))

            Text("Expected caveat: Finder may still keep the built-in plain-text preview on some macOS releases.")
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Local verification")
                    .font(.headline)

                Text("1. Run Scripts/dev-preview.sh")
                Text("2. Open the fixture in Finder")
                Text("3. Press Space to compare Finder's chosen preview")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Opened files")
                    .font(.headline)

                if appState.openedFileURLs.isEmpty {
                    Text("No files have been opened yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.openedFileURLs, id: \.self) { url in
                        Text(url.path)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 620)
    }
}
