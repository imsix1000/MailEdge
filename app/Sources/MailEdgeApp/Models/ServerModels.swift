import Foundation

struct UsageView: Codable, Hashable, Sendable {
  struct D1Usage: Codable, Hashable, Sendable {
    let sizeBytes: Int?
    let pageCount: Int?
    let pageSize: Int?
    let totalRows: Int
    let rows: [String: Int]
  }

  struct DurableObjectsUsage: Codable, Hashable, Sendable {
    let mailboxCount: Int
    let messageCount: Int
    let attachmentCount: Int
    let archivedMessageCount: Int
    let sqliteBytes: Int?
    let bodyBytesInSqlite: Int
  }

  struct R2Usage: Codable, Hashable, Sendable {
    let available: Bool
    let objectCount: Int
    let bytes: Int
    let truncated: Bool
  }

  let scope: String
  let d1: D1Usage
  let durableObjects: DurableObjectsUsage
  let r2: R2Usage
  let updatedAt: String
}

struct ManagedAttachment: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let source: String
  let mailboxId: String?
  let mailboxAddress: String?
  let messageId: String?
  let messageSubject: String?
  let filename: String
  let contentType: String
  let size: Int
  let direction: String
  let folder: String
  let mode: String
  let uploadedAt: String
  let downloadUrl: String
  let token: String?
  let downloads: Int?
  let expiresAt: String?
  let expired: Bool?
  let revoked: Bool?

  var stableID: String { "\(source):\(id)" }
  var uploadedDate: Date? { MailDateParser.date(from: uploadedAt) }
  var isUnavailable: Bool { expired == true || revoked == true }
}

struct ManagedAttachmentsResponse: Codable, Sendable {
  let attachments: [ManagedAttachment]
  let total: Int
}

struct ManagedAttachmentReference: Encodable, Sendable {
  let source: String
  let mailboxId: String?
  let messageId: String?
  let attachmentId: String?
  let token: String?

  init(_ attachment: ManagedAttachment) {
    source = attachment.source
    mailboxId = attachment.source == "message" ? attachment.mailboxId : nil
    messageId = attachment.source == "message" ? attachment.messageId : nil
    attachmentId = attachment.source == "message" ? attachment.id : nil
    token = attachment.source == "share" ? attachment.token : nil
  }
}

struct StagedAttachmentResponse: Codable, Sendable {
  let token: String
  let filename: String
  let contentType: String
  let size: Int
}

struct ContactPayload: Encodable, Sendable {
  let email: String
  let name: String
  let company: String?
  let notes: String?
}

struct ContactResponse: Codable, Sendable {
  let contact: Contact
}

struct MailboxResponse: Codable, Sendable {
  let mailbox: Mailbox
}

struct CreateMailboxPayload: Encodable, Sendable {
  let address: String
  let displayName: String?
  let isCatchAll: Bool
}

struct UpdateMailboxPayload: Encodable, Sendable {
  let displayName: String?
  let isCatchAll: Bool?
}

struct PasswordPayload: Encodable, Sendable {
  let currentPassword: String
  let newPassword: String
}

struct AIConfigView: Codable, Hashable, Sendable {
  let enabled: Bool
  let baseUrl: String?
  let apiKey: String?
  let hasKey: Bool?
  let model: String?
}

struct TelegramView: Codable, Hashable, Sendable {
  let enabled: Bool
  let botToken: String?
  let hasToken: Bool?
  let chatId: String?
  let onlyCategories: [String]?
}

struct AIConfigResponse: Codable, Hashable, Sendable {
  let ai: AIConfigView
  let telegram: TelegramView
  let categories: [String: String]
}

struct SaveAIResponse: Codable, Sendable {
  let ai: AIConfigView
}

struct SaveTelegramResponse: Codable, Sendable {
  let telegram: TelegramView
}

struct OperationTestResponse: Codable, Sendable {
  let ok: Bool
  let reply: String?
  let error: String?
}

struct SaveAIConfigPayload: Encodable, Sendable {
  let enabled: Bool
  let baseUrl: String
  let apiKey: String
  let model: String
}

struct SaveTelegramPayload: Encodable, Sendable {
  let enabled: Bool
  let botToken: String
  let chatId: String
  let onlyCategories: [String]
}

struct StorageConfigView: Codable, Hashable, Sendable {
  let backend: String
  let configuredBackend: String
  let r2Available: Bool
  let kvAvailable: Bool
  let outboundRetentionDays: Int
  let outboundRetentionOptions: [Int]
}

struct StorageBackendPayload: Encodable, Sendable {
  let backend: String
}

struct RetentionPayload: Encodable, Sendable {
  let days: Int
}

struct RetentionResponse: Codable, Sendable {
  let outboundRetentionDays: Int
  let outboundRetentionOptions: [Int]
}

struct UpdateVersionView: Codable, Hashable, Sendable {
  let currentVersion: String
  let availableVersion: String?
  let updateAvailable: Bool
  let source: String?
  let checkedAt: String
}

struct ProviderView: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let name: String
  let type: String
  let isDefault: Bool
  let isEnabled: Bool
  let priority: Int
  let lastError: String?
  let lastCheckedAt: String?
  let createdAt: String
  let config: [String: JSONValue]
}

struct ProvidersResponse: Codable, Sendable {
  let providers: [ProviderView]
}

struct ProviderResponse: Codable, Sendable {
  let provider: ProviderView
}

struct ProviderDomainsResponse: Codable, Sendable {
  let domains: [String]
  let provider: ProviderView
}

struct ProviderTestPayload: Encodable, Sendable {
  let from: String
  let to: String
}

struct ProviderTestResult: Codable, Sendable {
  struct Result: Codable, Sendable {
    let success: Bool
    let error: String?
    let providerMessageId: String?
  }
  let result: Result
}

enum JSONValue: Codable, Hashable, Sendable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case array([JSONValue])
  case object([String: JSONValue])
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() { self = .null }
    else if let value = try? container.decode(Bool.self) { self = .bool(value) }
    else if let value = try? container.decode(Double.self) { self = .number(value) }
    else if let value = try? container.decode(String.self) { self = .string(value) }
    else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
    else { self = .object(try container.decode([String: JSONValue].self)) }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .bool(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }

  var stringValue: String? {
    if case .string(let value) = self { return value }
    return nil
  }
}

extension Int64 {
  var byteCountText: String {
    ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
  }
}
