import SwiftUI
import AppKit

@MainActor
class AssistantState: ObservableObject {
    @Published var showComposer = false
    @Published var isAlwaysOnTop = true
    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var isThinking = false
    @Published var isResponding = false
    @Published var focusComposer = false
    @Published var petState: PetState = .idle

    enum PetState: Equatable {
        case idle, hover, thinking, responding, success, error
    }

    private let client = HermesClient()

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""

        messages.append(ChatMessage(role: .user, content: text))
        messages.append(ChatMessage(role: .assistant, content: "", isStreaming: true))

        isThinking = true
        isResponding = false
        petState = .thinking
        showComposer = false

        Task { await doStream() }
    }

    private func doStream() async {
        // Don't send the empty assistant placeholder to the API.
        let history = messages.dropLast().map { msg in
            ["role": msg.role == .user ? "user" : "assistant", "content": msg.content]
        }

        do {
            try await client.streamCompletion(messages: history) { [weak self] delta in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.isThinking = false
                    self.isResponding = true
                    self.petState = .responding
                    if let last = self.messages.indices.last {
                        self.messages[last].content += delta
                    }
                }
            }

            if let last = messages.indices.last {
                messages[last].isStreaming = false
            }
            isResponding = false
            petState = .success
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if petState == .success { petState = .idle }
        } catch {
            isThinking = false
            isResponding = false
            petState = .error
            if let last = messages.indices.last {
                messages[last].isStreaming = false
                messages[last].content = "Error: \(error.localizedDescription)"
            }
        }
    }

    func startMock() {
        Task {
            var count = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                count += 1
                messages.append(ChatMessage(role: .assistant, content: "Test message #\(count)"))
            }
        }
    }
}

func loadPetImage() -> NSImage? {
    let names = ["sunless", "sunny"]
    for name in names {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        let path = FileManager.default.currentDirectoryPath + "/\(name).png"
        if FileManager.default.fileExists(atPath: path),
           let image = NSImage(contentsOfFile: path) {
            return image
        }
    }
    return nil
}

struct ResponseBubble: View {
    let text: String
    let isError: Bool

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            MarkdownText(text: text)
                .padding(12)
                .frame(width: 230, alignment: .leading)
        }
        .frame(width: 230)
        .frame(maxHeight: 160, alignment: .top)
    }

    var body: some View {
        if isError {
            content
                .background(Color.red.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.red.opacity(0.3), lineWidth: 1))
                .cornerRadius(18)
                .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
        } else {
            content
                .background(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.gray.opacity(0.18), lineWidth: 1))
                .cornerRadius(18)
                .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
        }
    }
}

final class GrowingTextView: NSScrollView {
    var maxHeight: CGFloat = 120

    private var textView: NSTextView { documentView as! NSTextView }

    override var intrinsicContentSize: NSSize {
        let lineHeight = textView.font?.boundingRectForFont.height ?? 17
        let minHeight = lineHeight + 4
        guard let container = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            return NSSize(width: NSView.noIntrinsicMetric, height: minHeight)
        }
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        let height = used.height + textView.textContainerInset.height * 2
        let clamped = max(minHeight, min(height, maxHeight))
        return NSSize(width: NSView.noIntrinsicMetric, height: clamped)
    }

    func didChangeText() {
        invalidateIntrinsicContentSize()
    }
}

struct PromptTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var shouldFocus: Bool
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> GrowingTextView {
        let scrollView = GrowingTextView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        let textView = NSTextView(frame: .zero)
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.backgroundColor = .clear
        textView.focusRingType = .none
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: GrowingTextView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.focusIfNeeded(textView: textView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PromptTextView
        init(_ parent: PromptTextView) { self.parent = parent }

        func focusIfNeeded(textView: NSTextView) {
            guard parent.shouldFocus else { return }
            if let window = textView.window {
                window.makeFirstResponder(textView)
                if window.firstResponder === textView {
                    Task { @MainActor in
                        parent.shouldFocus = false
                    }
                    return
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.focusIfNeeded(textView: textView)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let scrollView = textView.enclosingScrollView as? GrowingTextView else { return }
            parent.text = textView.string
            scrollView.didChangeText()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    let trimmed = parent.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        parent.onSubmit()
                    }
                }
                return true
            }
            return false
        }
    }
}

