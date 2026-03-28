import SwiftUI
import Combine

struct Message: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isUser: Bool
}

// MARK: - Scroll Tracking
private struct BottomAnchorOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Breathing Glow
struct PresenceGlow: View {
    @State private var breathing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#c8956a"))
                .frame(width: 110, height: 110)
                .blur(radius: 34)
                .opacity(breathing ? 0.12 : 0.04)

            Circle()
                .fill(Color(hex: "#c8956a"))
                .frame(width: 48, height: 48)
                .blur(radius: 14)
                .opacity(breathing ? 0.22 : 0.08)

            Circle()
                .fill(Color(hex: "#f0b67a"))
                .frame(width: 7, height: 7)
                .opacity(0.92)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                breathing = true
            }
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
                Circle()
                    .fill(Color(hex: "#c88a52"))
                    .frame(width: 5, height: 5)
                    .opacity(phase == i ? 1.0 : 0.22)
                    .animation(.easeInOut(duration: 0.22), value: phase)
            }
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}

// MARK: - Message View
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
                .foregroundColor(
                    message.isUser
                    ? Color(hex: "#f3dcc3")
                    : Color(hex: "#e2ba91")
                )
                .lineSpacing(5)
                .multilineTextAlignment(message.isUser ? .trailing : .leading)
                .frame(maxWidth: 255, alignment: message.isUser ? .trailing : .leading)
                .opacity(visible ? 1 : 0)
                .offset(y: visible ? 0 : 6)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.22)) {
                        visible = true
                    }
                }

            if !message.isUser { Spacer(minLength: 46) }
        }
    }
}

// MARK: - Time Divider
struct TimeDivider: View {
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color(hex: "#23160d").opacity(0.55))
                .frame(height: 0.5)

            Text(label)
                .font(.custom("Cormorant Garamond", size: 11))
                .italic()
                .foregroundColor(Color(hex: "#8d6748"))
                .kerning(2)

            Rectangle()
                .fill(Color(hex: "#23160d").opacity(0.55))
                .frame(height: 0.5)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Main View
struct ContentView: View {
    @State private var messages: [Message] = [
        Message(
            text: "You are here. That is the first step. Now tell me — what did you actually do today?",
            isUser: false
        )
    ]

    @State private var inputText = ""
    @State private var isThinking = false

    @State private var viewportHeight: CGFloat = 0
    @State private var bottomAnchorY: CGFloat = 0
    @State private var isNearBottom = true
    @State private var pendingAutoScroll = true

    @FocusState private var inputFocused: Bool

    let backendURL = "https://worker-production-3a1c.up.railway.app/chat"

