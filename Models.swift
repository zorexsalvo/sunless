import Foundation

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    var content: String
    var isStreaming: Bool = false

    enum Role: Equatable {
        case user, assistant
    }
}
