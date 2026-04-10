import SwiftUI
import SwiftData
import Combine
import EventKit

// MARK: - Hex Color

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - Dark Background

struct DarkBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#040201"), Color(hex: "#080402"), Color(hex: "#040201")],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Color(hex: "#2a180c").opacity(0.18), Color(hex: "#120904").opacity(0.08), .clear],
                center: .top, startRadius: 10, endRadius: 260
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - App View (no tab bar — state-based navigation)

struct AppView: View {
    @State private var showLogbook = false

    var body: some View {
        ZStack {
            if showLogbook {
                LogbookView(onBack: { showLogbook = false })
                    .transition(.move(edge: .trailing))
            } else {
                ChatView(onLogbook: { showLogbook = true })
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.28), value: showLogbook)
    }
}

// MARK: - Calendar Manager

class CalendarManager: ObservableObject {
    private let store = EKEventStore()
    @Published var authorized = false

    private let sydney = TimeZone(identifier: "Australia/Sydney")!

    func requestAccess() {
        if #available(iOS 17.0, *) {
            store.requestFullAccessToEvents { granted, _ in
                DispatchQueue.main.async { self.authorized = granted }
            }
        } else {
            store.requestAccess(to: .event) { granted, _ in
                DispatchQueue.main.async { self.authorized = granted }
            }
        }
    }

    /// Builds the full context string injected into every /chat request.
    func contextString() -> String {
        var cal = Calendar.current
        cal.timeZone = sydney
        let now = Date()

        let dateFmt = DateFormatter()
        dateFmt.timeZone = sydney
        dateFmt.dateFormat = "EEEE d MMM yyyy"
        let dateStr = dateFmt.string(from: now)

        let timeFmt = DateFormatter()
        timeFmt.timeZone = sydney
        timeFmt.dateFormat = "h:mm a zzz"
        let timeStr = timeFmt.string(from: now)

        let weekNum = cal.component(.weekOfYear, from: now)
        let hour    = cal.component(.hour,        from: now)

        // Time-of-day label
        let timeOfDay: String
        switch hour {
        case 6..<12:  timeOfDay = "morning"
        case 12..<18: timeOfDay = "afternoon"
        case 18..<22: timeOfDay = "evening"
        default:      timeOfDay = "night"
        }

        // Time remaining until midnight (Sydney)
        let tomorrow      = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now)!)
        let secondsLeft   = max(0, Int(tomorrow.timeIntervalSince(now)))
        let hoursLeft     = secondsLeft / 3600
        let minsLeft      = (secondsLeft % 3600) / 60

        // Build the time-awareness segment
        let timeAwareness: String
        if hour >= 22 {
            // Late night: collapse into a single note
            if hoursLeft == 0 {
                timeAwareness = "late night — tomorrow starts in \(minsLeft) mins"
            } else {
                let minPart = minsLeft > 0 ? " \(minsLeft) mins" : ""
                timeAwareness = "late night — tomorrow starts in \(hoursLeft) hrs\(minPart)"
            }
        } else {
            let timeLeft: String
            if secondsLeft < 3600 {
                timeLeft = "\(minsLeft) mins left in day"
            } else if minsLeft == 0 {
                timeLeft = "\(hoursLeft) hrs left in day"
            } else {
                timeLeft = "\(hoursLeft) hrs \(minsLeft) mins left in day"
            }
            timeAwareness = "\(timeOfDay) · \(timeLeft)"
        }

        var ctx = "[Context: \(dateStr) · \(timeStr) · Week \(weekNum) · \(timeAwareness)"

        if authorized {
            let windowStart = cal.date(byAdding: .day, value: -7,  to: now)!
            let windowEnd   = cal.date(byAdding: .day, value:  30, to: now)!
            let predicate   = store.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: nil)
            let events      = store.events(matching: predicate)

            if events.isEmpty {
                ctx += " · Calendar: No events"
            } else {
                let evtFmt = DateFormatter()
                evtFmt.timeZone = sydney
                evtFmt.dateFormat = "d MMM h:mm a"
                let eventList = events.map { evt -> String in
                    let s = evtFmt.string(from: evt.startDate)
                    let e = evtFmt.string(from: evt.endDate)
                    return "\(evt.title ?? "Untitled") (\(s)–\(e))"
                }.joined(separator: "; ")
                ctx += " · Calendar: \(eventList)"
            }
        } else {
            ctx += " · Calendar: not authorised"
        }

        ctx += "]"
        return ctx
    }

    /// Creates an EKEvent on the user's default calendar.
    func createEvent(title: String, start: Date, end: Date, notes: String?) {
        guard authorized else { return }
        let event = EKEvent(eventStore: store)
        event.title    = title
        event.startDate = start
        event.endDate   = end
        event.notes    = notes
        event.calendar = store.defaultCalendarForNewEvents
        try? store.save(event, span: .thisEvent)
    }
}

