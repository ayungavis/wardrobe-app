import Foundation

public protocol AccountService: Sendable {
    func deleteAccount() async throws
}

public struct ServerAccountService: AccountService {
    private let client: AuthenticatedAPIClient

    public init(client: AuthenticatedAPIClient) {
        self.client = client
    }

    public func deleteAccount() async throws {
        _ = try await client.send(DeleteUsersMeEndpoint())
    }
}
