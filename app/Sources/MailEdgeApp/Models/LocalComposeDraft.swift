import CryptoKit
import Foundation

struct LocalComposeDraft: Codable, Equatable, Sendable {
  let context: String
  let from: String
  let to: String
  let cc: String
  let bcc: String
  let subject: String
  let body: String
  let savedAt: Date
}

enum LocalComposeDraftStore {
  static func load(context: String) throws -> LocalComposeDraft? {
    let url = try draftURL(context: context)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let draft = try JSONDecoder().decode(LocalComposeDraft.self, from: Data(contentsOf: url))
    return draft.context == context ? draft : nil
  }

  static func save(_ draft: LocalComposeDraft) throws {
    let url = try draftURL(context: draft.context)
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONEncoder().encode(draft).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  static func clear(context: String) {
    guard let url = try? draftURL(context: context) else { return }
    try? FileManager.default.removeItem(at: url)
  }

  private static func draftURL(context: String) throws -> URL {
    guard let applicationSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first else {
      throw CocoaError(.fileNoSuchFile)
    }
    let digest = SHA256.hash(data: Data(context.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    return applicationSupport
      .appendingPathComponent("MailEdge", isDirectory: true)
      .appendingPathComponent("compose-draft-\(digest).json", isDirectory: false)
  }
}