// MARK: - Message

struct Message: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isUser: Bool
}

// MARK: - Scroll Tracking

private struct BottomAnchorOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Presence Glow

struct PresenceGlow: View {
    @State private var breathing = false
    var body: some View {
        ZStack {
            Circle().fill(Color(hex: "#c8956a")).frame(width: 200, height: 200).blur(radius: 70)
                .opacity(breathing ? 0.22 : 0.06)
            Circle().fill(Color(hex: "#c8956a")).frame(width: 100, height: 100).blur(radius: 35)
                .opacity(breathing ? 0.42 : 0.15)
            Circle().fill(Color(hex: "#c8956a")).frame(width: 36, height: 36).blur(radius: 12)
                .opacity(breathing ? 0.65 : 0.30)
            Circle().fill(Color(hex: "#d4a878")).frame(width: 7, height: 7).opacity(0.9)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) { breathing = true }
        }
    }
}

// MARK: - Thinking Dots

struct ThinkingDots: View {
    @State private var phase = 0
    let timer = Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Color(hex: "#c88a52")).frame(width: 5, height: 5)
                    .opacity(phase == i ? 1.0 : 0.22)
                    .animation(.easeInOut(duration: 0.22), value: phase)
            }
        }
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: Message
    @State private var visible = false
    var body: some View {
        HStack(alignment: .bottom) {
            if message.isUser { Spacer(minLength: 46) }
            Text(message.text)
                .font(.custom("Cormorant Garamond", size: 18))
                .fontWeight(.light)
                .italic(message.isUser)
                // Contrast-bumped: SENSEI #f2cc90, user #f8e4cc
                .foregroundColor(message.isUser ? Color(hex: "#f8e4cc") : Color(hex: "#f2cc90"))
                .lineSpacing(5)
                .multilineTextAlignment(message.isUser ? .trailing : .leading)
                .frame(maxWidth: 255, alignment: message.isUser ? .trailing : .leading)
                .opacity(visible ? 1 : 0)
                .offset(y: visible ? 0 : 6)
                .onAppear { withAnimation(.easeOut(duration: 0.22)) { visible = true } }
            if !message.isUser { Spacer(minLength: 46) }
        }
    }
}

// MARK: - Time Divider

struct TimeDivider: View {
    let label: String
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color(hex: "#23160d").opacity(0.55)).frame(height: 0.5)
            Text(label)
                .font(.custom("Cormorant Garamond", size: 11)).italic()
                .foregroundColor(Color(hex: "#b8906a")).kerning(2) // brighter
            Rectangle().fill(Color(hex: "#23160d").opacity(0.55)).frame(height: 0.5)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Nav Arrow Button

private struct NavArrow: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .light))
                .foregroundColor(Color(hex: "#c8956a").opacity(0.75))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }
}

// MARK: - Chat View

struct ChatView: View {
    let onLogbook: () -> Void

    @Environment(\.modelContext) private var modelContext
    @StateObject private var calendar = CalendarManager()
    @AppStorage("senseiSessionId") private var sessionId = UUID().uuidString