    var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 0) {
                PresenceGlow()
                    .frame(height: 62)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                chatArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) {
            inputBar
                .background(
                    LinearGradient(
                        colors: [
                            Color(hex: "#070402").opacity(0.0),
                            Color(hex: "#070402").opacity(0.75),
                            Color(hex: "#070402")
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .preferredColorScheme(.dark)
        .onTapGesture {
            inputFocused = false
        }
    }

    var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "#040201"),
                    Color(hex: "#080402"),
                    Color(hex: "#040201")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color(hex: "#2a180c").opacity(0.18),
                    Color(hex: "#120904").opacity(0.08),
                    Color.clear
                ],
                center: .top,
                startRadius: 10,
                endRadius: 260
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.clear,
                    Color(hex: "#140b05").opacity(0.08),
                    Color(hex: "#090402").opacity(0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    var chatArea: some View {
        GeometryReader { outerGeo in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        TimeDivider(label: timeLabel())
                            .padding(.horizontal, 28)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(messages) { msg in
                                MessageBubble(message: msg)
                                    .padding(.horizontal, 28)
                                    .id(msg.id)
                            }

                            if isThinking {
                                HStack {
                                    ThinkingDots()
                                    Spacer()
                                }
                                .padding(.horizontal, 28)
                                .id("thinking")
                            }

                            Color.clear
                                .frame(height: 90)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear
                                            .preference(
                                                key: BottomAnchorOffsetKey.self,
                                                value: geo.frame(in: .named("chatScroll")).minY
                                            )
                                    }
                                )
                                .id("bottom-anchor")
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .coordinateSpace(name: "chatScroll")
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    viewportHeight = outerGeo.size.height
                    DispatchQueue.main.async {
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                }
                .onChange(of: outerGeo.size.height) { _, newHeight in
                    viewportHeight = newHeight
                    updateNearBottom()
                }
                .onPreferenceChange(BottomAnchorOffsetKey.self) { newValue in
                    bottomAnchorY = newValue
                    updateNearBottom()
                }
                .onChange(of: messages.count) { _, _ in
                    if pendingAutoScroll || isNearBottom {
                        scrollToBottom(proxy)
                    }
                    pendingAutoScroll = false
                }
                .onChange(of: isThinking) { _, newValue in
                    if newValue && (pendingAutoScroll || isNearBottom) {
                        scrollToBottom(proxy)
                    }
                }
            }
        }
    }

    var inputBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color(hex: "#1a110a").opacity(0.45))
                .frame(height: 0.5)

            HStack(spacing: 12) {
                TextField(
                    "",
                    text: $inputText,
                    prompt:
                        Text("speak...")
                        .font(.system(size: 17, weight: .regular, design: .serif))
                        .foregroundColor(Color(hex: "#8a6546")),
                    axis: .vertical
                )
                .font(.system(size: 17, weight: .regular, design: .serif))
                .foregroundColor(Color(hex: "#f3e6d7"))
                .tint(Color(hex: "#d59a63"))
                .focused($inputFocused)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(hex: "#120b07").opacity(0.78))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color(hex: "#3b2819").opacity(0.45), lineWidth: 0.7)
                )
                .onTapGesture {
                    pendingAutoScroll = true
                }
                .onSubmit {
                    sendMessage()
                }

                Button(action: sendMessage) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#120b07").opacity(0.88))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle()
                                    .stroke(Color(hex: "#4f3522").opacity(0.55), lineWidth: 0.7)
                            )

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
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
    }

    func updateNearBottom() {
        let threshold: CGFloat = 140
        isNearBottom = bottomAnchorY <= viewportHeight + threshold
    }

    func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
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

        Task {
            await sendToBackend(text: text)
        }
    }

    func sendToBackend(text: String) async {
        guard let url = URL(string: backendURL) else {
            await MainActor.run {
                isThinking = false
                messages.append(
                    Message(
                        text: "The backend URL is invalid.",
                        isUser: false
                    )
                )
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["message": text])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run {
                    isThinking = false
                    messages.append(
                        Message(
                            text: "No valid response from SENSEI.",
                            isUser: false
                        )
                    )
                }
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let bodyText = String(data: data, encoding: .utf8) ?? "Unknown server error."
                await MainActor.run {
                    isThinking = false
                    messages.append(
                        Message(
                            text: "SENSEI returned an error (\(httpResponse.statusCode)): \(bodyText)",
                            isUser: false
                        )
                    )
                }
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let reply = json["reply"] as? String {
                await MainActor.run {
                    isThinking = false
                    pendingAutoScroll = true
                    messages.append(Message(text: reply, isUser: false))
                }
            } else {
                let bodyText = String(data: data, encoding: .utf8) ?? "Unreadable response."
                await MainActor.run {
                    isThinking = false
                    messages.append(
                        Message(
                            text: "SENSEI replied, but the response format was unexpected: \(bodyText)",
                            isUser: false
                        )
                    )
                }
            }
        } catch {
            await MainActor.run {
                isThinking = false
                pendingAutoScroll = true
                messages.append(
                    Message(
                        text: "Could not reach SENSEI. Check your connection.",
                        isUser: false
                    )
                )
            }
        }
    }

    func timeLabel() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let time = formatter.string(from: Date()).lowercased()

        if hour < 12 { return "morning · \(time)" }
        if hour < 17 { return "afternoon · \(time)" }
        return "evening · \(time)"
    }
}

// MARK: - Hex Color
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64

        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    ContentView()
}
