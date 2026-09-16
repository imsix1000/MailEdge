import Foundation

struct User: Codable, Hashable, Sendable {
  let id: String
  let email: String
  let name: String?
  let role: String
  let isEnabled: Bool
  let createdAt: String

  var displayName: String { name?.nilIfBlank ?? email }
}

struct Mailbox: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let address: String
  let displayName: String?
  let isCatchAll: Bool
  let domain: String
  let createdAt: String

  var title: String { displayName?.nilIfBlank ?? address }
}

struct Contact: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let email: String
  let name: String
  let company: String?
  let notes: String?
  let createdAt: String
  let updatedAt: String

  var initials: String {
    let value = name.nilIfBlank ?? email
    return String(value.prefix(1)).uppercased()
  }
}

struct CustomFolder: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let name: String
  let createdAt: String
}

struct FolderStats: Codable, Hashable, Sendable {
  let folder: String
  let total: Int
  let unread: Int
}

struct MessageAddress: Codable, Hashable, Sendable {
  let email: String
  let name: String?

  var displayName: String { name?.nilIfBlank ?? email }
}

struct MessageSummary: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let mailboxId: String?
  let mailboxAddress: String?
  let internalId: String?
  let direction: String
  let folder: String
  let subject: String
  let snippet: String
  let from: MessageAddress
  let to: [MessageAddress]
  let isRead: Bool
  let isStarred: Bool
  let hasAttachments: Bool
  let status: String?
  let provider: String?
  let category: String?
  let receivedAt: String

  var participant: String {
    direction == "outbound" ? (to.first?.displayName ?? "未知收件人") : from.displayName
  }

  var inboundAlias: String? {
    guard direction != "outbound" else { return nil }
    let mailbox = mailboxAddress?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let aliases = to.map(\.email)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && (mailbox == nil || $0.lowercased() != mailbox) }
    return aliases.isEmpty ? nil : aliases.joined(separator: "、")
  }

  var displaySubject: String { subject.nilIfBlank ?? "（无主题）" }

  var receivedDate: Date? { MailDateParser.date(from: receivedAt) }

  func updating(isRead: Bool? = nil, isStarred: Bool? = nil, folder: String? = nil) -> Self {
    .init(
      id: id,
      mailboxId: mailboxId,
      mailboxAddress: mailboxAddress,
      internalId: internalId,
      direction: direction,
      folder: folder ?? self.folder,
      subject: subject,
      snippet: snippet,
      from: from,
      to: to,
      isRead: isRead ?? self.isRead,
      isStarred: isStarred ?? self.isStarred,
      hasAttachments: hasAttachments,
      status: status,
      provider: provider,
      category: category,
      receivedAt: receivedAt
    )
  }
}

struct MessageAttachment: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let filename: String
  let contentType: String
  let size: Int
  let mode: String
  let downloadUrl: String
}

struct MessageDetail: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let mailboxId: String?
  let mailboxAddress: String?
  let internalId: String?
  let direction: String
  let folder: String
  let subject: String
  let snippet: String
  let from: MessageAddress
  let to: [MessageAddress]
  let isRead: Bool
  let isStarred: Bool
  let hasAttachments: Bool
  let status: String?
  let provider: String?
  let category: String?
  let receivedAt: String
  let cc: [MessageAddress]
  let bcc: [MessageAddress]
  let replyTo: MessageAddress?
  let html: String?
  let text: String?
  let headers: [String: String]
  let size: Int
  let messageId: String?
  let inReplyTo: String?
  let error: String?
  let aiSummary: String?
  let attachments: [MessageAttachment]

  var displaySubject: String { subject.nilIfBlank ?? "（无主题）" }
  var senderName: String { from.displayName }
  var receivedDate: Date? { MailDateParser.date(from: receivedAt) }
}

struct HealthResponse: Codable, Sendable {
  let ok: Bool
  let service: String
  let apiVersion: Int?
}

struct SetupStatusResponse: Codable, Sendable {
  let needsSetup: Bool
}

struct UserResponse: Codable, Sendable {
  let user: User
}

struct SessionResponse: Codable, Sendable {
  let user: User
  let mailboxes: [Mailbox]
}

struct MailboxesResponse: Codable, Sendable {
  let mailboxes: [Mailbox]
}

struct ContactsResponse: Codable, Sendable {
  let contacts: [Contact]
}

struct FoldersResponse: Codable, Sendable {
  let folders: [CustomFolder]
}

struct StatsResponse: Codable, Sendable {
  let stats: [FolderStats]
}

struct MessagesResponse: Codable, Sendable {
  let items: [MessageSummary]
  let nextCursor: String?
}

struct MessageResponse: Codable, Sendable {
  let message: MessageDetail
}

struct OKResponse: Codable, Sendable {
  let ok: Bool
}

struct SendResponse: Codable, Sendable {
  let internalId: String
  let status: String
  let provider: String
  let success: Bool
  let error: String?
}

struct UploadedAttachment: Identifiable, Hashable, Sendable {
  let id = UUID()
  let token: String
  let filename: String
  let contentType: String
  let size: Int
}

struct ComposeSeed: Hashable, Sendable {
  var from = ""
  var to = ""
  var subject = ""
  var body = ""
}

struct AttachmentUploadResponse: Codable, Sendable {
  let token: String
  let filename: String
  let size: Int
}

struct SendPayload: Encodable, Sendable {
  struct Attachment: Encodable, Sendable {
    let token: String
    let filename: String
    let contentType: String
  }

  let from: String
  let to: String
  let cc: [String]?
  let bcc: [String]?
  let subject: String
  let markdown: String
  let attachments: [Attachment]
}

struct SetupPayload: Encodable, Sendable {
  let email: String
  let password: String
  let name: String?
  let mailbox: String?
}

struct LoginPayload: Encodable, Sendable {
  let email: String
  let password: String
}

struct PatchMessagePayload: Encodable, Sendable {
  let isRead: Bool?
  let isStarred: Bool?
  let folder: String?
}

struct ReadAllPayload: Encodable, Sendable {
  let folder: String
}

struct APIErrorPayload: Decodable, Sendable {
  let error: String?
}

enum MailDateParser {
  static func date(from value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let standard = ISO8601DateFormatter()
    return fractional.date(from: value) ?? standard.date(from: value)
  }
}

extension String {
  var nilIfBlank: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

extension Int {
  var byteCountText: String {
    ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
  }
}
