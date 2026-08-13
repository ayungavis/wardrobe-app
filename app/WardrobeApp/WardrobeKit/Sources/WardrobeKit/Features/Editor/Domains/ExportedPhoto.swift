import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Sanitized flattened derivative (FR-032): the bytes shared and saved are
/// identical, produced once from pixels only — no source metadata survives.
public struct ExportedPhoto: Equatable, Sendable, Transferable {
    public let data: Data

    public init(data: Data) {
        self.data = data
    }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { photo in photo.data }
    }
}
