import Foundation
import EventKit

/// Unified task model that bridges Obsidian Tasks and Apple Reminders
struct SyncTask: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var priority: Priority
    var dueDate: Date?
    var startDate: Date?
    var scheduledDate: Date?
    var completedDate: Date?
    var tags: [String]
    var targetList: String? // The hashtag that determines which Reminders list to use
    var notes: String?
    var clientName: String? // Extracted from hierarchical tags (e.g., work/clients/somfy → "somfy") or file path

    // Source tracking for sync
    var obsidianSource: ObsidianSource?
    var remindersId: String?
    var lastModified: Date
    var url: URL?  // The URL field (e.g., obsidian:// link)
    
    enum Priority: Int, Codable, CaseIterable {
        case none = 0
        case low = 1
        case medium = 5
        case high = 9
        
        var obsidianEmoji: String {
            switch self {
            case .none: return ""
            case .low: return "🔽"
            case .medium: return "🔼"
            case .high: return "⏫"
            }
        }
        
        var displayName: String {
            switch self {
            case .none: return "None"
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            }
        }
        
        /// Convert from Apple Reminders priority (0 = none, 1-4 = high, 5 = medium, 6-9 = low)
        static func fromReminders(_ priority: Int) -> Priority {
            switch priority {
            case 0: return .none
            case 1...4: return .high
            case 5: return .medium
            case 6...9: return .low
            default: return .none
            }
        }
        
        /// Convert to Apple Reminders priority
        var toRemindersPriority: Int {
            switch self {
            case .none: return 0
            case .low: return 9
            case .medium: return 5
            case .high: return 1
            }
        }
    }
    
    struct ObsidianSource: Equatable, Codable {
        let filePath: String
        let lineNumber: Int
        let originalLine: String
    }
    
    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        priority: Priority = .none,
        dueDate: Date? = nil,
        startDate: Date? = nil,
        scheduledDate: Date? = nil,
        completedDate: Date? = nil,
        tags: [String] = [],
        targetList: String? = nil,
        notes: String? = nil,
        clientName: String? = nil,
        obsidianSource: ObsidianSource? = nil,
        remindersId: String? = nil,
        lastModified: Date = Date(),
        url: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.priority = priority
        self.dueDate = dueDate
        self.startDate = startDate
        self.scheduledDate = scheduledDate
        self.completedDate = completedDate
        self.tags = tags
        self.targetList = targetList
        self.notes = notes
        self.clientName = clientName
        self.obsidianSource = obsidianSource
        self.remindersId = remindersId
        self.lastModified = lastModified
        self.url = url
    }
}

// MARK: - Obsidian Tasks Format Parsing

extension SyncTask {
    /// Parse an Obsidian Tasks format line
    /// Format: - [x] Task title 📅 2024-01-15 🛫 2024-01-10 ⏫ #list-name #tag1 🔁 every week
    /// We parse EVERYTHING from Obsidian but may truncate for Reminders display
    static func fromObsidianLine(_ line: String, filePath: String, lineNumber: Int) -> SyncTask? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // Must start with a valid task checkbox: - [ ] or - [x] or - [X]
        // This explicitly rejects wikilinks like "- [[Name]]" which start with "- [["
        guard trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") else { return nil }

        // Check completion status
        let isCompleted = trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ")

        // Extract the content after checkbox (skip "- [x] " = 6 characters)
        var content = String(trimmed.dropFirst(6))
        
        // Parse dates with emojis
        let dueDate = extractDate(from: &content, emoji: "📅")
        let startDate = extractDate(from: &content, emoji: "🛫")
        let scheduledDate = extractDate(from: &content, emoji: "⏳")
        let completedDate = extractDate(from: &content, emoji: "✅")
        
