import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var syncManager: SyncManager

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)

            ListMappingsView()
                .tabItem {
                    Label("Mappings", systemImage: "arrow.triangle.swap")
                }
                .tag(1)

            if syncManager.config.taskSourceType == .taskNotes {
                TaskNotesSettingsView()
                    .tabItem {
                        Label("TaskNotes", systemImage: "doc.text")
                    }
                    .tag(3)
            }

            AdvancedSettingsView()
                .tabItem {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                }
                .tag(2)
        }
        .frame(minWidth: 700, idealWidth: 800, minHeight: 600, idealHeight: 750)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @EnvironmentObject var syncManager: SyncManager

    var body: some View {
        ScrollView {
            Form {
                // Source & Destination — primary choice, belongs in General
                Section {
                    Picker("Task Source", selection: $syncManager.config.taskSourceType) {
                        ForEach(SyncConfiguration.TaskSourceType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .onChange(of: syncManager.config.taskSourceType) { _ in
                        syncManager.updateSourceAndDestination()
                    }

                    Picker("Sync To", selection: $syncManager.config.taskDestinationType) {
                        Label("Apple Reminders", systemImage: "checklist")
                            .tag(SyncConfiguration.TaskDestinationType.appleReminders)
                        Label("Calendar Feed", systemImage: "calendar")
                            .tag(SyncConfiguration.TaskDestinationType.calendarFeed)
                    }
                    .onChange(of: syncManager.config.taskDestinationType) { _ in
                        syncManager.updateSourceAndDestination()
                    }

                    if syncManager.config.taskDestinationType == .calendarFeed {
                        HStack {
                            Text("Output path:")
                                .foregroundColor(.secondary)
                            TextField("~/Documents/remindian-tasks.ics", text: $syncManager.config.calendarFeedOutputPath)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 250)
                        }
                        .padding(.leading, 20)

                        HStack {
                            Text("Calendar name:")
                                .foregroundColor(.secondary)
                            TextField("Remindian Tasks", text: $syncManager.config.calendarFeedName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                        }
                        .padding(.leading, 20)

                        Text("Generates a subscribable .ics file with your tasks as VTODO entries. Subscribe to it from Apple Calendar, Google Calendar, or any CalDAV client.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 20)
                    }
                } header: {
                    Text("Source & Destination")
                }

                Section {
                    HStack {
                        TextField("Vault Path", text: $syncManager.config.vaultPath)
                            .disabled(true)

                        Button("Browse...") {
                            syncManager.selectVaultPath()
                        }
                    }

                    if !syncManager.config.vaultPath.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Vault configured")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Obsidian Vault")
                }

                // Obsidian → Reminders settings (#24 — separate sync directions)
                Section {
                    Toggle("Enable automatic sync", isOn: $syncManager.config.enableAutoSync)

                    if syncManager.config.enableAutoSync {
                        Picker("Sync interval", selection: $syncManager.config.syncIntervalMinutes) {
                            Text("1 minute").tag(1)
                            Text("5 minutes").tag(5)
                            Text("15 minutes").tag(15)
                            Text("30 minutes").tag(30)
                            Text("1 hour").tag(60)
                        }
                    }

                    Toggle("Sync on app launch", isOn: $syncManager.config.syncOnLaunch)

                    Toggle("Watch vault for changes (real-time sync)", isOn: $syncManager.config.enableFileWatcher)
                        .onChange(of: syncManager.config.enableFileWatcher) { _ in
                            syncManager.updateFileWatcher()
                        }
                        .help("Automatically sync when markdown files in your vault are modified")

                    Toggle("Include time in due dates", isOn: $syncManager.config.includeDueTime)
                        .help("When disabled, reminders will be all-day tasks without a specific time")
                } header: {
                    Label("Obsidian \u{2192} \(syncManager.config.taskDestinationType.displayName)", systemImage: "arrow.right")
                }

                // Destination → Obsidian settings (#24 — separate sync directions)
                Section {
                    Toggle("Sync completions back", isOn: $syncManager.config.enableCompletionWriteback)
                        .help("Marking a task complete in \(syncManager.config.taskDestinationType.displayName) will update the checkbox and add a completion date in Obsidian")

                    Toggle("Sync due date changes back", isOn: $syncManager.config.enableDueDateWriteback)
                        .help("Changing a due date in \(syncManager.config.taskDestinationType.displayName) will update the \u{1F4C5} date in Obsidian")

                    Toggle("Sync start date changes back", isOn: $syncManager.config.enableStartDateWriteback)
                        .help("Changing a start date in \(syncManager.config.taskDestinationType.displayName) will update the \u{1F6EB} date in Obsidian")

                    Toggle("Sync priority changes back", isOn: $syncManager.config.enablePriorityWriteback)
                        .help("Changing priority in \(syncManager.config.taskDestinationType.displayName) will update the priority emoji in Obsidian")

                    Toggle("Sync tag changes back", isOn: $syncManager.config.enableTagWriteback)
                        .help("Tag changes in \(syncManager.config.taskDestinationType.displayName) will update #tags in Obsidian")

                    Toggle("Write new \(syncManager.config.taskDestinationType.displayName) tasks to Obsidian", isOn: $syncManager.config.enableNewTaskWriteback)
                        .help("New tasks created in \(syncManager.config.taskDestinationType.displayName) will be appended to an inbox file in your vault")

                    if syncManager.config.enableNewTaskWriteback {
                        HStack {
                            Text("Inbox file:")
                                .foregroundColor(.secondary)
                            TextField("Inbox.md", text: $syncManager.config.inboxFilePath)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                        }
                        .padding(.leading, 20)
                    }

                    if syncManager.config.enableCompletionWriteback || syncManager.config.enableDueDateWriteback || syncManager.config.enableStartDateWriteback || syncManager.config.enablePriorityWriteback || syncManager.config.enableTagWriteback || syncManager.config.enableNewTaskWriteback {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("Writeback is active. Your Obsidian files will be modified. Backups are created automatically.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Label("\(syncManager.config.taskDestinationType.displayName) \u{2192} Obsidian (Writeback)", systemImage: "arrow.left")
                }

                Section {
                    Toggle("Enable notifications", isOn: $syncManager.config.enableNotifications)
                        .help("Show macOS notifications for sync errors and first sync completion")
                } header: {
                    Text("Notifications")
                }

                Section {
                    Picker("Default list", selection: $syncManager.config.defaultList) {
                        ForEach(syncManager.availableLists, id: \.self) { list in
                            Text(list).tag(list)
                        }
                    }
                    .onAppear {
                        syncManager.refreshLists()
                    }

                    Button("Refresh Lists") {
                        syncManager.refreshLists()
                    }
                    .font(.caption)

                    if syncManager.config.taskSourceType == .taskNotes && syncManager.config.taskNotesListField != "tags" {
                        Text("Tasks with a \(syncManager.config.taskNotesListField) field will go to that list instead. This is the fallback for tasks without one.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Tasks with a matching tag mapping go to that list. This is the fallback for untagged tasks.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Default List")
                }

                Section {
                    Toggle("Launch at login", isOn: $syncManager.config.launchAtLogin)
                        .onChange(of: syncManager.config.launchAtLogin) { newValue in
                            syncManager.updateLaunchAtLogin(newValue)
                        }
                        .help("Automatically start Remindian when you log in")

                    Toggle("Hide dock icon", isOn: $syncManager.config.hideDockIcon)
                        .onChange(of: syncManager.config.hideDockIcon) { _ in
                            syncManager.updateDockIconVisibility()
                        }
                        .help("App will only appear in the menu bar")

                    Toggle("Force dark mode", isOn: $syncManager.config.forceDarkIcon)
                        .onChange(of: syncManager.config.forceDarkIcon) { _ in
                            syncManager.updateAppIcon()
                        }
                        .help("Forces the app into dark mode regardless of system setting")

                    Toggle("Global sync hotkey", isOn: $syncManager.config.globalHotKeyEnabled)
                        .onChange(of: syncManager.config.globalHotKeyEnabled) { _ in
                            syncManager.updateHotKey()
                        }
                        .help("Register a global keyboard shortcut to trigger sync from any app")

                    if syncManager.config.globalHotKeyEnabled {
                        HStack {
                            Text("Hotkey:")
                                .foregroundColor(.secondary)
                            Text(HotKeyService.describeHotKey(
                                keyCode: syncManager.config.globalHotKeyCode,
                                modifiers: syncManager.config.globalHotKeyModifiers
                            ))
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                        }
                        .padding(.leading, 20)
                    }
                } header: {
                    Text("Appearance & Shortcuts")
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: - List Mappings

struct ListMappingsView: View {
    @EnvironmentObject var syncManager: SyncManager
    @State private var newTag = ""
    @State private var newList = ""
    @State private var newFilePath = ""
    @State private var newFileList = ""
    @State private var newFolderPath = ""
    @State private var newFolderList = ""

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            // MARK: - Tag Mappings
            Text("Tag \u{2192} List Mappings")
                .font(.headline)

            Text("Tasks with #tag or +tag will sync to the mapped list")
                .font(.caption)
                .foregroundColor(.secondary)

            List {
                ForEach(Array(syncManager.config.listMappings.enumerated()), id: \.element.id) { index, mapping in
                    HStack {
                        Text(mapping.obsidianTag.hasPrefix("+") ? mapping.obsidianTag : "#\(mapping.obsidianTag)")
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)

                        Image(systemName: "arrow.right")
                            .foregroundColor(.secondary)

                        Text(mapping.remindersList)

                        Spacer()

                        Button(action: {
                            syncManager.removeListMapping(at: index)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(minHeight: 100)

            HStack {
                TextField("Tag (e.g., work or +project)", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120, maxWidth: 250)

                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)

                Picker("List", selection: $newList) {
                    Text("Select list...").tag("")
                    ForEach(syncManager.availableLists, id: \.self) { list in
                        Text(list).tag(list)
                    }
                }
                .frame(minWidth: 120, maxWidth: 200)

                Button("Add") {
                    guard !newTag.isEmpty && !newList.isEmpty else { return }
                    syncManager.addListMapping(obsidianTag: newTag, remindersList: newList)
                    newTag = ""
                    newList = ""
                }
                .disabled(newTag.isEmpty || newList.isEmpty)
            }

            Divider()

            // MARK: - File Path Mappings (#37)
            Text("File \u{2192} List Mappings")
                .font(.headline)

            Text("All tasks in the specified file will sync to the mapped list, regardless of their tags")
                .font(.caption)
                .foregroundColor(.secondary)

            List {
                ForEach(Array(syncManager.config.filePathMappings.enumerated()), id: \.element.id) { index, mapping in
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundColor(.secondary)

                        Text(mapping.filePath)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Image(systemName: "arrow.right")
                            .foregroundColor(.secondary)

                        Text(mapping.remindersList)

                        Spacer()

                        Button(action: {
                            syncManager.removeFileMapping(at: index)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(minHeight: 80)

            HStack {
                TextField("File path (e.g., Projects/Work.md)", text: $newFilePath)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 150, maxWidth: 300)

                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)

                Picker("List", selection: $newFileList) {
                    Text("Select list...").tag("")
                    ForEach(syncManager.availableLists, id: \.self) { list in
                        Text(list).tag(list)
                    }
                }
                .frame(minWidth: 120, maxWidth: 200)

                Button("Add") {
                    guard !newFilePath.isEmpty && !newFileList.isEmpty else { return }
                    syncManager.addFileMapping(filePath: newFilePath, remindersList: newFileList)
                    newFilePath = ""
                    newFileList = ""
                }
                .disabled(newFilePath.isEmpty || newFileList.isEmpty)
            }

            Text("Use the relative path from your vault root (e.g., Projects/Work.md)")
                .font(.caption2)
                .foregroundColor(.secondary)

            Divider()

            // MARK: - Folder Path Mappings (#40)
            Text("Folder \u{2192} List Mappings")
                .font(.headline)

            Text("All tasks in any file within the specified folder (and subfolders) will sync to the mapped list")
                .font(.caption)
                .foregroundColor(.secondary)

            List {
                ForEach(Array(syncManager.config.folderPathMappings.enumerated()), id: \.element.id) { index, mapping in
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.secondary)

                        Text(mapping.folderPath)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Image(systemName: "arrow.right")
                            .foregroundColor(.secondary)

                        Text(mapping.remindersList)

                        Spacer()

                        Button(action: {
                            syncManager.removeFolderMapping(at: index)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(minHeight: 80)

            HStack {
                TextField("Folder path (e.g., Projects/Work)", text: $newFolderPath)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 150, maxWidth: 300)

                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)

                Picker("List", selection: $newFolderList) {
                    Text("Select list...").tag("")
                    ForEach(syncManager.availableLists, id: \.self) { list in
                        Text(list).tag(list)
                    }
                }
                .frame(minWidth: 120, maxWidth: 200)

                Button("Add") {
                    guard !newFolderPath.isEmpty && !newFolderList.isEmpty else { return }
                    syncManager.addFolderMapping(folderPath: newFolderPath, remindersList: newFolderList)
                    newFolderPath = ""
                    newFolderList = ""
                }
                .disabled(newFolderPath.isEmpty || newFolderList.isEmpty)
            }

            Text("Use the relative folder path from your vault root. More specific folders take priority over broader ones.")
                .font(.caption2)
                .foregroundColor(.secondary)

            // Mapping priority explanation
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mapping Priority (highest to lowest):")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("1. Explicit tag mapping (#tag \u{2192} List)")
                        .font(.caption2)
                    Text("2. File path mapping (file.md \u{2192} List)")
                        .font(.caption2)
                    Text("3. Folder path mapping (folder/ \u{2192} List)")
                        .font(.caption2)
                    Text("4. Auto-capitalize tag name")
                        .font(.caption2)
                    Text("5. Default list")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
        }
        .padding()
        } // ScrollView
        .onAppear {
            syncManager.refreshLists()
        }
    }
}

// MARK: - TaskNotes Settings (#24 — separate tab with individual rows and wider fields)

struct TaskNotesSettingsView: View {
    @EnvironmentObject var syncManager: SyncManager

    var body: some View {
        ScrollView {
            Form {
                Section {
                    HStack {
                        Text("Integration:")
                            .foregroundColor(.secondary)
                        Picker("", selection: $syncManager.config.taskNotesIntegrationMode) {
                            Text("CLI (mtn)").tag("cli")
                            Text("Direct Files").tag("file")
                            Text("HTTP API").tag("http")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 280)
                    }
                    .onChange(of: syncManager.config.taskNotesIntegrationMode) { _ in
                        syncManager.updateSourceAndDestination()
                    }

                    if syncManager.config.taskNotesIntegrationMode == "cli" {
                        Text("Uses mdbase-tasknotes CLI. Works without Obsidian. Install: npm install -g mdbase-tasknotes")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Text("mtn path:")
                                .foregroundColor(.secondary)
                            TextField("/opt/homebrew/bin/mtn", text: $syncManager.config.taskNotesMtnPath)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: .infinity)
                            Button("Browse...") {
                                syncManager.selectMtnBinary()
                            }
                        }

                        if syncManager.config.taskNotesMtnPath.isEmpty {
                            Text("Select the mtn binary to grant sandbox access. Run 'which mtn' in Terminal to find its location.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("mtn configured: \(syncManager.config.taskNotesMtnPath)")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    } else if syncManager.config.taskNotesIntegrationMode == "http" {
                        Text("Uses the TaskNotes plugin HTTP API. Requires Obsidian to be open.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Text("API URL:")
                                .foregroundColor(.secondary)
                            TextField("http://localhost:8080", text: $syncManager.config.taskNotesApiUrl)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: .infinity)
                        }
                        .onChange(of: syncManager.config.taskNotesApiUrl) { _ in
                            syncManager.updateSourceAndDestination()
                        }
                    }

                    HStack {
                        Text("Tasks Folder:")
                            .foregroundColor(.secondary)
                        TextField("tasks", text: $syncManager.config.taskNotesFolder)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                    }

                    Text("Relative path within your vault where TaskNotes stores task files.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Integration")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Completed statuses")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                        TextField("done, completed, cancelled, archived, shipped", text: Binding(
                            get: { syncManager.config.taskNotesCompletedStatuses.joined(separator: ", ") },
                            set: { syncManager.config.taskNotesCompletedStatuses = $0.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty } }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        Text("Comma-separated list of status values that mean \"completed\".")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Open status")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                            TextField("open", text: $syncManager.config.taskNotesOpenStatus)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 150)
                            Text("Written when marking incomplete")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Done status")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                            TextField("done", text: $syncManager.config.taskNotesDoneStatus)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 150)
                            Text("Written when marking complete")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Status Mapping")
                }

                Section {
                    Text("Map your YAML frontmatter field names to Remindian properties. If your TaskNotes uses custom field names (e.g., \"deadline\" instead of \"due\"), configure them here.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        FieldMappingRow(label: "Title", binding: $syncManager.config.taskNotesFieldMapping.title, placeholder: "title")
                        Divider()
                        FieldMappingRow(label: "Status", binding: $syncManager.config.taskNotesFieldMapping.status, placeholder: "status")
                        Divider()
                        FieldMappingRow(label: "Priority", binding: $syncManager.config.taskNotesFieldMapping.priority, placeholder: "priority")
                        Divider()
                        FieldMappingRow(label: "Due Date", binding: $syncManager.config.taskNotesFieldMapping.due, placeholder: "due")
                        Divider()
                        FieldMappingRow(label: "Start Date", binding: $syncManager.config.taskNotesFieldMapping.scheduled, placeholder: "scheduled")
                        Divider()
                        FieldMappingRow(label: "Completed", binding: $syncManager.config.taskNotesFieldMapping.completedDate, placeholder: "completedDate")
                        Divider()
                        FieldMappingRow(label: "Tags", binding: $syncManager.config.taskNotesFieldMapping.tags, placeholder: "tags")
                        Divider()
                        FieldMappingRow(label: "Project", binding: $syncManager.config.taskNotesFieldMapping.project, placeholder: "project")
                        Divider()
                        FieldMappingRow(label: "Context", binding: $syncManager.config.taskNotesFieldMapping.context, placeholder: "context")
                    }
                } header: {
                    Text("Field Mapping")
                }

                Section {
                    HStack {
                        Text("Reminders list from:")
                            .foregroundColor(.secondary)
                        Picker("", selection: $syncManager.config.taskNotesListField) {
                            Text("Tags").tag("tags")
                            Text("Project").tag("project")
                            Text("Context").tag("context")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 250)
                    }

                    Text("Which TaskNotes field determines the Reminders list/folder. Supports wikilinks (e.g., [[My Project]] \u{2192} My Project). Tasks without a value fall back to the Default List in General.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("List/Folder Source")
                }
            }
            .formStyle(.grouped)
        }
    }
}

/// Individual field mapping row — each field on its own line with wider text input (#24)
struct FieldMappingRow: View {
    let label: String
    @Binding var binding: String
    let placeholder: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .trailing)
            TextField(placeholder, text: $binding)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Advanced Settings

struct AdvancedSettingsView: View {
    @EnvironmentObject var syncManager: SyncManager
    @State private var showResetConfirmation = false

    var body: some View {
        ScrollView {
        Form {
            Section {
                Toggle("Sync completed tasks", isOn: $syncManager.config.syncCompletedTasks)

                if syncManager.config.syncCompletedTasks {
                    HStack {
                        Text("Skip completed tasks older than:")
                            .foregroundColor(.secondary)
                        Picker("", selection: $syncManager.config.maxCompletedTaskAgeDays) {
                            Text("No limit").tag(0)
                            Text("7 days").tag(7)
                            Text("30 days").tag(30)
                            Text("90 days").tag(90)
                            Text("180 days").tag(180)
                            Text("1 year").tag(365)
                        }
                        .frame(width: 120)
                    }
                    .padding(.leading, 20)
                }

                Toggle("Add task link to Reminders", isOn: $syncManager.config.addTaskLinkToReminders)
                    .help("Adds an obsidian:// URL to the Reminders notes so you can jump to the task file")

                Toggle("Dry run mode", isOn: $syncManager.config.dryRunMode)
                    .help("Shows what would change without making any actual changes")

                if syncManager.config.dryRunMode {
                    HStack(spacing: 4) {
                        Image(systemName: "eye")
                            .foregroundColor(.yellow)
                            .font(.caption)
                        Text("Dry run is active. No changes will be made.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 20)
                }

                if syncManager.config.taskSourceType == .obsidianTasks {
                    LabeledContent {
                        TextField("e.g. #task", text: $syncManager.config.globalFilter)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                    } label: {
                        Text("Global filter")
                    }

                    Text("Only sync tasks whose line contains this text. Matches the Obsidian Tasks plugin global filter setting. Leave empty to sync all tasks.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("Parse dataview inline fields", isOn: $syncManager.config.enableDataviewFormat)
                        .help("Also read [key::value] and (key::value) metadata from task lines")

                    if syncManager.config.enableDataviewFormat {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recognized fields: due, start, scheduled, completed, priority, tags, project, list")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Example: - [ ] Buy milk [due::2025-01-15] [priority::high] [project::Shopping]")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .italic()
                            Text("Emoji-based metadata takes precedence. Dataview fields fill in any gaps.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 20)
                    }
                }
            } header: {
                Text("Sync Options")
            }

            Section {
                LabeledContent {
                    TextField("e.g. Work, Personal", text: Binding(
                        get: { syncManager.config.includedFolders.joined(separator: ", ") },
                        set: { syncManager.config.includedFolders = $0.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) } }
                    ))
                    .textFieldStyle(.roundedBorder)
                } label: {
                    Text("Only scan")
                }

                Text("Comma-separated. If set, ONLY these folders will be scanned. Leave empty to scan the entire vault.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                LabeledContent {
                    TextField(".obsidian, .git, .trash", text: Binding(
                        get: { syncManager.config.excludedFolders.joined(separator: ", ") },
                        set: { syncManager.config.excludedFolders = $0.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) } }
                    ))
                    .textFieldStyle(.roundedBorder)
                } label: {
                    Text("Exclude")
                }
            } header: {
                Text("Folder Filtering")
            }

            Section {
                LabeledContent {
                    TextField("e.g. Work, Personal", text: Binding(
                        get: { syncManager.config.syncedRemindersLists.joined(separator: ", ") },
                        set: { syncManager.config.syncedRemindersLists = $0.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty } }
                    ))
                    .textFieldStyle(.roundedBorder)
                } label: {
                    Text("Only sync lists")
                }

                LabeledContent {
                    TextField("e.g. Groceries, Shared", text: Binding(
                        get: { syncManager.config.excludedRemindersLists.joined(separator: ", ") },
                        set: { syncManager.config.excludedRemindersLists = $0.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty } }
                    ))
                    .textFieldStyle(.roundedBorder)
                } label: {
                    Text("Exclude lists")
                }
                LabeledContent {
                    TextField("e.g. Routine, SomeDay", text: Binding(
                        get: { syncManager.config.excludedTags.joined(separator: ", ") },
                        set: { syncManager.config.excludedTags = $0.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty } }
                    ))
                    .textFieldStyle(.roundedBorder)
                } label: {
                    Text("Exclude tags")
                }

                Text("Tasks with any of these tags will be skipped during sync. Enter tag names without the # prefix, separated by commas.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("\(syncManager.config.taskDestinationType.displayName) List Filtering")
            }

            Section {
                Button("Reset Sync State") {
                    showResetConfirmation = true
                }
                .foregroundColor(.red)

                Text("Clears all sync mappings, history, and logs. The next sync will treat all tasks as new.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Troubleshooting")
            }

            Section {
                Button("Open Backups Folder") {
                    if let url = FileBackupService.shared.backupDirectoryURL {
                        NSWorkspace.shared.open(url)
                    }
                }

                Button("Open Audit Log") {
                    if let url = AuditLog.shared.auditLogURL {
                        NSWorkspace.shared.open(url)
                    }
                }

                Text("Backups are created automatically before any Obsidian file modification.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Recovery")
            }
        }
        .formStyle(.grouped)
        }
        .alert("Reset Sync State?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                syncManager.resetSyncState()
            }
        } message: {
            Text("This will clear all sync mappings, history, and logs. The next sync will treat all tasks as new and re-create them in Reminders.")
        }
    }
}

// MARK: - Liquid Glass (macOS Tahoe)

/// Conditionally applies Liquid Glass effect on macOS 26+ (Tahoe).
/// Falls back to no-op on older macOS versions.
struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
        }
    }
}

struct LiquidGlassClearModifier: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.clear, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
        }
    }
}

extension View {
    /// Apply Liquid Glass with `.regular` style (opaque-ish, for navigation/chrome).
    func liquidGlass(cornerRadius: CGFloat = 12) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius))
    }

    /// Apply Liquid Glass with `.clear` style (transparent, for media-rich backgrounds).
    func liquidGlassClear(cornerRadius: CGFloat = 12) -> some View {
        modifier(LiquidGlassClearModifier(cornerRadius: cornerRadius))
    }
}

#Preview {
    SettingsView()
        .environmentObject(SyncManager.shared)
}
