import Foundation

public struct DiagnosticEntry: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let at: Date
    public let message: String
    public let operation: String?
    public let endpoint: String?
    public let requestID: String?
    public let status: Int?
}
