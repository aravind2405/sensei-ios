import Foundation
import SwiftData

// MARK: - SwiftData Models

@Model final class StudySession {
    var id: UUID
    var topic: String
    var phase: String?
    var objective: String?
    var sessionResult: String?
    var notes: String?
    var status: String
    var completed: Bool
    var date: Date
    var createdAt: Date

    init(id: UUID = UUID(), topic: String, phase: String? = nil,
         objective: String? = nil, sessionResult: String? = nil,
         notes: String? = nil, status: String = "Not Started",
         completed: Bool = false, date: Date = .now, createdAt: Date = .now) {
        self.id = id; self.topic = topic; self.phase = phase
        self.objective = objective; self.sessionResult = sessionResult
        self.notes = notes; self.status = status
        self.completed = completed; self.date = date; self.createdAt = createdAt
    }
}

@Model final class ProgressLog {
    var id: UUID
    var action: String
    var category: String
    var points: Int
    var weeklyTotal: Int
    var rewardWallet: Int
    var notes: String?
    var date: Date

    init(id: UUID = UUID(), action: String, category: String,
         points: Int, weeklyTotal: Int = 0, rewardWallet: Int = 0,
         notes: String? = nil, date: Date = .now) {
        self.id = id; self.action = action; self.category = category
        self.points = points; self.weeklyTotal = weeklyTotal
        self.rewardWallet = rewardWallet; self.notes = notes; self.date = date
    }
}

@Model final class Commitment {
    var id: UUID
    var week: Int
    var commitmentMade: String
    var met: String   // "Yes" | "No" | "None"
    var notes: String?
    var createdAt: Date

    init(id: UUID = UUID(), week: Int, commitmentMade: String,
         met: String = "None", notes: String? = nil, createdAt: Date = .now) {
        self.id = id; self.week = week; self.commitmentMade = commitmentMade
        self.met = met; self.notes = notes; self.createdAt = createdAt
    }
}

@Model final class PatternJournal {
    var id: UUID
    var week: Int
    var patternsNoticed: String?
    var breakthroughs: String?
    var excusesUsed: String?
    var createdAt: Date

    init(id: UUID = UUID(), week: Int, patternsNoticed: String? = nil,
         breakthroughs: String? = nil, excusesUsed: String? = nil,
         createdAt: Date = .now) {
        self.id = id; self.week = week; self.patternsNoticed = patternsNoticed
        self.breakthroughs = breakthroughs; self.excusesUsed = excusesUsed
        self.createdAt = createdAt
    }
}

@Model final class SenseiProject {
    var id: UUID
    var name: String
    var phase: String?
    var status: String
    var githubLink: String?
    var notes: String?
    var createdAt: Date

    init(id: UUID = UUID(), name: String, phase: String? = nil,
         status: String = "Not Started", githubLink: String? = nil,
         notes: String? = nil, createdAt: Date = .now) {
        self.id = id; self.name = name; self.phase = phase
        self.status = status; self.githubLink = githubLink
        self.notes = notes; self.createdAt = createdAt
    }
}

@Model final class CareerEntry {
    var id: UUID
    var name: String
    var eventType: String   // "Events" | "Hackathons" | "Application" | "Connection" | "Volunteer"
    var date: Date
    var outcome: String?
    var notes: String?

    init(id: UUID = UUID(), name: String, eventType: String,
         date: Date = .now, outcome: String? = nil, notes: String? = nil) {
        self.id = id; self.name = name; self.eventType = eventType
        self.date = date; self.outcome = outcome; self.notes = notes
    }
}

@Model final class ConversationHistory {
    var id: UUID
    var role: String
    var content: String
    var sessionId: String
    var createdAt: Date

    init(id: UUID = UUID(), role: String, content: String,
         sessionId: String, createdAt: Date = .now) {
        self.id = id; self.role = role; self.content = content
        self.sessionId = sessionId; self.createdAt = createdAt
    }
}

// MARK: - Network Types

struct ChatAPIResponse: Codable {
    let reply: String
    let logEntries: [RawLogEntry]

    enum CodingKeys: String, CodingKey {
        case reply
        case logEntries = "log_entries"
    }
}

// Captures every field the backend can return (LogEntry with extra="allow").
struct RawLogEntry: Codable {
    // Defined fields on backend LogEntry
    let table: String?
    let action: String?
    let points: Int?
    let category: String?
    let id: String?       // UUID of existing record (updates)
    let met: String?

    // Extra fields passed through via extra="allow"
    let created: String?        // UUID of newly created record
    let updated: String?        // UUID of record that was updated
    let notes: String?

    // progress_log write result extras
    let weeklyTotal: Int?
    let wallet: Int?

    // study_sessions input fields
    let topic: String?
    let phase: String?
    let objective: String?
    let result: String?
    let status: String?
    let completed: Bool?
    let date: String?

    // commitments input fields
    let week: Int?
    let commitmentMade: String?

    // pattern_journal input fields
    let patternsNoticed: String?
    let breakthroughs: String?
    let excusesUsed: String?

    // projects input fields
    let name: String?
    let githubLink: String?

    // career_tracker input fields
    let careerType: String?
    let outcome: String?

    // calendar_event input fields
    let title: String?
    let startDatetime: String?
    let endDatetime: String?

    enum CodingKeys: String, CodingKey {
        case table, action, points, category, id, met
        case created, updated, notes
        case weeklyTotal = "weekly_total"
        case wallet
        case topic, phase, objective, result, status, completed, date
        case week
        case commitmentMade = "commitment_made"
        case patternsNoticed = "patterns_noticed"
        case breakthroughs
        case excusesUsed = "excuses_used"
        case name
        case githubLink = "github_link"
        case careerType = "type"
        case outcome
        case title
        case startDatetime = "start_datetime"
        case endDatetime = "end_datetime"
    }
}