    @State private var messages: [Message] = [
        Message(text: "You are here. That is the first step. Now tell me — what did you actually do today?", isUser: false)
    ]
    @State private var inputText         = ""
    @State private var isThinking        = false
    @State private var viewportHeight: CGFloat = 0
    @State private var bottomAnchorY:   CGFloat = 0
    @State private var isNearBottom      = true
    @State private var pendingAutoScroll = true
    @FocusState private var inputFocused: Bool

    let backendURL = "https://worker-production-3a1c.up.railway.app/chat"

    var body: some View {
        ZStack {
            DarkBackground()
            VStack(spacing: 0) {
                // Top row: → arrow in top-right, nothing on left
                HStack {
                    Spacer()
                    NavArrow(systemName: "arrow.right", action: onLogbook)
                        .padding(.trailing, 8)
                }
                .padding(.top, 4)

                PresenceGlow().frame(height: 56).padding(.bottom, 4)
                chatArea.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) {
            inputBar.background(
                LinearGradient(
                    colors: [Color(hex: "#070402").opacity(0), Color(hex: "#070402").opacity(0.75), Color(hex: "#070402")],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
        .preferredColorScheme(.dark)
        .onTapGesture { inputFocused = false }
        .onAppear { calendar.requestAccess() }
    }

    // MARK: Chat scroll area

    var chatArea: some View {
        GeometryReader { outerGeo in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        TimeDivider(label: timeLabel())
                            .padding(.horizontal, 28).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(messages) { msg in
                                MessageBubble(message: msg).padding(.horizontal, 28).id(msg.id)
                            }
                            if isThinking {
                                HStack { ThinkingDots(); Spacer() }
                                    .padding(.horizontal, 28).id("thinking")
                            }
                            Color.clear.frame(height: 90)
                                .background(GeometryReader { geo in
                                    Color.clear.preference(
                                        key: BottomAnchorOffsetKey.self,
                                        value: geo.frame(in: .named("chatScroll")).minY
                                    )
                                })
                                .id("bottom-anchor")
                        }
                        .padding(.top, 8).padding(.bottom, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .coordinateSpace(name: "chatScroll")
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    viewportHeight = outerGeo.size.height
                    DispatchQueue.main.async { proxy.scrollTo("bottom-anchor", anchor: .bottom) }
                }
                .onChange(of: outerGeo.size.height) { _, h in viewportHeight = h; updateNearBottom() }
                .onPreferenceChange(BottomAnchorOffsetKey.self) { bottomAnchorY = $0; updateNearBottom() }
                .onChange(of: messages.count) { _, _ in
                    if pendingAutoScroll || isNearBottom { scrollToBottom(proxy) }
                    pendingAutoScroll = false
                }
                .onChange(of: isThinking) { _, v in
                    if v && (pendingAutoScroll || isNearBottom) { scrollToBottom(proxy) }
                }
            }
        }
    }

    // MARK: Input bar

    var inputBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color(hex: "#1a110a").opacity(0.45)).frame(height: 0.5)
            HStack(spacing: 12) {
                TextField("", text: $inputText,
                    prompt: Text("speak...")
                        .font(.system(size: 17, weight: .regular, design: .serif))
                        .foregroundColor(Color(hex: "#b08860")),  // brighter placeholder
                    axis: .vertical
                )
                .font(.system(size: 17, weight: .regular, design: .serif))
                .foregroundColor(Color(hex: "#f3e6d7"))
                .tint(Color(hex: "#d59a63"))
                .focused($inputFocused)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(.horizontal, 18).padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(hex: "#120b07").opacity(0.78)))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color(hex: "#3b2819").opacity(0.45), lineWidth: 0.7))
                .onTapGesture { pendingAutoScroll = true }
                .onSubmit { sendMessage() }

                Button(action: sendMessage) {
                    ZStack {
                        Circle().fill(Color(hex: "#120b07").opacity(0.88)).frame(width: 44, height: 44)
                            .overlay(Circle().stroke(Color(hex: "#4f3522").opacity(0.55), lineWidth: 0.7))
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(hex: "#d9a26d"))
                    }
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
                .opacity(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.34 : 1.0)
                .scaleEffect(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 1.0 : 1.015)
                .animation(.easeInOut(duration: 0.14), value: inputText.isEmpty)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)
        }
    }

    // MARK: Helpers

    func updateNearBottom() { isNearBottom = bottomAnchorY <= viewportHeight + 140 }

    func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo("bottom-anchor", anchor: .bottom) }
        }
    }

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        pendingAutoScroll = true
        inputText = ""
        inputFocused = false
        messages.append(Message(text: text, isUser: true))
        isThinking = true
        let ctx = modelContext
        let sid = sessionId
        Task { await sendToBackend(text: text, context: ctx, sessionId: sid) }
    }

    func sendToBackend(text: String, context: ModelContext, sessionId: String) async {
        guard let url = URL(string: backendURL) else { await showError("Invalid backend URL."); return }

        let calendarContext = calendar.contextString()
        var body: [String: Any] = ["message": text, "session_id": sessionId, "context": calendarContext]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { await showError("No response."); return }
            guard (200...299).contains(http.statusCode) else {
                let errBody = String(data: data, encoding: .utf8) ?? "Unknown"
                await showError("SENSEI error (\(http.statusCode)): \(errBody)"); return
            }
            let apiResponse = try JSONDecoder().decode(ChatAPIResponse.self, from: data)
            await MainActor.run {
                isThinking = false
                pendingAutoScroll = true
                messages.append(Message(text: apiResponse.reply, isUser: false))
                context.insert(ConversationHistory(role: "user",      content: text,              sessionId: sessionId))
                context.insert(ConversationHistory(role: "assistant", content: apiResponse.reply, sessionId: sessionId))
                for entry in apiResponse.logEntries {
                    persistLogEntry(entry, context: context)
                    // Calendar event creation — backend signals intent, iOS acts on it
                    if entry.table == "calendar_event", let title = entry.title,
                       let startStr = entry.startDatetime {
                        let iso = ISO8601DateFormatter()
                        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        let isoSimple = ISO8601DateFormatter()
                        if let startDate = iso.date(from: startStr) ?? isoSimple.date(from: startStr) {
                            let endDate = entry.endDatetime
                                .flatMap { iso.date(from: $0) ?? isoSimple.date(from: $0) }
                                ?? startDate.addingTimeInterval(3600)
                            calendar.createEvent(title: title, start: startDate, end: endDate, notes: entry.notes)
                        }
                    }
                }
            }
        } catch {
            await showError("Could not reach SENSEI. Check your connection.")
        }
    }

    func showError(_ text: String) async {
        await MainActor.run { isThinking = false; messages.append(Message(text: text, isUser: false)) }
    }

    func timeLabel() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        let t = f.string(from: Date()).lowercased()
        if hour < 12 { return "morning · \(t)" }
        if hour < 17 { return "afternoon · \(t)" }
        return "evening · \(t)"
    }
}

