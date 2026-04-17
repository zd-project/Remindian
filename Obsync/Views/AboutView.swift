import SwiftUI

struct AboutView: View {
    private let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3.2.0"
    private let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "3"
    private let releaseDate = "March 2026"
    private let githubURL = "https://github.com/Santofer/Remindian"
    private let buyMeCoffeeURL = "https://buymeacoffee.com/santofer"

    var body: some View {
        VStack(spacing: 16) {
            // App icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .cornerRadius(20)
                .shadow(radius: 4)

            // App name & version
            Text("Remindian")
                .font(.title)
                .fontWeight(.bold)

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.caption)
                .foregroundColor(.secondary)

            // Tagline
            Text("Sync your tasks between Obsidian, Apple Reminders & Things 3")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Divider()
                .frame(width: 240)

            // Author & info
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("Made by")
                        .foregroundColor(.secondary)
                    Text("Santofer")
                        .fontWeight(.medium)
                }
                .font(.callout)

                HStack(spacing: 4) {
                    Text("Released")
                        .foregroundColor(.secondary)
                    Text(releaseDate)
                        .fontWeight(.medium)
                }
                .font(.callout)

                HStack(spacing: 4) {
                    Image(systemName: "lock.open.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("Open Source")
                        .fontWeight(.medium)
                }
                .font(.callout)
            }

            Divider()
                .frame(width: 240)

            // Action buttons
            VStack(spacing: 10) {
                Button(action: {
                    if let url = URL(string: githubURL) {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                        Text("View on GitHub")
                    }
                    .frame(width: 200)
                }
                .buttonStyle(.bordered)

                // Buy Me a Coffee button
                Button(action: {
                    if let url = URL(string: buyMeCoffeeURL) {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 6) {
                        Text("\u{2615}")
                            .font(.body)
                        Text("Buy Me a Coffee")
                            .fontWeight(.medium)
                    }
                    .frame(width: 200)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

            Text("Free and open source under the MIT License")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.top, 2)
        }
        .padding(30)
        .frame(width: 340, height: 580)
    }
}

#Preview {
    AboutView()
}
