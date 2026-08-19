import CoreTransferable
import Foundation
import UniformTypeIdentifiers

public struct ExportedPhoto: Equatable, Sendable, Transferable {
    public let data: Data

    public init(data: Data) {
        self.data = data
    }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { photo in photo.data }
    }
}