// MARK: - Logbook View

struct LogbookView: View {
    let onBack: () -> Void

    @Query(sort: \ProgressLog.date,      order: .reverse) private var progressLogs:  [ProgressLog]
    @Query(sort: \Commitment.createdAt,  order: .reverse) private var commitments:   [Commitment]
    @Query(sort: \CareerEntry.date,      order: .reverse) private var careerEntries: [CareerEntry]
    @Query(sort: \PatternJournal.week,   order: .reverse) private var patterns:      [PatternJournal]

    var body: some View {
        ZStack {
            DarkBackground()
            VStack(spacing: 0) {
                // Top row: ← arrow in top-left, no label
                HStack {
                    NavArrow(systemName: "arrow.left", action: onBack)
                        .padding(.leading, 8)
                    Spacer()
                }
                .padding(.top, 4)

                summaryBar

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        LogbookSection(title: "PROGRESS", isEmpty: progressLogs.isEmpty,
                                       emptyText: "Chat with SENSEI to start logging activity.") {
                            ForEach(Array(progressLogs.prefix(30))) { ProgressRow(log: $0) }
                        }
                        LogbookSection(title: "COMMITMENTS", isEmpty: commitments.isEmpty,
                                       emptyText: "No commitments recorded yet.") {
                            ForEach(Array(commitments.prefix(20))) { CommitmentRow(commitment: $0) }
                        }
                        LogbookSection(title: "CAREER", isEmpty: careerEntries.isEmpty,
                                       emptyText: "No career events logged yet.") {
                            ForEach(Array(careerEntries.prefix(20))) { CareerRow(entry: $0) }
                        }
                        LogbookSection(title: "PATTERNS", isEmpty: patterns.isEmpty,
                                       emptyText: "No patterns recorded yet.") {
                            ForEach(Array(patterns.prefix(10))) { PatternRow(pattern: $0) }
                        }
                        Color.clear.frame(height: 32)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Pinned summary bar

    private var summaryBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SummaryCell(value: "\(weeklyPoints)", label: "pts · week")
                SummaryCell(value: "$\(walletBalance)", label: "wallet")
                SummaryCell(value: "\(streakDays)", label: "day streak")
            }
            .padding(.vertical, 12)
            .background(Color(hex: "#060301").opacity(0.95))
            Rectangle().fill(Color(hex: "#1a100a").opacity(0.7)).frame(height: 0.5)
        }
    }

