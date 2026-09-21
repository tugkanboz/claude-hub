import Foundation

struct RefreshGeneration {
    private var current = UUID()

    mutating func advance() -> UUID {
        current = UUID()
        return current
    }

    func accepts(_ generation: UUID) -> Bool { current == generation }
}
