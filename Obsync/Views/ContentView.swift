import SwiftUI

// MARK: - Shared Settings Window Helper

/// Opens the Settings window reliably, even when running as menu bar accessory.
/// Always creates the window programmatically — the native Settings scene +
/// sendAction("showSettingsWindow:") returns true but doesn't display on macOS 26.
func openNativeSettingsWindow() {
    // Temporarily become a regular app so we can present windows
    let wasAccessory = NSApp.activationPolicy() == .accessory
    if wasAccessory {
        NSApp.setActivationPolicy(.regular)
    }
    NSApplication.shared.activate(ignoringOtherApps: true)

    // Reuse an existing settings window if already open
    for window in NSApplication.shared.windows {
        if window.identifier?.rawValue == "settings-window" {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }

    // Always create programmatically — sendAction is unreliable on macOS 26
    let settingsView = SettingsView().environmentObject(SyncManager.shared)
    let hostingController = NSHostingController(rootView: settingsView)
    let window = NSWindow(contentViewController: hostingController)
    window.identifier = NSUserInterfaceItemIdentifier("settings-window")
    window.title = "Settings"
    window.setContentSize(NSSize(width: 750, height: 700))
    window.styleMask = [.titled, .closable, .resizable]
    window.minSize = NSSize(width: 650, height: 550)
    window.center()
    window.makeKeyAndOrderFront(nil)
}

struct ContentView: View {
    @EnvironmentObject var syncManager: SyncManager
    @State private var selectedTab = 0
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

    var body: some View {
        mainContent
            .frame(minWidth: 600, minHeight: 500)
            .alert("Error", isPresented: $syncManager.showError) {
                Button("OK") { }
            } message: {
                Text(syncManager.errorMessage)
            }
            .sheet(isPresented: $showOnboarding) {
                OnboardingView(isPresented: $showOnboarding)
                    .environmentObject(syncManager)
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        if !syncManager.hasDestinationAccess {
            legacyShell { PermissionRequestView() }
        } else if syncManager.config.vaultPath.isEmpty {
            legacyShell { SetupWizardView() }
        } else {
            dashboardView
        }
    }

    /// Wraps non-dashboard views with the header (always legacy style for these)
    private func legacyShell<V: View>(@ViewBuilder content: () -> V) -> some View {
        VStack(spacing: 0) {
            HeaderView()
            Divider()
            content()
        }
    }

    @ViewBuilder
    private var dashboardView: some View {
        if #available(macOS 26, *) {
            ModernDashboardView()
        } else {
            VStack(spacing: 0) {
                HeaderView()
                Divider()
                MainDashboardView()
            }
        }
    }
}

// MARK: - Modern Dashboard (macOS 26+ / Liquid Glass)

@available(macOS 26, *)
struct ModernDashboardView: View {
    @EnvironmentObject var syncManager: SyncManager
    @State private var showResetConfirmation = false

    var body: some View {
        NavigationSplitView {
            // Sidebar — gets automatic floating glass on Tahoe
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    syncStatusSection
                    configurationSection

                    Spacer(minLength: 20)

                    actionButtons
                }
                .padding()
            }
            .navigationTitle("Remindian")
            .frame(minWidth: 260, idealWidth: 280)
        } detail: {
            // Detail pane — Settings + Activity in unified tabs
            TabView {
                GeneralSettingsView()
                    .tabItem { Label("General", systemImage: "gear") }

                ListMappingsView()
                    .tabItem { Label("Mappings", systemImage: "arrow.triangle.swap") }

                if syncManager.config.taskSourceType == .taskNotes {
                    TaskNotesSettingsView()
                        .tabItem { Label("TaskNotes", systemImage: "doc.text") }
                }

                AdvancedSettingsView()
                    .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }

                VStack {
                    if !syncManager.pendingConflicts.isEmpty {
                        ConflictsView()
                    } else {
                        EmptyConflictsView()
                    }
                }
                .tabItem { Label("Conflicts", systemImage: "exclamationmark.triangle") }

                SyncHistoryView()
                    .tabItem { Label("History", systemImage: "clock") }
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                syncToolbarButton
            }
            ToolbarItem(placement: .automatic) {
                if syncManager.config.dryRunMode {
                    Text("DRY RUN")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.3))
                        .cornerRadius(4)
                }
            }
        }
        .alert("Reset Sync State?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                syncManager.resetSyncState()
            }
        } message: {
            Text("This will clear all sync mappings, history, and logs. The next sync will treat all tasks as new.")
        }
    }

    // MARK: - Sidebar Sections

    private var syncStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sync Status", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
                .foregroundColor(.primary)

            if let date = syncManager.lastSyncDate {
                HStack {
                    Text("Last sync:")
                        .font(.callout)
                    Spacer()
                    Text(date, style: .relative)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }

            if let result = syncManager.lastSyncResult {
                HStack(spacing: 4) {
                    StatBadge(value: result.created, label: "Created", color: .green)
                    StatBadge(value: result.updated, label: "Updated", color: .blue)
                    StatBadge(value: result.deleted, label: "Deleted", color: .red)
                }

                if result.completionsWrittenBack > 0 {
                    Label("\(result.completionsWrittenBack) completed in Obsidian", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.purple)
                }

                if result.metadataWrittenBack > 0 {
                    Label("\(result.metadataWrittenBack) metadata written back", systemImage: "pencil.circle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                if !result.errors.isEmpty {
                    Label("\(result.errors.count) errors occurred", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Text(syncManager.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Configuration", systemImage: "gearshape")
                .font(.headline)
                .foregroundColor(.primary)

            ConfigRow(label: "Vault", value: URL(fileURLWithPath: syncManager.config.vaultPath).lastPathComponent)
            ConfigRow(label: "Auto-sync", value: syncManager.config.enableAutoSync ? "Every \(syncManager.config.syncIntervalMinutes) min" : "Disabled")
            ConfigRow(label: "Default list", value: syncManager.config.defaultList)
            ConfigRow(label: "Mappings", value: "\(syncManager.config.listMappings.count) configured")
            ConfigRow(label: "Writeback", value: syncManager.config.enableCompletionWriteback ? "Enabled" : "Disabled")
        }
        .padding()
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label("Reset Sync State", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var syncToolbarButton: some View {
        if syncManager.isSyncing {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Button(action: { syncManager.cancelSync() }) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .tint(.red)
            }
        } else {
            Button(action: {
                Task { await syncManager.performSync() }
            }) {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!syncManager.hasDestinationAccess || syncManager.config.vaultPath.isEmpty)
        }
    }

}

// MARK: - Header (Legacy — macOS 13-15)

struct HeaderView: View {
    @EnvironmentObject var syncManager: SyncManager

    var body: some View {
        HStack {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading) {
                Text("Remindian")
                    .font(.headline)

                Text("Obsidian \u{2194} Reminders")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    Text(syncManager.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if syncManager.config.dryRunMode {
                        Text("DRY RUN")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.yellow.opacity(0.3))
                            .cornerRadius(3)
                    }
                }
            }

            Spacer()

            if syncManager.isSyncing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Button(action: {
                        syncManager.cancelSync()
                    }) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                    .help("Cancel the current sync operation")
                }
            } else {
                Button(action: {
                    Task {
                        await syncManager.performSync()
                    }
                }) {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!syncManager.hasDestinationAccess || syncManager.config.vaultPath.isEmpty)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Permission Request

struct PermissionRequestView: View {
    @EnvironmentObject var syncManager: SyncManager

    private var destinationType: SyncConfiguration.TaskDestinationType {
        syncManager.config.taskDestinationType
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: iconName)
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text(titleText)
                .font(.title2)
                .fontWeight(.semibold)

            Text(descriptionText)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 400)

            if needsSettingsButton {
                Button("Open Settings") {
                    openNativeSettingsWindow()
                }
                .buttonStyle(.borderedProminent)
            } else {
                VStack(spacing: 8) {
                    Button("Grant Access") {
                        Task {
                            await syncManager.requestDestinationAccess()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Text(hintText)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }

    private var iconName: String {
        switch destinationType {
        case .appleReminders: return "checklist"
        case .calendarFeed: return "calendar.badge.plus"
        }
    }

    private var titleText: String {
        switch destinationType {
        case .appleReminders: return "Reminders Access Required"
        case .calendarFeed: return "Calendar Feed Configuration Needed"
        }
    }

    private var descriptionText: String {
        switch destinationType {
        case .appleReminders:
            return "This app needs access to your Reminders to sync tasks with Obsidian."
        case .calendarFeed:
            return "Set the output path for your .ics file in Settings > General. The file will be generated on each sync."
        }
    }

    private var hintText: String {
        switch destinationType {
        case .appleReminders:
            return "You can also grant access in System Settings \u{2192} Privacy & Security \u{2192} Reminders"
        case .calendarFeed:
            return "Subscribe to the .ics file from Apple Calendar, Google Calendar, or any CalDAV client"
        }
    }

    private var needsSettingsButton: Bool {
        switch destinationType {
        case .appleReminders:
            return false
        case .calendarFeed:
            return true
        }
    }
}

// MARK: - Setup Wizard

struct SetupWizardView: View {
    @EnvironmentObject var syncManager: SyncManager

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Welcome! Let's set up your sync.")
                .font(.title2)
                .fontWeight(.semibold)

            Text("First, select your Obsidian vault folder.")
                .foregroundColor(.secondary)

            Button("Select Obsidian Vault") {
                syncManager.selectVaultPath()
            }
            .buttonStyle(.borderedProminent)

            if !syncManager.config.vaultPath.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(syncManager.config.vaultPath)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: 400)
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Main Dashboard (Legacy — macOS 13-15)

struct MainDashboardView: View {
    @EnvironmentObject var syncManager: SyncManager
    @State private var showResetConfirmation = false

    var body: some View {
        HSplitView {
            // Left panel - Status & Quick Actions
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Sync Status") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let date = syncManager.lastSyncDate {
                            HStack {
                                Text("Last sync:")
                                Spacer()
                                Text(date, style: .relative)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let result = syncManager.lastSyncResult {
                            Divider()
                            HStack {
                                StatBadge(value: result.created, label: "Created", color: .green)
                                    .help("Tasks created in Reminders from Obsidian")
                                StatBadge(value: result.updated, label: "Updated", color: .blue)
                                    .help("Tasks updated in Reminders to match Obsidian changes")
                                StatBadge(value: result.deleted, label: "Deleted", color: .red)
                                    .help("Tasks removed from Reminders (deleted in Obsidian)")
                            }

                            if result.completionsWrittenBack > 0 {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.purple)
                                    Text("\(result.completionsWrittenBack) completed in Obsidian")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .help("Tasks marked complete in Reminders → written back to Obsidian")
                            }

                            if result.metadataWrittenBack > 0 {
                                HStack {
                                    Image(systemName: "pencil.circle.fill")
                                        .foregroundColor(.orange)
                                    Text("\(result.metadataWrittenBack) metadata written back")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .help("Date/priority/tag changes from Reminders → written back to Obsidian")
                            }

                            if !result.errors.isEmpty {
                                Divider()
                                Text("\(result.errors.count) errors occurred")
                                    .foregroundColor(.red)
                                    .font(.caption)
                                    .help("Check History tab for error details")
                            }

                            if result.isDryRun {
                                Divider()
                                HStack {
                                    Image(systemName: "eye")
                                        .foregroundColor(.yellow)
                                    Text("Dry run - no changes were made")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .help("Dry Run mode is on — disable it in Settings > Advanced")
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                GroupBox("Configuration") {
                    VStack(alignment: .leading, spacing: 8) {
                        ConfigRow(label: "Vault", value: URL(fileURLWithPath: syncManager.config.vaultPath).lastPathComponent)
                        ConfigRow(label: "Auto-sync", value: syncManager.config.enableAutoSync ? "Every \(syncManager.config.syncIntervalMinutes) min" : "Disabled")
                        ConfigRow(label: "Default list", value: syncManager.config.defaultList)
                        ConfigRow(label: "Mappings", value: "\(syncManager.config.listMappings.count) configured")
                        ConfigRow(label: "Completion writeback", value: syncManager.config.enableCompletionWriteback ? "Enabled" : "Disabled")
                    }
                    .padding(.vertical, 8)
                }

                Spacer()

                VStack(spacing: 8) {
                    Button("Reset Sync State") {
                        showResetConfirmation = true
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.red)
                }
            }
            .padding()
            .frame(minWidth: 250, maxWidth: 300)
            .alert("Reset Sync State?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    syncManager.resetSyncState()
                }
            } message: {
                Text("This will clear all sync mappings, history, and logs. The next sync will treat all tasks as new and re-create them in Reminders.")
            }

            // Right panel — Settings + Activity in unified tabs
            TabView {
                GeneralSettingsView()
                    .tabItem { Label("General", systemImage: "gear") }

                ListMappingsView()
                    .tabItem { Label("Mappings", systemImage: "arrow.triangle.swap") }

                if syncManager.config.taskSourceType == .taskNotes {
                    TaskNotesSettingsView()
                        .tabItem { Label("TaskNotes", systemImage: "doc.text") }
                }

                AdvancedSettingsView()
                    .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }

                VStack {
                    if !syncManager.pendingConflicts.isEmpty {
                        ConflictsView()
                    } else {
                        EmptyConflictsView()
                    }
                }
                .tabItem { Label("Conflicts", systemImage: "exclamationmark.triangle") }

                SyncHistoryView()
                    .tabItem { Label("History", systemImage: "clock") }
            }
            .padding()
            .frame(minWidth: 300)
        }
    }
}

// MARK: - Helper Views

struct StatBadge: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack {
            Text("\(value)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ConfigRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.callout)
    }
}

struct ConflictsView: View {
    @EnvironmentObject var syncManager: SyncManager

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("\(syncManager.pendingConflicts.count) Conflicts")
                        .font(.headline)
                    Spacer()
                }

                Text("Obsidian is the source of truth. Use 'Use Obsidian' to sync to Reminders.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(syncManager.pendingConflicts, id: \.task.id) { conflict in
                            ConflictRow(conflict: conflict)
                        }
                    }
                }
            }
            .padding()
        } label: {
            Text("Pending Conflicts")
        }
    }
}

struct ConflictRow: View {
    let conflict: SyncEngine.SyncConflict
    @EnvironmentObject var syncManager: SyncManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(conflict.task.title)
                .fontWeight(.medium)
                .lineLimit(1)

            Button("Use Obsidian Version") {
                syncManager.resolveConflict(conflict, choice: .useObsidian)
            }
            .buttonStyle(.bordered)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct EmptyConflictsView: View {
    var body: some View {
        GroupBox("Activity") {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 40))
                    .foregroundColor(.green)
                Text("No conflicts")
                    .font(.headline)
                Text("Everything is in sync!")
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SyncManager.shared)
}