struct ComposerView: View {
    @EnvironmentObject var state: AssistantState

    var body: some View {
        ZStack(alignment: .topLeading) {
            PromptTextView(
                text: $state.inputText,
                shouldFocus: $state.focusComposer,
                onSubmit: { state.sendMessage() }
            )
            .frame(maxHeight: 120, alignment: .top)
            .padding(8)

            if state.inputText.isEmpty {
                Text("Ask anything…")
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 230)
        .background(.ultraThinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
        .onAppear { state.focusComposer = true }
    }
}

struct PetWidget: View {
    @EnvironmentObject var state: AssistantState
    var onMove: (CGSize) -> Void
    var onMoveEnd: () -> Void
    @State private var image: NSImage?
    @State private var hovering = false
    @State private var isDragging = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: isDragging)) { timeline in
            ZStack {
                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .shadow(color: Color.black.opacity(0.25), radius: 14, x: 0, y: 8)
                        .scaleEffect(scale(for: timeline.date))
                        .rotationEffect(.degrees(rotation(for: timeline.date)))
                        .offset(y: offsetY(for: timeline.date))
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                if hovering {
                    VStack {
                        HStack(spacing: 6) {
                            Spacer()
                            Button(action: { AssistantController.shared.toggleComposer() }) {
                                Image(systemName: state.showComposer ? "xmark" : "pencil")
                                    .font(.system(size: 11, weight: .bold))
                                    .frame(width: 26, height: 26)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                        }
                        Spacer()
                    }
                    .padding(4)
                }
            }
            .frame(width: 140, height: 140)
            .contentShape(Rectangle())
            .onHover { isHovering in
                hovering = isHovering
                if state.petState == .idle || state.petState == .hover {
                    state.petState = isHovering ? .hover : .idle
                }
            }
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        isDragging = true
                        onMove(value.translation)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onMoveEnd()
                    }
            )
            .contextMenu {
                Button(state.showComposer ? "Close Composer" : "Ask Hermes") {
                    AssistantController.shared.toggleComposer()
                }
                Button(state.isAlwaysOnTop ? "Disable Always on Top" : "Always on Top") {
                    state.isAlwaysOnTop.toggle()
                    AssistantController.shared.window?.level = state.isAlwaysOnTop ? .floating : .normal
                }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .onAppear { image = loadPetImage() }
    }

    private func scale(for date: Date) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate
        switch state.petState {
        case .idle:       return 1.0 + sin(t * 2.0) * 0.02
        case .hover:      return 1.08 + sin(t * 6.0) * 0.015
        case .thinking:   return 1.0 + sin(t * 4.0) * 0.02
        case .responding: return 1.04 + sin(t * 12.0) * 0.025
        case .success:    return 1.12 + sin(t * 15.0) * 0.03
        case .error:      return 1.0 + sin(t * 8.0) * 0.03
        }
    }

    private func rotation(for date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        switch state.petState {
        case .thinking:   return sin(t * 10.0) * 8.0
        case .responding: return sin(t * 15.0) * 6.0
        case .error:      return sin(t * 20.0) * 10.0
        default:          return 0
        }
    }

    private func offsetY(for date: Date) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate
        switch state.petState {
        case .idle:       return sin(t * 2.0) * 3.0
        case .thinking:   return sin(t * 8.0) * 2.0
        case .responding: return sin(t * 10.0) * 2.0
        default:          return 0
        }
    }
}

struct AssistantRoot: View {
    @EnvironmentObject var state: AssistantState
    var onMove: (CGSize) -> Void
    var onMoveEnd: () -> Void

    private var latestResponse: ChatMessage? {
        state.messages.last { $0.role == .assistant && !$0.content.isEmpty }
    }

    var body: some View {
        ZStack {
            if let response = latestResponse {
                ResponseBubble(text: response.content, isError: state.petState == .error)
                    .offset(y: -125)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            PetWidget(onMove: onMove, onMoveEnd: onMoveEnd)

            if state.showComposer {
                ComposerView()
                    .offset(y: 125)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: 260, height: 400)
    }
}
