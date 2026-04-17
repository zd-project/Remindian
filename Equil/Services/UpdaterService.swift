import Foundation
import AppKit

/// Lightweight auto-updater that checks GitHub Releases for new versions.
/// In a sandboxed app, Process() calls (hdiutil, open) are unreliable,
/// so we open the DMG download URL in the browser and let the user
/// drag-install. The version check itself uses URLSession (allowed by
/// the com.apple.security.network.client entitlement).
@MainActor
class UpdaterService: ObservableObject {
    static let shared = UpdaterService()

    private let owner = "Santofer"
    private let repo = "Remindian"

    @Published var updateAvailable = false
    @Published var latestVersion: String = ""
    @Published var releaseNotes: String = ""
    @Published var downloadURL: URL?
    @Published var releasePageURL: URL?
    @Published var isChecking = false
    @Published var lastCheckDate: Date?
    @Published var errorMessage: String?
    @Published var upToDate = false

    private var checkTimer: Timer?

    private init() {
        debugLog("[Updater] Service initialized")
        // Check for updates on launch (after a short delay to let the app settle)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            Task { await self?.checkForUpdates(silent: true) }
        }
        // Check every 24 hours
        startPeriodicCheck()
    }

    // MARK: - Periodic Check

    func startPeriodicCheck() {
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkForUpdates(silent: true)
            }
        }
    }

    // MARK: - Check for Updates

    func checkForUpdates(silent: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        errorMessage = nil
        upToDate = false

        defer { isChecking = false }

        do {
            let release = try await fetchLatestRelease()
            let remoteVersion = release.tagName
                .replacingOccurrences(of: "v", with: "")
                .replacingOccurrences(of: "-beta", with: "")

            let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

            debugLog("[Updater] Current: \(currentVersion), Remote: \(remoteVersion)")

            if compareVersions(remoteVersion, isNewerThan: currentVersion) {
                latestVersion = release.tagName
                releaseNotes = release.body ?? ""
                downloadURL = release.assets.first(where: { $0.name.hasSuffix(".dmg") })?.browserDownloadUrl
                releasePageURL = URL(string: "https://github.com/\(owner)/\(repo)/releases/tag/\(release.tagName)")
                updateAvailable = true
                lastCheckDate = Date()

                debugLog("[Updater] Update available: \(release.tagName)")

                if !silent {
                    showUpdateNotification()
                }
            } else {
                updateAvailable = false
                lastCheckDate = Date()
                debugLog("[Updater] Up to date")
                if !silent {
                    upToDate = true
                }
            }
        } catch {
            if !silent {
                errorMessage = "Failed to check for updates: \(error.localizedDescription)"
            }
            debugLog("[Updater] Check failed: \(error)")
        }
    }

    // MARK: - Download Update

    /// Opens the DMG download in the browser. In a sandboxed app we cannot
    /// use Process() to mount DMGs or replace the running bundle, so we
    /// let the user drag-install from the downloaded DMG.
    func downloadUpdate() {
        if let url = downloadURL {
            debugLog("[Updater] Opening DMG download: \(url)")
            NSWorkspace.shared.open(url)
        } else if let page = releasePageURL {
            debugLog("[Updater] Opening release page: \(page)")
            NSWorkspace.shared.open(page)
        } else {
            errorMessage = "No download URL available"
        }
    }

    /// Opens the GitHub release page in the browser.
    func openReleasePage() {
        if let page = releasePageURL {
            NSWorkspace.shared.open(page)
        }
    }

    // MARK: - Private Helpers

    private func fetchLatestRelease() async throws -> GitHubRelease {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            throw UpdateError.apiError("Invalid GitHub API URL")
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.apiError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let snippet = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw UpdateError.apiError("HTTP \(httpResponse.statusCode): \(snippet)")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    private func showUpdateNotification() {
        NotificationService.shared.sendNotification(
            title: "Remindian Update Available",
            body: "Version \(latestVersion) is available. Open Remindian to update.",
            category: .syncComplete
        )
    }

    /// Compare two semantic version strings. Returns true if `version` > `current`.
    func compareVersions(_ version: String, isNewerThan current: String) -> Bool {
        let vParts = version.components(separatedBy: ".").compactMap { Int($0) }
        let cParts = current.components(separatedBy: ".").compactMap { Int($0) }

        let maxLen = max(vParts.count, cParts.count)
        for i in 0..<maxLen {
            let v = i < vParts.count ? vParts[i] : 0
            let c = i < cParts.count ? cParts[i] : 0
            if v > c { return true }
            if v < c { return false }
        }
        return false
    }
}

// MARK: - Models

struct GitHubRelease: Codable {
    let tagName: String
    let name: String?
    let body: String?
    let prerelease: Bool
    let assets: [GitHubAsset]
}

struct GitHubAsset: Codable {
    let name: String
    let size: Int
    let browserDownloadUrl: URL
}

// MARK: - Errors

enum UpdateError: LocalizedError {
    case apiError(String)
    case appNotFoundInDMG
    case mountFailed
    case replaceFailed

    var errorDescription: String? {
        switch self {
        case .apiError(let msg): return "GitHub API error: \(msg)"
        case .appNotFoundInDMG: return "Could not find Remindian.app in the downloaded DMG"
        case .mountFailed: return "Failed to mount the downloaded DMG"
        case .replaceFailed: return "Failed to replace the application"
        }
    }
}