    // MARK: Computed stats

    private var weeklyPoints: Int {
        let start = weekStart()
        return progressLogs.filter { $0.date >= start }.reduce(0) { $0 + $1.points }
    }

    private var walletBalance: Int {
        let start = weekStart()
        return progressLogs.filter { $0.date >= start }
            .max(by: { $0.date < $1.date })?.rewardWallet ?? 0
    }

    private var streakDays: Int {
        let cal = Calendar.current
        let uniqueDays = Set(progressLogs.map { cal.startOfDay(for: $0.date) })
        var streak = 0
        var day = cal.startOfDay(for: .now)
        while uniqueDays.contains(day) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    private func weekStart() -> Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
    }
}

// MARK: - Summary Cell

private struct SummaryCell: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.custom("Cormorant Garamond", size: 28)).fontWeight(.light)
                .foregroundColor(Color(hex: "#f2cc90"))
            Text(label)
                .font(.custom("Cormorant Garamond", size: 11)).italic()
                .foregroundColor(Color(hex: "#a07848")).kerning(1.5)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Logbook Section

private struct LogbookSection<Content: View>: View {
    let title: String
    let isEmpty: Bool
    let emptyText: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.custom("Cormorant Garamond", size: 10)).italic()
                    .foregroundColor(Color(hex: "#a07848")).kerning(3)  // brighter
                Rectangle().fill(Color(hex: "#1e1008").opacity(0.7)).frame(height: 0.5)
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 12)

            if isEmpty {
                Text(emptyText)
                    .font(.custom("Cormorant Garamond", size: 14)).italic()
                    .foregroundColor(Color(hex: "#7a5840"))  // brighter
                    .padding(.horizontal, 24).padding(.bottom, 8)
            } else {
                content()
            }
        }
    }
}

// MARK: - Progress Row

private struct ProgressRow: View {
    let log: ProgressLog

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(log.points >= 0 ? "+\(log.points)" : "\(log.points)")
                .font(.custom("Cormorant Garamond", size: 15)).fontWeight(.medium)
                .foregroundColor(log.points >= 0 ? Color(hex: "#8fbb72") : Color(hex: "#bb7272"))
                .frame(width: 40, alignment: .trailing)
            Rectangle().fill(Color(hex: "#2a1a0e")).frame(width: 0.5, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(log.action)
                    .font(.custom("Cormorant Garamond", size: 16)).fontWeight(.light)
                    .foregroundColor(Color(hex: "#eccc90")).lineLimit(2)  // brighter
                HStack(spacing: 6) {
                    Text(log.category.uppercased())
                        .font(.custom("Cormorant Garamond", size: 10)).italic()
                        .foregroundColor(Color(hex: "#a07848")).kerning(1.5)  // brighter
                    Text("·").foregroundColor(Color(hex: "#6a4a30"))
                    Text(shortDate(log.date))
                        .font(.custom("Cormorant Garamond", size: 11)).italic()
                        .foregroundColor(Color(hex: "#806040"))  // brighter
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f.string(from: date)
    }
}

// MARK: - Commitment Row

private struct CommitmentRow: View {
    let commitment: Commitment