// MARK: - Persistence

func persistLogEntry(_ entry: RawLogEntry, context: ModelContext) {
    guard let table = entry.table else { return }

    // Determine operation type
    let isCreate = entry.created != nil
    let isUpdate = entry.updated != nil || (entry.id != nil && entry.created == nil)
    guard isCreate || isUpdate else { return }   // skip reads (no created/updated)

    let isoParser: (String?) -> Date = { str in
        guard let str = str else { return .now }
        // Try full ISO8601 first, then date-only
        let fullFmt = ISO8601DateFormatter()
        if let d = fullFmt.date(from: str) { return d }
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        return dateFmt.date(from: str) ?? .now
    }

    switch table {

    case "progress_log":
        guard isCreate, let action = entry.action, let category = entry.category else { return }
        let uuid = UUID(uuidString: entry.created ?? "") ?? UUID()
        let log = ProgressLog(
            id: uuid,
            action: action,
            category: category,
            points: entry.points ?? 0,
            weeklyTotal: entry.weeklyTotal ?? 0,
            rewardWallet: entry.wallet ?? 0,
            notes: entry.notes,
            date: isoParser(entry.date)
        )
        context.insert(log)

    case "study_sessions":
        if isCreate {
            let uuid = UUID(uuidString: entry.created ?? "") ?? UUID()
            let s = StudySession(
                id: uuid,
                topic: entry.topic ?? "Study",
                phase: entry.phase,
                objective: entry.objective,
                sessionResult: entry.result,
                notes: entry.notes,
                status: entry.status ?? "Not Started",
                completed: entry.completed ?? false,
                date: isoParser(entry.date)
            )
            context.insert(s)
        } else if isUpdate, let idStr = entry.id, let uuid = UUID(uuidString: idStr) {
            let descriptor = FetchDescriptor<StudySession>(predicate: #Predicate { $0.id == uuid })
            if let existing = (try? context.fetch(descriptor))?.first {
                if let v = entry.topic { existing.topic = v }
                if let v = entry.phase { existing.phase = v }
                if let v = entry.status { existing.status = v }
                if let v = entry.completed { existing.completed = v }
                if let v = entry.notes { existing.notes = v }
            }
        }

    case "commitments":
        if isCreate {
            let uuid = UUID(uuidString: entry.created ?? "") ?? UUID()
            let weekNum = entry.week ?? Calendar.current.component(.weekOfYear, from: .now)
            let c = Commitment(
                id: uuid,
                week: weekNum,
                commitmentMade: entry.commitmentMade ?? "",
                met: entry.met ?? "None",
                notes: entry.notes
            )
            context.insert(c)
        } else if isUpdate, let idStr = entry.id, let uuid = UUID(uuidString: idStr) {
            let descriptor = FetchDescriptor<Commitment>(predicate: #Predicate { $0.id == uuid })
            if let existing = (try? context.fetch(descriptor))?.first {
                if let v = entry.met { existing.met = v }
                if let v = entry.commitmentMade { existing.commitmentMade = v }
                if let v = entry.notes { existing.notes = v }
            }
        }

    case "pattern_journal":
        let weekNum = entry.week ?? Calendar.current.component(.weekOfYear, from: .now)
        let descriptor = FetchDescriptor<PatternJournal>(predicate: #Predicate { $0.week == weekNum })
        if let existing = (try? context.fetch(descriptor))?.first {
            if let v = entry.patternsNoticed { existing.patternsNoticed = v }
            if let v = entry.breakthroughs { existing.breakthroughs = v }
            if let v = entry.excusesUsed { existing.excusesUsed = v }
        } else {
            let uuid = UUID(uuidString: entry.created ?? "") ?? UUID()
            let p = PatternJournal(
                id: uuid, week: weekNum,
                patternsNoticed: entry.patternsNoticed,
                breakthroughs: entry.breakthroughs,
                excusesUsed: entry.excusesUsed
            )
            context.insert(p)
        }

    case "projects":
        if isCreate {
            let uuid = UUID(uuidString: entry.created ?? "") ?? UUID()
            let p = SenseiProject(
                id: uuid,
                name: entry.name ?? "Project",
                phase: entry.phase,
                status: entry.status ?? "Not Started",
                githubLink: entry.githubLink,
                notes: entry.notes
            )
            context.insert(p)
        } else if isUpdate, let idStr = entry.id, let uuid = UUID(uuidString: idStr) {
            let descriptor = FetchDescriptor<SenseiProject>(predicate: #Predicate { $0.id == uuid })
            if let existing = (try? context.fetch(descriptor))?.first {
                if let v = entry.name { existing.name = v }
                if let v = entry.phase { existing.phase = v }
                if let v = entry.status { existing.status = v }
                if let v = entry.githubLink { existing.githubLink = v }
                if let v = entry.notes { existing.notes = v }
            }
        }

    case "career_tracker":
        guard isCreate else { return }
        let uuid = UUID(uuidString: entry.created ?? "") ?? UUID()
        let c = CareerEntry(
            id: uuid,
            name: entry.name ?? "Event",
            eventType: entry.careerType ?? "Events",
            date: isoParser(entry.date),
            outcome: entry.outcome,
            notes: entry.notes
        )
        context.insert(c)

    default:
        break
    }

    try? context.save()
}
