import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppStore {
  enum Phase: Equatable {
    case launching
    case connection
    case setup
    case signedOut
    case authenticated
  }

  enum Workspace: Equatable {
    case overview
    case mail
    case attachments
    case contacts
  }

  private enum DefaultsKey {
    static let serverURL = "MailEdge.serverURL"
  }

  private enum InfoKey {
    static let defaultServerURL = "MailEdgeDefaultServerURL"
  }

  var phase: Phase = .launching
  var serverURL: String
  var user: User?
  var mailboxes: [Mailbox] = []
  var contacts: [Contact] = []
  var folders: [CustomFolder] = []
  var stats: [FolderStats] = []
  var messages: [MessageSummary] = []
  var usage: UsageView?
  var managedAttachments: [ManagedAttachment] = []
  var providers: [ProviderView] = []
  var aiConfiguration: AIConfigResponse?
  var storageConfiguration: StorageConfigView?
  var updateVersion: UpdateVersionView?
  var workspace: Workspace = .overview
  var selectedMailboxId = "all"
  var selectedFolder = "inbox"
  var selectedMessageId: String?
  var detail: MessageDetail?
  var searchText = ""
  var nextCursor: String?
  var isLoading = false
  var isLoadingDetail = false
  var isLoadingMore = false
  var isLoadingContacts = false
  var isLoadingUsage = false
  var isLoadingAttachments = false
  var isLoadingSettings = false
  var isComposing = false
  var composeSeed = ComposeSeed()
  var composeAttachments: [UploadedAttachment] = []
  var errorMessage: String?
  var noticeMessage: String?
  var contactsErrorMessage: String?
  var serverAPIVersion: Int?

  private let client: APIClient
  private var listRequestID = UUID()

  init(defaults: UserDefaults = .standard) {
    let saved = defaults.string(forKey: DefaultsKey.serverURL)?.nilIfBlank
    let bundled = (Bundle.main.object(forInfoDictionaryKey: InfoKey.defaultServerURL) as? String)?.nilIfBlank
    let initial = saved ?? bundled ?? ""
    serverURL = initial
    client = APIClient(baseURL: URL(string: APIClient.normalizeServerURL(initial)))
  }

  var selectedMailbox: Mailbox? {
    mailboxes.first { $0.id == selectedMailboxId }
  }

  var selectedFolderTitle: String {
    if let custom = folders.first(where: { $0.id == selectedFolder }) { return custom.name }
    return Self.folderTitle(selectedFolder)
  }

  func bootstrap() async {
    guard !serverURL.isEmpty else {
      phase = .connection
      return
    }
    await connect(to: serverURL, persist: false)
  }

  func connect(to rawURL: String, persist: Bool = true) async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    do {
      let normalizedURL = try await client.updateBaseURL(rawURL)
      let health = try await client.health()
      guard health.ok, health.service == "MailEdge" else { throw APIClientError.invalidResponse }
      serverAPIVersion = health.apiVersion
      serverURL = APIClient.normalizeServerURL(normalizedURL.absoluteString)
      if persist { UserDefaults.standard.set(serverURL, forKey: DefaultsKey.serverURL) }
      await resolveAuthentication()
    } catch {
      phase = .connection
      show(error)
    }
  }

  func login(email: String, password: String) async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      _ = try await client.login(email: email, password: password)
      try await loadSession()
    } catch {
      show(error)
    }
  }

  func setup(email: String, password: String, name: String, mailbox: String) async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      let payload = SetupPayload(
        email: email,
        password: password,
        name: name.nilIfBlank,
        mailbox: mailbox.nilIfBlank
      )
      _ = try await client.setup(payload)
      try await loadSession()
    } catch {
      show(error)
    }
  }

  func logout() async {
    do {
      try await client.logout()
    } catch {
      // 本地仍退出，避免失效会话卡住界面。
    }
    clearWorkspace()
    phase = .signedOut
  }

  func changeServer() {
    clearWorkspace()
    serverAPIVersion = nil
    phase = .connection
  }

  func refresh() async {
    guard phase == .authenticated else { return }
    async let statsTask: Void = refreshStats()
    async let listTask: Void = refreshMessages()
    _ = await (statsTask, listTask)
  }

  func refreshOverview() async {
    guard phase == .authenticated else { return }
    async let mailTask: Void = refresh()
    async let resourceTask: Void = refreshOverviewResources()
    _ = await (mailTask, resourceTask)
  }

  func selectMailbox(_ id: String) async {
    let selectionChanged = selectedMailboxId != id
    workspace = .mail
    guard selectionChanged else { return }
    selectedMailboxId = id
    selectedMessageId = nil
    detail = nil
    await refresh()
  }

  func selectFolder(_ folder: String) async {
    let selectionChanged = selectedFolder != folder
    workspace = .mail
    guard selectionChanged else { return }
    selectedFolder = folder
    selectedMessageId = nil
    detail = nil
    searchText = ""
    await refresh()
  }

  func showOverview() {
    selectedMessageId = nil
    detail = nil
    workspace = .overview
  }

  func showAttachments() async {
    selectedMessageId = nil
    detail = nil
    workspace = .attachments
    await loadManagedAttachments(force: managedAttachments.isEmpty)
  }

  func showContacts() async {
    selectedMessageId = nil
    detail = nil
    workspace = .contacts
    await loadContacts(force: contacts.isEmpty)
  }

  func refreshOverviewResources() async {
    guard !isLoadingUsage else { return }
    isLoadingUsage = true
    defer { isLoadingUsage = false }
    do {
      async let usageTask = client.usage()
      async let attachmentTask = client.managedAttachments()
      usage = try await usageTask
      managedAttachments = try await attachmentTask
    } catch {
      handleSessionError(error)
    }
  }

  func loadManagedAttachments(force: Bool = false) async {
    guard force || managedAttachments.isEmpty else { return }
    guard !isLoadingAttachments else { return }
    isLoadingAttachments = true
    defer { isLoadingAttachments = false }
    do {
      managedAttachments = try await client.managedAttachments()
    } catch {
      handleSessionError(error)
    }
  }

  func search() async {
    await refreshMessages()
  }

  func loadContacts(force: Bool = false) async {
    guard force || contacts.isEmpty else { return }
    guard !isLoadingContacts else { return }
    isLoadingContacts = true
    contactsErrorMessage = nil
    defer { isLoadingContacts = false }
    do {
      contacts = try await client.contacts()
    } catch {
      contactsErrorMessage =
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      if let apiError = error as? APIClientError, apiError.isUnauthorized {
        handleSessionError(error)
      }
    }
  }

  @discardableResult
  func saveContact(id: String?, email: String, name: String, company: String, notes: String)
    async throws -> Contact
  {
    let payload = ContactPayload(
      email: email.trimmingCharacters(in: .whitespacesAndNewlines),
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      company: company.nilIfBlank,
      notes: notes.nilIfBlank
    )
    do {
      let result = if let id {
        try await client.updateContact(id: id, payload: payload)
      } else {
        try await client.createContact(payload)
      }
      await loadContacts(force: true)
      noticeMessage = id == nil ? "联系人已创建" : "联系人已更新"
      return result
    } catch {
      handleSessionError(error, showMessage: false)
      throw error
    }
  }

  func deleteContact(_ contact: Contact) async throws {
    do {
      try await client.deleteContact(id: contact.id)
      contacts.removeAll { $0.id == contact.id }
      noticeMessage = "联系人已删除"
    } catch {
      handleSessionError(error, showMessage: false)
      throw error
    }
  }

  func loadMore() async {
    guard !isLoadingMore, let nextCursor else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let response = try await client.messages(
        mailboxId: selectedMailboxId,
        folder: selectedFolder,
        query: searchText,
        before: nextCursor
      )
      let existing = Set(messages.map(\.id))
      messages.append(contentsOf: response.items.filter { !existing.contains($0.id) })
      self.nextCursor = response.nextCursor
    } catch {
      handleSessionError(error)
    }
  }

  func selectMessage(_ message: MessageSummary) async {
    workspace = .mail
    selectedMessageId = message.id
    detail = nil
    isLoadingDetail = true
    defer { isLoadingDetail = false }
    do {
      let mailboxId = message.mailboxId ?? selectedMailboxId
      let loaded = try await client.message(id: message.id, mailboxId: mailboxId)
      guard selectedMessageId == message.id else { return }
      detail = loaded
      updateSummary(id: message.id, isRead: true)
      await refreshStats()
    } catch {
      handleSessionError(error)
    }
  }

  func toggleStar(_ message: MessageSummary) async {
    let next = !message.isStarred
    updateSummary(id: message.id, isStarred: next)
    do {
      try await client.patchMessage(
        id: message.id,
        mailboxId: message.mailboxId ?? selectedMailboxId,
        isStarred: next
      )
      if selectedMessageId == message.id { await reloadSelectedDetail() }
    } catch {
      updateSummary(id: message.id, isStarred: message.isStarred)
      handleSessionError(error)
    }
  }

  func toggleDetailStar() async {
    guard let detail else { return }
    let next = !detail.isStarred
    do {
      try await client.patchMessage(
        id: detail.id,
        mailboxId: detail.mailboxId ?? selectedMailboxId,
        isStarred: next
      )
      updateSummary(id: detail.id, isStarred: next)
      await reloadSelectedDetail()
    } catch {
      handleSessionError(error)
    }
  }

  func moveSelected(to folder: String) async {
    guard let detail else { return }
    do {
      try await client.patchMessage(
        id: detail.id,
        mailboxId: detail.mailboxId ?? selectedMailboxId,
        folder: folder
      )
      selectedMessageId = nil
      self.detail = nil
      noticeMessage = "邮件已移至\(Self.folderTitle(folder))"
      await refresh()
    } catch {
      handleSessionError(error)
    }
  }

  func deleteSelected() async {
    guard let detail else { return }
    do {
      try await client.deleteMessage(
        id: detail.id, mailboxId: detail.mailboxId ?? selectedMailboxId)
      selectedMessageId = nil
      self.detail = nil
      noticeMessage = detail.folder == "trash" ? "邮件已永久删除" : "邮件已移至废纸篓"
      await refresh()
    } catch {
      handleSessionError(error)
    }
  }

  func markAllRead() async {
    do {
      try await client.markAllRead(mailboxId: selectedMailboxId, folder: selectedFolder)
      messages = messages.map { $0.updating(isRead: true) }
      await refreshStats()
    } catch {
      handleSessionError(error)
    }
  }

  func sendMessage(
    from: String,
    to: String,
    cc: String,
    bcc: String,
    subject: String,
    body: String,
    attachments: [UploadedAttachment]
  ) async throws -> SendResponse {
    let payload = SendPayload(
      from: from,
      to: to,
      cc: Self.addressList(cc),
      bcc: Self.addressList(bcc),
      subject: subject,
      markdown: body,
      attachments: attachments.map {
        .init(token: $0.token, filename: $0.filename, contentType: $0.contentType)
      }
    )
    do {
      let result = try await client.send(payload)
      noticeMessage = result.success ? "邮件已发送" : (result.error ?? "邮件进入重试队列")
      await refresh()
      return result
    } catch {
      handleSessionError(error, showMessage: false)
      throw error
    }
  }

  func uploadAttachment(url: URL) async throws -> UploadedAttachment {
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    let contentType =
      (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.preferredMIMEType
      ?? "application/octet-stream"
    let response = try await client.uploadAttachment(
      data: data,
      filename: url.lastPathComponent,
      contentType: contentType
    )
    return UploadedAttachment(
      token: response.token,
      filename: response.filename,
      contentType: contentType,
      size: response.size
    )
  }

  func removeAttachment(_ attachment: UploadedAttachment) async {
    try? await client.deleteStagedAttachment(token: attachment.token)
  }

  func compose(with attachment: ManagedAttachment) async {
    do {
      let staged = try await client.stageManagedAttachment(attachment)
      composeSeed = ComposeSeed(from: mailboxes.first?.address ?? "")
      composeAttachments = [
        UploadedAttachment(
          token: staged.token,
          filename: staged.filename,
          contentType: staged.contentType,
          size: staged.size
        )
      ]
      isComposing = true
    } catch {
      handleSessionError(error)
    }
  }

  func deleteManagedAttachment(_ attachment: ManagedAttachment) async throws {
    do {
      try await client.deleteManagedAttachment(attachment)
      managedAttachments.removeAll { $0.stableID == attachment.stableID }
      noticeMessage = "附件已删除"
      await refreshOverviewResources()
    } catch {
      handleSessionError(error, showMessage: false)
      throw error
    }
  }

  func revokeShare(_ attachment: ManagedAttachment) async throws {
    guard let token = attachment.token else { return }
    do {
      try await client.revokeShare(token: token)
      await loadManagedAttachments(force: true)
      noticeMessage = "分享链接已撤销"
    } catch {
      handleSessionError(error, showMessage: false)
      throw error
    }
  }

  func download(_ attachment: ManagedAttachment) async {
    guard !attachment.isUnavailable else { return }
    do {
      let (data, _) = try await client.attachmentData(downloadPath: attachment.downloadUrl)
      let panel = NSSavePanel()
      panel.nameFieldStringValue = attachment.filename
      panel.canCreateDirectories = true
      guard panel.runModal() == .OK, let destination = panel.url else { return }
      try data.write(to: destination, options: .atomic)
      noticeMessage = "附件已保存"
    } catch {
      handleSessionError(error)
    }
  }

  func shareURL(for attachment: ManagedAttachment) async -> URL? {
    guard attachment.source == "share", let token = attachment.token,
      let base = await client.currentBaseURL()
    else { return nil }
    return URL(string: "/d/\(token)", relativeTo: base)?.absoluteURL
  }

  func loadSettingsData() async {
    guard !isLoadingSettings else { return }
    isLoadingSettings = true
    defer { isLoadingSettings = false }
    do {
      async let mailboxTask = client.mailboxes()
      async let aiTask = client.aiConfig()
      async let storageTask = client.storageConfig()
      async let updateTask = client.updateVersion()
      mailboxes = try await mailboxTask
      aiConfiguration = try await aiTask
      storageConfiguration = try await storageTask
      updateVersion = try await updateTask
      if user?.role == "admin" {
        providers = try await client.providers()
      }
    } catch {
      handleSessionError(error)
    }
  }

  func refreshProviders() async throws {
    providers = try await client.providers()
  }

  @discardableResult
  func saveProvider(_ payload: [String: JSONValue]) async throws -> ProviderView {
    do {
      let provider = try await client.saveProvider(payload)
      providers = try await client.providers()
      noticeMessage = "发信渠道已保存"
      return provider
    } catch {
      handleSessionError(error, showMessage: false)
      throw error
    }
  }

  func setDefaultProvider(_ provider: ProviderView) async throws {
    do {
      try await client.setDefaultProvider(id: provider.id)
      providers = try await client.providers()
      noticeMessage = "默认发信渠道已更新"
    } catch {
      handleSessionError(error, showMessage: false)
      throw error
    }
  }

  func deleteProvider(_ provider: ProviderView) async throws {
    do {
      try await client.deleteProvider(id: provider.id)
      providers = try await client.providers()
      noticeMessage = "发信渠道已删除"
    } catch {
      handleSessionError(error, showMessage: false)
      throw error
    }
  }

  func fetchProviderDomains(_ provider: ProviderView) async throws -> [String] {
    do {
      let response = try await client.fetchProviderDomains(id: provider.id)
      providers = try await client.providers()
      return response.domains
    } catch {
      handleSessionError(error, showMessage: false)
      throw error
    }
  }

  func testProvider(_ provider: ProviderView, from: String, to: String) async throws
    -> ProviderTestResult.Result
  {
    try await client.testProvider(id: provider.id, from: from, to: to).result
  }

  func changePassword(current: String, new: String) async throws {
    do {
      try await client.changePassword(current: current, new: new)
      noticeMessage = "密码已更新"
    } catch {
      handleSessionError(error, showMessage: false)
      throw error
    }
  }

  func saveAI(enabled: Bool, baseURL: String, apiKey: String, model: String) async throws {
    do {
      let ai = try await client.saveAIConfig(
        .init(enabled: enabled, baseUrl: baseURL, apiKey: apiKey, model: model))
      if let current = aiConfiguration {
        aiConfiguration = .init(ai: ai, telegram: current.telegram, categories: current.categories)
      }
      noticeMessage = "AI 设置已保存"
    } catch {
      handleSessionError(error, showMessage: false)
      throw error
    }
  }

  func testAI() async throws -> OperationTestResponse {
    try await client.testAIConfig()
  }

  func saveTelegram(
    enabled: Bool, botToken: String, chatID: String, categories: [String]
  ) async throws {
    do {
      let telegram = try await client.saveTelegram(
        .init(
          enabled: enabled, botToken: botToken, chatId: chatID,
          onlyCategories: categories))
      if let current = aiConfiguration {
        aiConfiguration = .init(ai: current.ai, telegram: telegram, categories: current.categories)
      }
      noticeMessage = "Telegram 设置已保存"
    } catch {
      handleSessionError(error, showMessage: false)
      throw error
    }
  }

  func testTelegram() async throws -> OperationTestResponse {
    try await client.testTelegram()
  }

  func saveStorage(backend: String, retentionDays: Int) async throws {
    do {
      var config = try await client.saveStorageBackend(backend)
      let retention = try await client.saveRetention(days: retentionDays)
      config = .init(
        backend: config.backend,
        configuredBackend: config.configuredBackend,
        r2Available: config.r2Available,
        kvAvailable: config.kvAvailable,
        outboundRetentionDays: retention.outboundRetentionDays,
        outboundRetentionOptions: retention.outboundRetentionOptions
      )
      storageConfiguration = config
      noticeMessage = "存储设置已保存"
      await refreshOverviewResources()
    } catch {
      handleSessionError(error, showMessage: false)
      throw error
    }
  }

  @discardableResult
  func createMailbox(address: String, displayName: String, isCatchAll: Bool) async throws
    -> Mailbox
  {
    do {
      let mailbox = try await client.createMailbox(
        .init(address: address, displayName: displayName.nilIfBlank, isCatchAll: isCatchAll))
      mailboxes = try await client.mailboxes()
      noticeMessage = "信箱已创建"
      return mailbox
    } catch {
      handleSessionError(error, showMessage: false)
      throw error
    }
  }

  func updateMailbox(_ mailbox: Mailbox, displayName: String?, isCatchAll: Bool?) async throws {
    do {
      _ = try await client.updateMailbox(
        id: mailbox.id,
        payload: .init(displayName: displayName, isCatchAll: isCatchAll))
      mailboxes = try await client.mailboxes()
      noticeMessage = "信箱已更新"
    } catch {
      handleSessionError(error, showMessage: false)
      throw error
    }
  }

  func deleteMailbox(_ mailbox: Mailbox) async throws {
    do {
      try await client.deleteMailbox(id: mailbox.id, confirmCatchAll: mailbox.isCatchAll)
      mailboxes = try await client.mailboxes()
      noticeMessage = "信箱已删除"
    } catch {
      handleSessionError(error, showMessage: false)
      throw error
    }
  }

  func download(_ attachment: MessageAttachment) async {
    do {
      let (data, _) = try await client.attachmentData(downloadPath: attachment.downloadUrl)
      let panel = NSSavePanel()
      panel.nameFieldStringValue = attachment.filename
      panel.canCreateDirectories = true
      guard panel.runModal() == .OK, let destination = panel.url else { return }
      try data.write(to: destination, options: .atomic)
      noticeMessage = "附件已保存"
    } catch {
      handleSessionError(error)
    }
  }

  func clearNotice() {
    noticeMessage = nil
    errorMessage = nil
  }

  func startCompose(replyingTo message: MessageDetail? = nil) {
    composeAttachments = []
    if let message {
      composeSeed = ComposeSeed(
        from: message.mailboxAddress ?? mailboxes.first?.address ?? "",
        to: message.replyTo?.email ?? message.from.email,
        subject: message.subject.lowercased().hasPrefix("re:")
          ? message.subject : "Re: \(message.subject)",
        body: "\n\n> \(message.snippet.replacingOccurrences(of: "\n", with: "\n> "))"
      )
    } else {
      composeSeed = ComposeSeed(from: mailboxes.first?.address ?? "")
    }
    isComposing = true
  }

  static func folderTitle(_ folder: String) -> String {
    switch folder {
    case "inbox": "收件箱"
    case "sent": "已发送"
    case "archive": "归档"
    case "spam": "垃圾邮件"
    case "trash": "废纸篓"
    default: folder
    }
  }

  private func resolveAuthentication() async {
    do {
      let setup = try await client.setupStatus()
      if setup.needsSetup {
        phase = .setup
        return
      }
      try await loadSession()
    } catch let error as APIClientError where error.isUnauthorized {
      phase = .signedOut
    } catch {
      phase = .connection
      show(error)
    }
  }

  private func loadSession() async throws {
    let session = try await client.sessionInfo()
    user = session.user
    mailboxes = session.mailboxes
    if selectedMailboxId != "all", !mailboxes.contains(where: { $0.id == selectedMailboxId }) {
      selectedMailboxId = "all"
    }
    phase = .authenticated
    async let foldersTask = client.folders()
    folders = try await foldersTask
    await refreshOverview()
  }

  private func refreshStats() async {
    do {
      stats = try await client.stats(mailboxId: selectedMailboxId)
    } catch {
      handleSessionError(error)
    }
  }

  private func refreshMessages() async {
    let requestID = UUID()
    listRequestID = requestID
    isLoading = true
    defer { if listRequestID == requestID { isLoading = false } }
    do {
      let response = try await client.messages(
        mailboxId: selectedMailboxId,
        folder: selectedFolder,
        query: searchText
      )
      guard listRequestID == requestID else { return }
      messages = response.items
      nextCursor = response.nextCursor
    } catch {
      guard listRequestID == requestID else { return }
      handleSessionError(error)
    }
  }

  private func reloadSelectedDetail() async {
    guard let selectedMessageId,
      let summary = messages.first(where: { $0.id == selectedMessageId })
    else { return }
    do {
      detail = try await client.message(
        id: selectedMessageId,
        mailboxId: summary.mailboxId ?? selectedMailboxId
      )
    } catch {
      handleSessionError(error)
    }
  }

  private func updateSummary(id: String, isRead: Bool? = nil, isStarred: Bool? = nil) {
    messages = messages.map { message in
      message.id == id ? message.updating(isRead: isRead, isStarred: isStarred) : message
    }
  }

  private func handleSessionError(_ error: Error, showMessage: Bool = true) {
    if let apiError = error as? APIClientError, apiError.isUnauthorized {
      clearWorkspace()
      phase = .signedOut
      errorMessage = "登录已过期，请重新登录"
    } else if showMessage {
      show(error)
    }
  }

  private func show(_ error: Error) {
    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
  }

  private func clearWorkspace() {
    user = nil
    mailboxes = []
    contacts = []
    contactsErrorMessage = nil
    folders = []
    stats = []
    messages = []
    usage = nil
    managedAttachments = []
    providers = []
    aiConfiguration = nil
    storageConfiguration = nil
    updateVersion = nil
    workspace = .overview
    detail = nil
    selectedMessageId = nil
    nextCursor = nil
    composeAttachments = []
  }

  private static func addressList(_ value: String) -> [String]? {
    let result = value.split(whereSeparator: { $0 == "," || $0 == ";" })
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return result.isEmpty ? nil : result
  }
}