    private var metLabel: String {
        switch commitment.met {
        case "Yes": return "✓"
        case "No":  return "✗"
        default:    return "·"
        }
    }
    private var metColor: Color {
        switch commitment.met {
        case "Yes": return Color(hex: "#7fba6a")
        case "No":  return Color(hex: "#ba6a6a")
        default:    return Color(hex: "#a07848")  // brighter neutral
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(metLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(metColor)
                .frame(width: 22, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(commitment.commitmentMade)
                    .font(.custom("Cormorant Garamond", size: 16)).fontWeight(.light)
                    .foregroundColor(Color(hex: "#eccc90")).lineLimit(3)  // brighter
                Text("Week \(commitment.week)")
                    .font(.custom("Cormorant Garamond", size: 11)).italic()
                    .foregroundColor(Color(hex: "#806040"))  // brighter
            }
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
    }
}

// MARK: - Career Row

private struct CareerRow: View {
    let entry: CareerEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(typeGlyph(entry.eventType))
                .font(.system(size: 14))
                .frame(width: 22, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.custom("Cormorant Garamond", size: 16)).fontWeight(.light)
                    .foregroundColor(Color(hex: "#eccc90")).lineLimit(2)  // brighter
                HStack(spacing: 6) {
                    Text(entry.eventType.uppercased())
                        .font(.custom("Cormorant Garamond", size: 10)).italic()
                        .foregroundColor(Color(hex: "#a07848")).kerning(1.5)  // brighter
                    if let outcome = entry.outcome, !outcome.isEmpty {
                        Text("·").foregroundColor(Color(hex: "#6a4a30"))
                        Text(outcome)
                            .font(.custom("Cormorant Garamond", size: 12)).italic()
                            .foregroundColor(Color(hex: "#9a7558")).lineLimit(1)  // brighter
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
    }

    private func typeGlyph(_ type: String) -> String {
        switch type {
        case "Hackathons":   return "⚡"
        case "Application":  return "📄"
        case "Connection":   return "🤝"
        case "Volunteer":    return "🌱"
        default:             return "◇"
        }
    }
}

// MARK: - Pattern Row

private struct PatternRow: View {
    let pattern: PatternJournal

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Rectangle()
                .fill(Color(hex: "#2a1a0e"))
                .frame(width: 1)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 8) {
                Text("Week \(pattern.week)")
                    .font(.custom("Cormorant Garamond", size: 13)).italic()
                    .foregroundColor(Color(hex: "#a07848")).kerning(1)  // brighter

                if let p = pattern.patternsNoticed, !p.isEmpty {
                    PatternLine(label: "Noticed", text: p)
                }
                if let b = pattern.breakthroughs, !b.isEmpty {
                    PatternLine(label: "Breakthrough", text: b)
                }
                if let e = pattern.excusesUsed, !e.isEmpty {
                    PatternLine(label: "Excuses", text: e)
                }
            }
        }
        .padding(.leading, 24).padding(.trailing, 24).padding(.vertical, 12)
    }
}

private struct PatternLine: View {
    let label: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.custom("Cormorant Garamond", size: 9)).italic()
                .foregroundColor(Color(hex: "#806040")).kerning(2)  // brighter
            Text(text)
                .font(.custom("Cormorant Garamond", size: 15)).fontWeight(.light)
                .foregroundColor(Color(hex: "#e8c080")).lineLimit(5)  // brighter
        }
    }
}

// MARK: - Preview

#Preview { AppView() }
