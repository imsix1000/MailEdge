import Foundation

enum APIClientError: LocalizedError, Equatable {
  case invalidServerURL
  case insecureServerURL
  case invalidResponse
  case http(status: Int, message: String)
  case encoding

  var errorDescription: String? {
    switch self {
    case .invalidServerURL:
      "服务器地址无效，请填写完整的 https:// 地址"
    case .insecureServerURL:
      "远程服务器必须使用 HTTPS；HTTP 仅用于 localhost 或 127.0.0.1 本地调试"
    case .invalidResponse:
      "服务器返回了无法识别的响应"
    case .http(_, let message):
      message
    case .encoding:
      "请求数据编码失败"
    }
  }

  var isUnauthorized: Bool {
    if case .http(let status, _) = self { return status == 401 }
    return false
  }
}

actor APIClient {
  private var baseURL: URL?
  private let session: URLSession
  private let decoder = JSONDecoder()
  private let encoder = JSONEncoder()

  init(baseURL: URL? = nil) {
    self.baseURL = baseURL
    let configuration = URLSessionConfiguration.default
    configuration.httpCookieStorage = .shared
    configuration.httpShouldSetCookies = true
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 120
    configuration.requestCachePolicy = .reloadRevalidatingCacheData
    session = URLSession(configuration: configuration)
  }

  func updateBaseURL(_ value: String) throws -> URL {
    let url = try Self.validatedServerURL(value)
    baseURL = url
    return url
  }

  static func normalizeServerURL(_ value: String) -> String {
    var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
    while result.hasSuffix("/") { result.removeLast() }
    return result
  }

  static func validatedServerURL(_ value: String) throws -> URL {
    let normalized = normalizeServerURL(value)
    guard var components = URLComponents(string: normalized),
      let scheme = components.scheme?.lowercased(),
      ["https", "http"].contains(scheme),
      let host = components.host?.lowercased(), !host.isEmpty,
      components.user == nil, components.password == nil
    else { throw APIClientError.invalidServerURL }

    if scheme == "http", !isLocalDevelopmentHost(host) {
      throw APIClientError.insecureServerURL
    }

    // 用户经常会从网页版复制 /login、查询参数或 hash；原生客户端只需要实例 origin。
    components.scheme = scheme
    components.path = ""
    components.query = nil
    components.fragment = nil
    guard let url = components.url else { throw APIClientError.invalidServerURL }
    return url
  }

  private static func isLocalDevelopmentHost(_ host: String) -> Bool {
    host == "localhost" || host.hasSuffix(".localhost") || host == "::1" || host.hasPrefix("127.")
  }

  func currentBaseURL() -> URL? { baseURL }

  func health() async throws -> HealthResponse {
    try await request("/api/health")
  }

  func setupStatus() async throws -> SetupStatusResponse {
    try await request("/api/auth/setup")
  }

  func login(email: String, password: String) async throws -> User {
    let response: UserResponse = try await request(
      "/api/auth/login",
      method: "POST",
      payload: LoginPayload(email: email, password: password)
    )
    return response.user
  }

  func setup(_ payload: SetupPayload) async throws -> User {
    let response: UserResponse = try await request(
      "/api/auth/setup", method: "POST", payload: payload)
    return response.user
  }

  func sessionInfo() async throws -> SessionResponse {
    try await request("/api/auth/me")
  }

  func logout() async throws {
    let _: OKResponse = try await request("/api/auth/logout", method: "POST")
  }

  func folders() async throws -> [CustomFolder] {
    let response: FoldersResponse = try await request("/api/folders")
    return response.folders
  }

  func contacts() async throws -> [Contact] {
    let response: ContactsResponse = try await request("/api/contacts")
    return response.contacts
  }

  func createContact(_ payload: ContactPayload) async throws -> Contact {
    let response: ContactResponse = try await request(
      "/api/contacts", method: "POST", payload: payload)
    return response.contact
  }

  func updateContact(id: String, payload: ContactPayload) async throws -> Contact {
    let response: ContactResponse = try await request(
      "/api/contacts/\(id.pathEncoded)", method: "PATCH", payload: payload)
    return response.contact
  }

  func deleteContact(id: String) async throws {
    let _: OKResponse = try await request("/api/contacts/\(id.pathEncoded)", method: "DELETE")
  }

  func usage() async throws -> UsageView {
    try await request("/api/usage")
  }

  func managedAttachments() async throws -> [ManagedAttachment] {
    let response: ManagedAttachmentsResponse = try await request("/api/attachments")
    return response.attachments
  }

  func stageManagedAttachment(_ attachment: ManagedAttachment) async throws
    -> StagedAttachmentResponse
  {
    try await request(
      "/api/attachments/stage", method: "POST",
      payload: ManagedAttachmentReference(attachment))
  }

  func deleteManagedAttachment(_ attachment: ManagedAttachment) async throws {
    let _: OKResponse = try await request(
      "/api/attachments", method: "DELETE",
      payload: ManagedAttachmentReference(attachment))
  }

  func revokeShare(token: String) async throws {
    let _: OKResponse = try await request(
      "/api/shares/\(token.pathEncoded)/revoke", method: "POST")
  }

  func mailboxes() async throws -> [Mailbox] {
    let response: MailboxesResponse = try await request("/api/mailboxes")
    return response.mailboxes
  }

  func createMailbox(_ payload: CreateMailboxPayload) async throws -> Mailbox {
    let response: MailboxResponse = try await request(
      "/api/mailboxes", method: "POST", payload: payload)
    return response.mailbox
  }

  func updateMailbox(id: String, payload: UpdateMailboxPayload) async throws -> Mailbox {
    let response: MailboxResponse = try await request(
      "/api/mailboxes/\(id.pathEncoded)", method: "PATCH", payload: payload)
    return response.mailbox
  }

  func deleteMailbox(id: String, confirmCatchAll: Bool) async throws {
    let path = try endpoint(
      path: "/api/mailboxes/\(id.pathEncoded)",
      query: confirmCatchAll ? [URLQueryItem(name: "confirmCatchAll", value: "true")] : []
    )
    let _: OKResponse = try await request(path, method: "DELETE")
  }

  func changePassword(current: String, new: String) async throws {
    let _: OKResponse = try await request(
      "/api/auth/password", method: "POST",
      payload: PasswordPayload(currentPassword: current, newPassword: new))
  }

  func aiConfig() async throws -> AIConfigResponse {
    try await request("/api/ai/config")
  }

  func saveAIConfig(_ payload: SaveAIConfigPayload) async throws -> AIConfigView {
    let response: SaveAIResponse = try await request(
      "/api/ai/config", method: "POST", payload: payload)
    return response.ai
  }

  func testAIConfig() async throws -> OperationTestResponse {
    try await request("/api/ai/config/test", method: "POST")
  }

  func saveTelegram(_ payload: SaveTelegramPayload) async throws -> TelegramView {
    let response: SaveTelegramResponse = try await request(
      "/api/ai/telegram", method: "POST", payload: payload)
    return response.telegram
  }

  func testTelegram() async throws -> OperationTestResponse {
    try await request("/api/ai/telegram/test", method: "POST")
  }

  func storageConfig() async throws -> StorageConfigView {
    try await request("/api/storage/config")
  }

  func saveStorageBackend(_ backend: String) async throws -> StorageConfigView {
    try await request(
      "/api/storage/config", method: "POST", payload: StorageBackendPayload(backend: backend))
  }

  func saveRetention(days: Int) async throws -> RetentionResponse {
    try await request(
      "/api/storage/retention", method: "POST", payload: RetentionPayload(days: days))
  }

  func updateVersion() async throws -> UpdateVersionView {
    try await request("/api/update/version")
  }

  func providers() async throws -> [ProviderView] {
    let response: ProvidersResponse = try await request("/api/providers")
    return response.providers
  }

  func saveProvider(_ payload: [String: JSONValue]) async throws -> ProviderView {
    let response: ProviderResponse = try await request(
      "/api/providers", method: "POST", payload: payload)
    return response.provider
  }

  func setDefaultProvider(id: String) async throws {
    let _: OKResponse = try await request(
      "/api/providers/\(id.pathEncoded)/default", method: "POST")
  }

  func fetchProviderDomains(id: String) async throws -> ProviderDomainsResponse {
    try await request("/api/providers/\(id.pathEncoded)/domains", method: "POST")
  }

  func deleteProvider(id: String) async throws {
    let _: OKResponse = try await request("/api/providers/\(id.pathEncoded)", method: "DELETE")
  }

  func testProvider(id: String, from: String, to: String) async throws -> ProviderTestResult {
    try await request(
      "/api/providers/\(id.pathEncoded)/test", method: "POST",
      payload: ProviderTestPayload(from: from, to: to))
  }

  func stats(mailboxId: String) async throws -> [FolderStats] {
    let path = try endpoint(
      path: "/api/stats", query: [URLQueryItem(name: "mailboxId", value: mailboxId)])
    let response: StatsResponse = try await request(path)
    return response.stats
  }

  func messages(mailboxId: String, folder: String, query: String, before: String? = nil)
    async throws -> MessagesResponse
  {
    var items = [
      URLQueryItem(name: "mailboxId", value: mailboxId),
      URLQueryItem(name: "folder", value: folder),
      URLQueryItem(name: "limit", value: "50"),
    ]
    if let search = query.nilIfBlank { items.append(URLQueryItem(name: "q", value: search)) }
    if let before { items.append(URLQueryItem(name: "before", value: before)) }
    return try await request(try endpoint(path: "/api/messages", query: items))
  }

  func message(id: String, mailboxId: String) async throws -> MessageDetail {
    let path = try endpoint(
      path: "/api/messages/\(id.pathEncoded)",
      query: [URLQueryItem(name: "mailboxId", value: mailboxId)]
    )
    let response: MessageResponse = try await request(path)
    return response.message
  }

  func patchMessage(
    id: String, mailboxId: String, isRead: Bool? = nil, isStarred: Bool? = nil,
    folder: String? = nil
  ) async throws {
    let path = try endpoint(
      path: "/api/messages/\(id.pathEncoded)",
      query: [URLQueryItem(name: "mailboxId", value: mailboxId)]
    )
    let payload = PatchMessagePayload(isRead: isRead, isStarred: isStarred, folder: folder)
    let _: OKResponse = try await request(path, method: "PATCH", payload: payload)
  }

  func deleteMessage(id: String, mailboxId: String) async throws {
    let path = try endpoint(
      path: "/api/messages/\(id.pathEncoded)",
      query: [URLQueryItem(name: "mailboxId", value: mailboxId)]
    )
    let _: OKResponse = try await request(path, method: "DELETE")
  }

  func markAllRead(mailboxId: String, folder: String) async throws {
    let path = try endpoint(
      path: "/api/messages/read-all",
      query: [URLQueryItem(name: "mailboxId", value: mailboxId)]
    )
    let _: OKResponse = try await request(
      path, method: "POST", payload: ReadAllPayload(folder: folder))
  }

  func send(_ payload: SendPayload) async throws -> SendResponse {
    try await request("/api/mail/send", method: "POST", payload: payload)
  }

  func uploadAttachment(data: Data, filename: String, contentType: String) async throws
    -> AttachmentUploadResponse
  {
    let boundary = "MailEdge-\(UUID().uuidString)"
    var body = Data()
    body.appendUTF8("--\(boundary)\r\n")
    body.appendUTF8(
      "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename.multipartEscaped)\"\r\n"
    )
    body.appendUTF8("Content-Type: \(contentType)\r\n\r\n")
    body.append(data)
    body.appendUTF8("\r\n--\(boundary)--\r\n")
    return try await request(
      "/api/mail/attachment",
      method: "POST",
      body: body,
      contentType: "multipart/form-data; boundary=\(boundary)"
    )
  }

  func deleteStagedAttachment(token: String) async throws {
    let _: OKResponse = try await request(
      "/api/mail/attachment/\(token.pathEncoded)", method: "DELETE")
  }

  func attachmentData(downloadPath: String) async throws -> (Data, URLResponse) {
    let request = try makeRequest(path: downloadPath, method: "GET", body: nil, contentType: nil)
    let (data, response) = try await session.data(for: request)
    try validate(response: response, data: data)
    return (data, response)
  }

  private func endpoint(path: String, query: [URLQueryItem]) throws -> String {
    guard var components = URLComponents(string: path) else {
      throw APIClientError.invalidServerURL
    }
    components.queryItems = query
    guard let result = components.string else { throw APIClientError.invalidServerURL }
    return result
  }

  private func request<Response: Decodable, Payload: Encodable>(
    _ path: String,
    method: String,
    payload: Payload
  ) async throws -> Response {
    guard let body = try? encoder.encode(payload) else { throw APIClientError.encoding }
    return try await request(path, method: method, body: body, contentType: "application/json")
  }

  private func request<Response: Decodable>(
    _ path: String,
    method: String = "GET",
    body: Data? = nil,
    contentType: String? = "application/json"
  ) async throws -> Response {
    let request = try makeRequest(path: path, method: method, body: body, contentType: contentType)
    let (data, response) = try await session.data(for: request)
    try validate(response: response, data: data)
    do {
      return try decoder.decode(Response.self, from: data)
    } catch {
      throw APIClientError.invalidResponse
    }
  }

  private func makeRequest(path: String, method: String, body: Data?, contentType: String?) throws
    -> URLRequest
  {
    guard let baseURL else { throw APIClientError.invalidServerURL }
    let url: URL
    if let absolute = URL(string: path), absolute.scheme != nil {
      url = absolute
    } else {
      guard let resolved = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
        throw APIClientError.invalidServerURL
      }
      url = resolved
    }
    guard url.host == baseURL.host else { throw APIClientError.invalidServerURL }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("MailEdge-macOS/0.1", forHTTPHeaderField: "User-Agent")
    if body != nil, let contentType {
      request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    }
    return request
  }

  private func validate(response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      let message =
        (try? decoder.decode(APIErrorPayload.self, from: data).error)
        ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
      throw APIClientError.http(status: http.statusCode, message: message)
    }
  }
}

extension String {
  fileprivate var pathEncoded: String {
    addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
  }

  fileprivate var multipartEscaped: String {
    replacingOccurrences(of: "\\", with: "_").replacingOccurrences(of: "\"", with: "_")
  }
}

extension Data {
  fileprivate mutating func appendUTF8(_ value: String) {
    if let data = value.data(using: .utf8) { append(data) }
  }
}