        // Parse priority (handle optional FE0F variation selector)
        var priority: Priority = .none
        let priorityEmojis: [(emoji: String, level: Priority)] = [
            ("⏫", .high), ("🔼", .medium), ("🔽", .low)
        ]
        for (emoji, level) in priorityEmojis {
            let pattern = "\(emoji)\u{FE0F}?"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsRange = NSRange(content.startIndex..., in: content)
                if let match = regex.firstMatch(in: content, options: [], range: nsRange),
                   let matchRange = Range(match.range, in: content) {
                    priority = level
                    content.removeSubrange(matchRange)
                    break
                }
            }
        }
        
        // Strip recurrence markers from content before tag/title parsing
        // Case 1: Emoji-based recurrence (🔁/🔂 + optional FE0F + everything after until next emoji/tag/date)
        for recEmoji in ["🔁", "🔂"] {
            let recPattern = "\(recEmoji)\u{FE0F}?\\s*[^📅🛫⏳✅⏫🔼🔽#]*"
            if let recRegex = try? NSRegularExpression(pattern: recPattern, options: []) {
                let recRange = NSRange(content.startIndex..., in: content)
                content = recRegex.stringByReplacingMatches(in: content, options: [], range: recRange, withTemplate: "")
            }
        }
        // Case 2: Plain-text recurrence (e.g. "every month on the 1st when done")
        let plainRecPattern = "\\bevery\\s+(?:month|week|day|year|other|january|february|march|april|may|june|july|august|september|october|november|december|\\d+\\s+days?)\\b[^📅🛫⏳✅⏫🔼🔽#]*"
        if let plainRecRegex = try? NSRegularExpression(pattern: plainRecPattern, options: [.caseInsensitive]) {
            let recRange = NSRange(content.startIndex..., in: content)
            content = plainRecRegex.stringByReplacingMatches(in: content, options: [], range: recRange, withTemplate: "")
        }

        // Parse tags and find target list
        // Supports hierarchical tags like #work/clients/somfy
        // Also supports +prefix tags like +Project (#14)
        var tags: [String] = []
        var targetList: String? = nil
        let tagRegex = try? NSRegularExpression(pattern: "[#+][\\w-]+(?:/[\\w-]+)*", options: [])
        let range = NSRange(content.startIndex..., in: content)

        if let matches = tagRegex?.matches(in: content, options: [], range: range) {
            for match in matches {
                if let tagRange = Range(match.range, in: content) {
                    let tag = String(content[tagRange])
                    tags.append(tag)

                    // First top-level tag becomes the target list (convention)
                    // For "#work/clients/somfy", the target list is "work"
                    // For "+Project", the target list is "Project"
                    if targetList == nil {
                        let tagContent = String(tag.dropFirst()) // Remove # or +
                        if tagContent.contains("/") {
                            targetList = String(tagContent.split(separator: "/").first ?? Substring(tagContent))
                        } else {
                            targetList = tagContent
                        }
                    }
                }
            }
        }

        // Remove tags from content for clean title
        var title = content
        for tag in tags {
            title = title.replacingOccurrences(of: tag, with: "")
        }
        
        // Remove recurrence info from title
        // Case 1: 🔁/🔂 emoji (with optional FE0F variation selector) and everything after
        var recurrenceStripped = false
        let recurrenceEmojis = ["🔁", "🔂"]
        for emoji in recurrenceEmojis {
            let pattern = "\(emoji)\u{FE0F}?"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsRange = NSRange(title.startIndex..., in: title)
                if let match = regex.firstMatch(in: title, options: [], range: nsRange),
                   let matchRange = Range(match.range, in: title) {
                    title = String(title[..<matchRange.lowerBound])
                    recurrenceStripped = true
                    break
                }
            }
        }

        // Case 2: Plain-text recurrence rules without emoji
        // Matches patterns like "every month on the 1st when done", "every week", "every 90 days when done"
        if !recurrenceStripped {
            let plainRecurrencePattern = "\\bevery\\s+(?:month|week|day|year|other|\\d+\\s+days?)\\b.*?(?:when done)?.*$"
            if let regex = try? NSRegularExpression(pattern: plainRecurrencePattern, options: [.caseInsensitive]) {
                let nsRange = NSRange(title.startIndex..., in: title)
                if let match = regex.firstMatch(in: title, options: [], range: nsRange),
                   let matchRange = Range(match.range, in: title) {
                    title = String(title[..<matchRange.lowerBound])
                }
            }
        }
        
        title = title.trimmingCharacters(in: .whitespaces)
        
        // Clean up multiple spaces
        while title.contains("  ") {
            title = title.replacingOccurrences(of: "  ", with: " ")
        }
        
        guard !title.isEmpty else { return nil }

        // clientName is set later by ObsidianService from the note's YAML frontmatter
        return SyncTask(
            title: title,
            isCompleted: isCompleted,
            priority: priority,
            dueDate: dueDate,
            startDate: startDate,
            scheduledDate: scheduledDate,
            completedDate: completedDate,
            tags: tags,
            targetList: targetList,
            obsidianSource: ObsidianSource(
                filePath: filePath,
                lineNumber: lineNumber,
                originalLine: line
            )
        )
    }
    
    /// Parse dataview inline fields from a task line and merge into existing SyncTask.
    /// Format: `- [x] Task title [due::2024-01-15] [priority::high] [project::Shopping] [tags::work, urgent]`
    /// Also supports parenthetical syntax: `(due::2024-01-15)`
    /// This is called after `fromObsidianLine` to augment with any dataview fields found.
    static func parseDataviewFields(from line: String, into task: inout SyncTask) {
        // Match both [key::value] and (key::value) patterns
        let dvPattern = "[\\[\\(]([\\w-]+)::\\s*([^\\]\\)]+)[\\]\\)]"
        guard let regex = try? NSRegularExpression(pattern: dvPattern, options: []) else { return }

        let nsRange = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, options: [], range: nsRange)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for match in matches {
            guard match.numberOfRanges >= 3,
                  let keyRange = Range(match.range(at: 1), in: line),
                  let valueRange = Range(match.range(at: 2), in: line) else { continue }

            let key = String(line[keyRange]).lowercased().trimmingCharacters(in: .whitespaces)
            let value = String(line[valueRange]).trimmingCharacters(in: .whitespaces)

            switch key {
            case "due", "due_date", "duedate":
                if task.dueDate == nil, let date = dateFormatter.date(from: value) {
                    task.dueDate = date
                }
            case "start", "start_date", "startdate", "scheduled":
                if task.startDate == nil, let date = dateFormatter.date(from: value) {
                    task.startDate = date
                }
            case "scheduled_date", "scheduleddate":
                if task.scheduledDate == nil, let date = dateFormatter.date(from: value) {
                    task.scheduledDate = date
                }
            case "completed", "completion", "completed_date", "done":
                if task.completedDate == nil, let date = dateFormatter.date(from: value) {
                    task.completedDate = date
                }
            case "priority":
                if task.priority == .none {
                    switch value.lowercased() {
                    case "high", "highest", "1", "critical":
                        task.priority = .high
                    case "medium", "2", "normal":
                        task.priority = .medium
                    case "low", "lowest", "3":
                        task.priority = .low
                    default:
                        break
                    }
                }
            case "tags", "tag":
                // Parse comma-separated tags: "work, urgent" or "work"
                let dvTags = value.split(separator: ",").map { tag -> String in
                    let cleaned = tag.trimmingCharacters(in: .whitespaces)
                    return cleaned.hasPrefix("#") ? cleaned : "#\(cleaned)"
                }
                for dvTag in dvTags {
                    if !task.tags.contains(dvTag) {
                        task.tags.append(dvTag)
                    }
                }
                // Use first new tag as target list if not already set
                if task.targetList == nil, let firstTag = dvTags.first {
                    let tagContent = String(firstTag.dropFirst())
                    task.targetList = tagContent.contains("/")
                        ? String(tagContent.split(separator: "/").first ?? Substring(tagContent))
                        : tagContent
                }
            case "project", "list":
                // Directly set target list from project/list field
                if task.targetList == nil {
                    // Strip wikilink syntax [[Project Name]] → Project Name
                    let cleanValue = value
                        .replacingOccurrences(of: "[[", with: "")
                        .replacingOccurrences(of: "]]", with: "")
                    task.targetList = cleanValue
                }
            default:
                break
            }
        }

        // Clean dataview fields from the title
        let cleanPattern = "\\s*[\\[\\(][\\w-]+::\\s*[^\\]\\)]+[\\]\\)]"
        if let cleanRegex = try? NSRegularExpression(pattern: cleanPattern, options: []) {
            let titleRange = NSRange(task.title.startIndex..., in: task.title)
            task.title = cleanRegex.stringByReplacingMatches(in: task.title, range: titleRange, withTemplate: "")
                .trimmingCharacters(in: .whitespaces)
        }
    }

    /// Convert task back to Obsidian Tasks format
    func toObsidianLine() -> String {
        var parts: [String] = []
        
        // Checkbox
        let checkbox = isCompleted ? "- [x]" : "- [ ]"
        parts.append(checkbox)
        
        // Title
        parts.append(title)
        
        // Priority emoji
        if priority != .none {
            parts.append(priority.obsidianEmoji)
        }
        
        // Start date
        if let startDate = startDate {
            parts.append("🛫 \(formatDate(startDate))")
        }
        
        // Scheduled date
        if let scheduledDate = scheduledDate {
            parts.append("⏳ \(formatDate(scheduledDate))")
        }
        
        // Due date
        if let dueDate = dueDate {
            parts.append("📅 \(formatDate(dueDate))")
        }
        
        // Completed date
        if let completedDate = completedDate, isCompleted {
            parts.append("✅ \(formatDate(completedDate))")
        }
        
        // Add tags - targetList is already in tags if it was parsed from Obsidian
        // Only add targetList as tag if it's not already in the tags array
        var allTags = tags
        if let targetList = targetList {
            let targetTag = "#\(targetList)"
            if !allTags.contains(targetTag) && !allTags.contains(where: { $0.lowercased() == targetTag.lowercased() }) {
                allTags.insert(targetTag, at: 0)
            }
        }
        
        // Add all unique tags
        for tag in allTags {
            if !parts.contains(tag) {
                parts.append(tag)
            }
        }
        
        return parts.joined(separator: " ")
    }
    
    // MARK: - Helper Methods
    
    private static func extractDate(from content: inout String, emoji: String) -> Date? {
        // Handle optional FE0F variation selector that some editors/keyboards insert after emoji
        let pattern = "\(emoji)\u{FE0F}?\\s*(\\d{4}-\\d{2}-\\d{2})"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        
        let range = NSRange(content.startIndex..., in: content)
        guard let match = regex.firstMatch(in: content, options: [], range: range),
              let dateRange = Range(match.range(at: 1), in: content) else { return nil }
        
        let dateString = String(content[dateRange])
        
        // Remove the matched portion from content
        if let fullRange = Range(match.range, in: content) {
            content.removeSubrange(fullRange)
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - EKReminder Conversion

extension SyncTask {
    /// Create SyncTask from Apple Reminder
    static func fromReminder(_ reminder: EKReminder, listName: String) -> SyncTask {
        var tags: [String] = []
        
        // Parse tags from notes if present (supports both # and + prefixes)
        if let notes = reminder.notes {
            let tagRegex = try? NSRegularExpression(pattern: "[#+][\\w-]+(?:/[\\w-]+)*", options: [])
            let range = NSRange(notes.startIndex..., in: notes)
            if let matches = tagRegex?.matches(in: notes, options: [], range: range) {
                for match in matches {
                    if let tagRange = Range(match.range, in: notes) {
                        tags.append(String(notes[tagRange]))
                    }
                }
            }
        }
        
        // Get start date from reminder's start date component
        var startDate: Date? = nil
        if let startComponents = reminder.startDateComponents {
            startDate = Calendar.current.date(from: startComponents)
        }
        
        return SyncTask(
            title: reminder.title ?? "Untitled",
            isCompleted: reminder.isCompleted,
            priority: Priority.fromReminders(Int(reminder.priority)),
            dueDate: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
            startDate: startDate,
            completedDate: reminder.completionDate,
            tags: tags,
            targetList: listName,
            notes: reminder.notes,
            remindersId: reminder.calendarItemIdentifier,
            lastModified: reminder.lastModifiedDate ?? Date(),
            url: reminder.url
        )
    }
    
    /// Apply task properties to an EKReminder.
    /// Title is clean (no hashtags). Client name added in notes for work tasks.
    func applyToReminder(_ reminder: EKReminder, includeDueTime: Bool = false, addTaskLink: Bool = false, vaultPath: String = "") {
        reminder.title = title
        reminder.isCompleted = isCompleted
        reminder.priority = priority.toRemindersPriority

        if let dueDate = dueDate {
            if includeDueTime {
                reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            } else {
                // Only date, no time - this creates an all-day reminder
                reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: dueDate)
            }
        } else {
            reminder.dueDateComponents = nil
        }

        if let startDate = startDate {
            if includeDueTime {
                reminder.startDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: startDate)
            } else {
                reminder.startDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: startDate)
            }
        } else {
            reminder.startDateComponents = nil
        }

        // Build notes: client name + tags + task link
        // (EventKit has no native tag API, so tags are stored in notes for visibility)
        var noteParts: [String] = []

        if let client = clientName, !client.isEmpty {
            noteParts.append("Client: \(client)")
        }

        if !tags.isEmpty {
            noteParts.append("Tags: \(tags.joined(separator: " "))")
        }

        // Add obsidian:// link to the reminder's URL field and notes
        if addTaskLink, let source = obsidianSource, !vaultPath.isEmpty {
            let vaultName = URL(fileURLWithPath: vaultPath).lastPathComponent
            let filePath = source.filePath.hasPrefix("/") ? String(source.filePath.dropFirst()) : source.filePath
            let encodedVault = vaultName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? vaultName
            let encodedFile = filePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filePath
            let obsidianURL = "obsidian://open?vault=\(encodedVault)&file=\(encodedFile)"

            // Set the URL field (clickable in Reminders.app and GoodTask)
            reminder.url = URL(string: obsidianURL)

            // Also keep in notes as fallback for apps that don't show the URL field
            noteParts.append(obsidianURL)
        }

        if noteParts.isEmpty {
            reminder.notes = notes?.trimmingCharacters(in: .whitespaces)
        } else {
            reminder.notes = noteParts.joined(separator: "\n")
        }

        if isCompleted {
            reminder.completionDate = completedDate ?? Date()
        }
    }
}
