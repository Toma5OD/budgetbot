import Foundation
import SwiftData

enum AttachmentKind: String, Codable {
    case image
    case pdf
    case text
}

@Model
final class Attachment {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var filename: String?
    @Attribute(.externalStorage) var data: Data?
    var text: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: AttachmentKind,
        filename: String? = nil,
        data: Data? = nil,
        text: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.filename = filename
        self.data = data
        self.text = text
        self.createdAt = createdAt
    }

    var kind: AttachmentKind {
        get { AttachmentKind(rawValue: kindRaw) ?? .text }
        set { kindRaw = newValue.rawValue }
    }
}
