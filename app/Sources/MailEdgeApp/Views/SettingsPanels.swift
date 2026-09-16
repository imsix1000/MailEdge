import AppKit
import SwiftUI

struct ProviderSettingsPanel: View {
  @Bindable var store: AppStore
  @State private var selectedType = "cloudflare"
  @State private var errorMessage: String?

  private let types = ["cloudflare", "sendflare", "resend", "smtp"]

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let errorMessage { SettingsInlineNotice(message: errorMessage, isError: true) }

      HStack(alignment: .top, spacing: 14) {
        VStack(spacing: 7) {
          ForEach(types, id: \.self) { type in
            let provider = store.providers.first { $0.type == type }
            Button { selectedType = type } label: {
              HStack(spacing: 10) {
                Image(systemName: providerIcon(type)).frame(width: 19)
                VStack(alignment: .leading, spacing: 2) {
                  Text(provider?.name ?? providerName(type))
                    .font(.callout.weight(.semibold)).lineLimit(1)
                  Text(provider == nil ? "未配置" : "优先级 \(provider?.priority ?? 100)")
                    .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if provider?.isDefault == true {
                  Text("默认").font(.caption2.bold()).foregroundStyle(MailEdgePalette.blue)
                } else if provider != nil {
                  Circle().fill(provider?.lastError == nil ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                }
              }
              .padding(.horizontal, 11)
              .frame(minHeight: 52)
              .background(
                selectedType == type ? MailEdgePalette.blue.opacity(0.10) : Color.clear,
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
              )
              .overlay {
                if selectedType == type {
                  RoundedRectangle(cornerRadius: 13).strokeBorder(
                    MailEdgePalette.blue.opacity(0.25), lineWidth: 1)
                }
              }
            }
            .buttonStyle(.plain)
          }
        }
        .padding(8)
        .frame(width: 235)
        .liquidGlass(cornerRadius: 18, tint: MailEdgePalette.blue.opacity(0.015))

        ProviderEditor(
          store: store,
          type: selectedType,
          provider: store.providers.first { $0.type == selectedType },
          reportError: { errorMessage = $0 }
        )
        .id("\(selectedType):\(store.providers.first { $0.type == selectedType }?.id ?? "new")")
        .frame(maxWidth: .infinity)
      }
    }
  }

  private func providerIcon(_ type: String) -> String {
    switch type {
    case "cloudflare": "cloud.fill"
    case "sendflare": "bolt.fill"
    case "resend": "paperplane.fill"
    default: "server.rack"
    }
  }

  private func providerName(_ type: String) -> String {
    switch type {
    case "cloudflare": "Cloudflare Email Service"
    case "sendflare": "Sendflare"
    case "resend": "Resend"
    default: "SMTP"
    }
  }
}

private struct ProviderEditor: View {
  @Bindable var store: AppStore
  let type: String
  let provider: ProviderView?
  let reportError: (String?) -> Void

  @State private var name: String
  @State private var enabled: Bool
  @State private var priority: Int
  @State private var apiKey = ""
  @State private var token = ""
  @State private var secret = ""
  @State private var baseURL: String
  @State private var domains: String
  @State private var fromName: String
  @State private var smtpHost: String
  @State private var smtpPort: Int
  @State private var smtpSecurity: String
  @State private var smtpUsername: String
  @State private var smtpPassword = ""
  @State private var testFrom: String
  @State private var testTo = ""
  @State private var busy = false
  @State private var localNotice: String?

  init(
    store: AppStore, type: String, provider: ProviderView?, reportError: @escaping (String?) -> Void
  ) {
    self.store = store
    self.type = type
    self.provider = provider
    self.reportError = reportError
    _name = State(initialValue: provider?.name ?? Self.defaultName(type))
    _enabled = State(initialValue: provider?.isEnabled ?? true)
    _priority = State(initialValue: provider?.priority ?? 100)
    _baseURL = State(initialValue: provider?.config["baseUrl"]?.stringValue ?? "")
    _domains = State(initialValue: Self.stringList(provider?.config["verifiedDomains"]))
    _fromName = State(initialValue: provider?.config["fromName"]?.stringValue ?? "")
    _smtpHost = State(initialValue: provider?.config["host"]?.stringValue ?? "")
    _smtpPort = State(initialValue: Self.integer(provider?.config["port"]) ?? 587)
    _smtpSecurity = State(initialValue: provider?.config["security"]?.stringValue ?? "starttls")
    _smtpUsername = State(initialValue: provider?.config["username"]?.stringValue ?? "")
    _testFrom = State(initialValue: store.mailboxes.first?.address ?? "")
  }

  var body: some View {
    SettingsSurface {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(Self.defaultName(type)).font(.headline)
          Text(provider == nil ? "填写配置后即可启用这个渠道。" : "渠道已连接，可更新配置或发送测试邮件。")
            .font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        if provider?.isDefault == true {
          Text("默认渠道")
            .font(.caption.bold()).foregroundStyle(MailEdgePalette.blue)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(MailEdgePalette.blue.opacity(0.10), in: Capsule())
        }
      }

      if let lastError = provider?.lastError {
        SettingsInlineNotice(message: lastError, isError: true)
      }
      if type == "cloudflare" {
        SettingsInlineNotice(
          message:
            "send_email 绑定只代表 Worker 可以调用接口。请先在 Cloudflare Email Service → Email Sending 完成发件域 onboarding 与 DNS 验证。未完成时只能发给账户里已验证的 destination address。",
          isError: false)
      }
      if let localNotice {
        SettingsInlineNotice(message: localNotice, isError: false)
      }

      SettingsFormRow("显示名称") {
        TextField("渠道名称", text: $name).settingsTextField()
      }

      if type == "resend" {
        SettingsFormRow("API Key", hint: provider == nil ? nil : "留空表示保留现有密钥") {
          SecureField(provider == nil ? "re_..." : "••••••••", text: $apiKey)
            .settingsTextField()
        }
      }

      if type == "sendflare" {
        SettingsFormRow("API Token", hint: provider == nil ? nil : "留空表示保留现有密钥") {
          SecureField(provider == nil ? "sf_..." : "••••••••", text: $token)
            .settingsTextField()
        }
        SettingsFormRow("API Secret", hint: "可选；留空沿用现有值") {
          SecureField(provider == nil ? "可选" : "••••••••", text: $secret)
            .settingsTextField()
        }
        SettingsFormRow("API 地址") {
          TextField("https://api.sendflare.com", text: $baseURL).settingsTextField()
        }
      }

      if type == "smtp" {
        SettingsFormRow("快速预设") {
          Button("Gmail") {
            smtpHost = "smtp.gmail.com"
            smtpPort = 587
            smtpSecurity = "starttls"
          }
          .glassButton()
        }
        SettingsFormRow("SMTP 主机") {
          TextField("smtp.gmail.com", text: $smtpHost).settingsTextField()
        }
        SettingsFormRow("端口") {
          TextField("587", value: $smtpPort, format: .number).settingsTextField()
        }
        SettingsFormRow("连接安全") {
          Picker("连接安全", selection: $smtpSecurity) {
            Text("STARTTLS（587）").tag("starttls")
            Text("TLS（465）").tag("tls")
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          .liquidGlass(cornerRadius: 12, tint: Color.primary.opacity(0.012), interactive: true)
        }
        SettingsFormRow("用户名") {
          TextField("you@gmail.com", text: $smtpUsername).settingsTextField()
        }
        SettingsFormRow("密码", hint: provider == nil ? "Gmail 请使用应用专用密码" : "留空表示保留现有密码") {
          SecureField(provider == nil ? "" : "••••••••", text: $smtpPassword)
            .settingsTextField()
        }
      }

      if type == "resend" || type == "sendflare" {
        SettingsFormRow("发件人名称") {
          TextField("MailEdge", text: $fromName).settingsTextField()
        }
        SettingsFormRow("已验证域名", hint: "支持逗号、分号或换行分隔", vertical: true) {
          TextEditor(text: $domains)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(9)
            .frame(minHeight: 78)
            .liquidGlass(cornerRadius: 12, tint: Color.primary.opacity(0.012), interactive: true)
        }
      }

      SettingsFormRow("优先级", hint: "数字越小，尝试顺序越靠前") {
        TextField("100", value: $priority, format: .number).settingsTextField()
      }
      SettingsFormRow("启用") {
        Toggle("允许系统使用这个渠道发信", isOn: $enabled).toggleStyle(.switch)
      }

      HStack(spacing: 10) {
        Button {
          Task { await save() }
        } label: {
          Label("保存", systemImage: "checkmark")
        }
        .prominentGlassButton()
        .disabled(busy || name.nilIfBlank == nil)

        if let provider, !provider.isDefault {
          Button("设为默认") { Task { await setDefault(provider) } }
            .glassButton()
            .disabled(busy)
        }

        if let provider, type == "resend" || type == "sendflare" {
          Button("同步域名") { Task { await syncDomains(provider) } }
            .glassButton()
            .disabled(busy)
        }
        Spacer()
        if let provider {
          Button(role: .destructive) { Task { await remove(provider) } } label: {
            Image(systemName: "trash")
          }
          .circularGlassButton(tint: .red.opacity(0.10), size: 40)
          .disabled(busy)
        }
      }

      if let provider {
        Divider().opacity(0.4)
        Text("发送测试邮件").font(.headline)
        SettingsFormRow("发件地址") {
          Picker("发件地址", selection: $testFrom) {
            ForEach(store.mailboxes) { mailbox in Text(mailbox.address).tag(mailbox.address) }
          }
          .labelsHidden().pickerStyle(.menu)
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          .liquidGlass(cornerRadius: 12, tint: Color.primary.opacity(0.012), interactive: true)
        }
        SettingsFormRow("收件地址") {
          TextField("name@example.com", text: $testTo).settingsTextField()
        }
        Button("发送测试") { Task { await test(provider) } }
          .glassButton()
          .disabled(busy || testFrom.isEmpty || testTo.nilIfBlank == nil)
      }
    }
  }

  private func save() async {
    busy = true
    reportError(nil)
    localNotice = nil
    defer { busy = false }
    var config: [String: JSONValue]
    switch type {
    case "resend":
      config = [
        "apiKey": .string(apiKey), "verifiedDomains": .string(domains),
        "fromName": .string(fromName),
      ]
    case "sendflare":
      config = [
        "token": .string(token), "secret": .string(secret), "baseUrl": .string(baseURL),
        "verifiedDomains": .string(domains), "fromName": .string(fromName),
      ]
    case "smtp":
      config = [
        "host": .string(smtpHost), "port": .number(Double(smtpPort)),
        "username": .string(smtpUsername), "password": .string(smtpPassword),
        "security": .string(smtpSecurity),
      ]
    default:
      config = ["type": .string("cloudflare")]
    }
    var payload: [String: JSONValue] = [
      "name": .string(name), "type": .string(type), "isEnabled": .bool(enabled),
      "priority": .number(Double(priority)), "config": .object(config),
    ]
    if let provider { payload["id"] = .string(provider.id) }
    do { _ = try await store.saveProvider(payload) } catch { reportError(error.localizedDescription) }
  }

  private func setDefault(_ provider: ProviderView) async {
    busy = true; defer { busy = false }
    do { try await store.setDefaultProvider(provider) } catch { reportError(error.localizedDescription) }
  }

  private func remove(_ provider: ProviderView) async {
    busy = true; defer { busy = false }
    do { try await store.deleteProvider(provider) } catch { reportError(error.localizedDescription) }
  }

  private func syncDomains(_ provider: ProviderView) async {
    busy = true; defer { busy = false }
    do {
      domains = try await store.fetchProviderDomains(provider).joined(separator: ", ")
      localNotice = domains.isEmpty ? "没有检测到已验证域名" : "域名已同步"
    } catch { reportError(error.localizedDescription) }
  }

  private func test(_ provider: ProviderView) async {
    busy = true; localNotice = nil; defer { busy = false }
    do {
      let result = try await store.testProvider(provider, from: testFrom, to: testTo)
      if result.success { localNotice = result.providerMessageId ?? "测试邮件已发送" }
      else { reportError(result.error ?? "测试发送失败") }
    } catch { reportError(error.localizedDescription) }
  }

  private static func defaultName(_ type: String) -> String {
    [
      "cloudflare": "Cloudflare Email Service", "sendflare": "Sendflare",
      "resend": "Resend", "smtp": "SMTP",
    ][type] ?? type
  }

  private static func integer(_ value: JSONValue?) -> Int? {
    if case .number(let value) = value { return Int(value) }
    return nil
  }

  private static func stringList(_ value: JSONValue?) -> String {
    guard case .array(let values) = value else { return "" }
    return values.compactMap(\.stringValue).joined(separator: ", ")
  }
}

struct AISettingsPanel: View {
  @Bindable var store: AppStore
  @State private var enabled = false
  @State private var baseURL = ""
  @State private var apiKey = ""
  @State private var model = ""
  @State private var busy = false
  @State private var notice: (String, Bool)?
  @State private var hydrated = false

  var body: some View {
    SettingsSurface {
      if let notice { SettingsInlineNotice(message: notice.0, isError: notice.1) }
      SettingsFormRow("启用 AI") {
        Toggle("在邮件阅读中启用摘要、分类与回复", isOn: $enabled).toggleStyle(.switch)
      }
      SettingsFormRow("API 地址") {
        TextField("https://api.openai.com/v1", text: $baseURL).settingsTextField()
      }
      SettingsFormRow("API Key", hint: store.aiConfiguration?.ai.hasKey == true ? "留空表示沿用已保存的密钥" : nil) {
        SecureField(store.aiConfiguration?.ai.hasKey == true ? "••••••••" : "sk-...", text: $apiKey)
          .settingsTextField()
      }
      SettingsFormRow("模型") {
        TextField("gpt-4o-mini", text: $model).settingsTextField()
      }
      HStack(spacing: 10) {
        Button("保存") { Task { await save() } }.prominentGlassButton().disabled(busy)
        Button("测试连接") { Task { await test() } }.glassButton().disabled(busy || store.aiConfiguration?.ai.hasKey != true)
        if busy { ProgressView().controlSize(.small) }
      }
    }
    .onChange(of: store.aiConfiguration) { _, _ in hydrate() }
    .onAppear { hydrate() }
  }

  private func hydrate() {
    guard !hydrated, let config = store.aiConfiguration?.ai else { return }
    enabled = config.enabled
    baseURL = config.baseUrl ?? ""
    model = config.model ?? ""
    hydrated = true
  }

  private func save() async {
    busy = true; notice = nil; defer { busy = false }
    do {
      try await store.saveAI(enabled: enabled, baseURL: baseURL, apiKey: apiKey, model: model)
      apiKey = ""; notice = ("AI 设置已保存", false)
    } catch { notice = (error.localizedDescription, true) }
  }

  private func test() async {
    busy = true; notice = nil; defer { busy = false }
    do {
      let result = try await store.testAI()
      notice = (result.ok ? (result.reply ?? "连接成功") : (result.error ?? "连接失败"), !result.ok)
    } catch { notice = (error.localizedDescription, true) }
  }
}

struct TelegramSettingsPanel: View {
  @Bindable var store: AppStore
  @State private var enabled = false
  @State private var botToken = ""
  @State private var chatID = ""
  @State private var selectedCategories: Set<String> = []
  @State private var busy = false
  @State private var hydrated = false
  @State private var notice: (String, Bool)?

  private let categories = ["important", "updates", "promotions", "verification", "social", "other"]

  var body: some View {
    SettingsSurface {
      if let notice { SettingsInlineNotice(message: notice.0, isError: notice.1) }
      SettingsFormRow("启用 Telegram") {
        Toggle("新邮件到达时发送通知", isOn: $enabled).toggleStyle(.switch)
      }
      SettingsFormRow("Bot Token", hint: store.aiConfiguration?.telegram.hasToken == true ? "留空表示沿用现有 Token" : "从 BotFather 获取") {
        SecureField(store.aiConfiguration?.telegram.hasToken == true ? "••••••••" : "123456:ABC-...", text: $botToken)
          .settingsTextField()
      }
      SettingsFormRow("Chat ID") {
        TextField("123456789", text: $chatID).settingsTextField()
      }
      SettingsFormRow("通知分类", hint: "未选择时通知所有分类", vertical: true) {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], alignment: .leading, spacing: 10) {
          ForEach(categories, id: \.self) { category in
            Toggle(categoryTitle(category), isOn: categoryBinding(category)).toggleStyle(.checkbox)
          }
        }
      }
      HStack(spacing: 10) {
        Button("保存") { Task { await save() } }.prominentGlassButton().disabled(busy)
        Button("发送测试通知") { Task { await test() } }.glassButton()
          .disabled(busy || store.aiConfiguration?.telegram.hasToken != true)
        if busy { ProgressView().controlSize(.small) }
      }
    }
    .onChange(of: store.aiConfiguration) { _, _ in hydrate() }
    .onAppear { hydrate() }
  }

  private func categoryBinding(_ category: String) -> Binding<Bool> {
    Binding(
      get: { selectedCategories.contains(category) },
      set: { selected in
        if selected { selectedCategories.insert(category) }
        else { selectedCategories.remove(category) }
      }
    )
  }

  private func categoryTitle(_ key: String) -> String {
    ["important": "重要", "updates": "更新", "promotions": "推广", "verification": "验证码", "social": "社交", "other": "其他"][key] ?? key
  }

  private func hydrate() {
    guard !hydrated, let config = store.aiConfiguration?.telegram else { return }
    enabled = config.enabled
    chatID = config.chatId ?? ""
    selectedCategories = Set(config.onlyCategories ?? [])
    hydrated = true
  }

  private func save() async {
    busy = true; notice = nil; defer { busy = false }
    do {
      try await store.saveTelegram(
        enabled: enabled, botToken: botToken, chatID: chatID,
        categories: Array(selectedCategories))
      botToken = ""; notice = ("Telegram 设置已保存", false)
    } catch { notice = (error.localizedDescription, true) }
  }

  private func test() async {
    busy = true; notice = nil; defer { busy = false }
    do {
      let result = try await store.testTelegram()
      notice = (result.ok ? "测试通知已发送" : (result.error ?? "发送失败"), !result.ok)
    } catch { notice = (error.localizedDescription, true) }
  }
}

struct UpdateSettingsPanel: View {
  @Bindable var store: AppStore

  var body: some View {
    SettingsSurface {
      HStack(spacing: 15) {
        ZStack {
          RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill((store.updateVersion?.updateAvailable == true ? Color.orange : Color.green).opacity(0.12))
          Image(systemName: store.updateVersion?.updateAvailable == true ? "arrow.down.circle.fill" : "checkmark.circle.fill")
            .font(.title2)
            .foregroundStyle(store.updateVersion?.updateAvailable == true ? .orange : .green)
        }
        .frame(width: 54, height: 54)
        VStack(alignment: .leading, spacing: 4) {
          Text(store.updateVersion?.updateAvailable == true ? "发现新版本" : "当前已是最新版本")
            .font(.headline)
          Text("升级由 MailEdge 部署向导完成，不会在后台静默更新。")
            .font(.caption).foregroundStyle(.secondary)
        }
      }

      Divider().opacity(0.4)
      valueRow("当前版本", store.updateVersion?.currentVersion ?? "—")
      valueRow("最新版本", store.updateVersion?.availableVersion ?? store.updateVersion?.currentVersion ?? "—")
      valueRow("检查时间", store.updateVersion?.checkedAt ?? "—")

      HStack(spacing: 10) {
        Button("重新检查") { Task { await store.loadSettingsData() } }.glassButton()
          .disabled(store.isLoadingSettings)
        Button("打开部署向导") {
          if let url = URL(string: "https://mailedge.sh/") { NSWorkspace.shared.open(url) }
        }
        .prominentGlassButton()
      }
    }
  }

  private func valueRow(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title).foregroundStyle(.secondary)
      Spacer()
      Text(value).fontWeight(.semibold).textSelection(.enabled)
    }
    .font(.callout)
  }
}

struct StorageSettingsPanel: View {
  @Bindable var store: AppStore
  @State private var backend = "r2"
  @State private var retentionDays = 365
  @State private var busy = false
  @State private var hydrated = false
  @State private var notice: (String, Bool)?

  var body: some View {
    SettingsSurface {
      if let notice { SettingsInlineNotice(message: notice.0, isError: notice.1) }
      SettingsFormRow("存储后端", hint: "附件与发信载荷使用这里选择的对象存储", vertical: true) {
        HStack(spacing: 12) {
          StorageOption(
            title: "Cloudflare R2", subtitle: availability(store.storageConfiguration?.r2Available),
            icon: "externaldrive.fill", selected: backend == "r2",
            enabled: store.storageConfiguration?.r2Available == true
          ) { backend = "r2" }
          StorageOption(
            title: "Workers KV", subtitle: availability(store.storageConfiguration?.kvAvailable),
            icon: "cylinder.fill", selected: backend == "kv",
            enabled: store.storageConfiguration?.kvAvailable == true
          ) { backend = "kv" }
        }
      }

      Label(
        backend == "kv" ? "KV 单个附件上限为 25 MB。" : "R2 适合大文件和长期附件存储。",
        systemImage: "info.circle.fill"
      )
      .font(.caption).foregroundStyle(.secondary)

      SettingsFormRow("发件保留周期", hint: "到期后服务端可清理已发送附件") {
        Picker("发件保留周期", selection: $retentionDays) {
          ForEach(store.storageConfiguration?.outboundRetentionOptions ?? [90, 180, 365], id: \.self) {
            Text("\($0) 天").tag($0)
          }
        }
        .labelsHidden().pickerStyle(.menu)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .liquidGlass(cornerRadius: 12, tint: Color.primary.opacity(0.012), interactive: true)
      }

      Button("保存存储设置") { Task { await save() } }
        .prominentGlassButton()
        .disabled(busy || !(backend == "r2" ? store.storageConfiguration?.r2Available == true : store.storageConfiguration?.kvAvailable == true))
    }
    .onChange(of: store.storageConfiguration) { _, _ in hydrate() }
    .onAppear { hydrate() }
  }

  private func availability(_ value: Bool?) -> String {
    value == true ? "当前部署可用" : "未绑定"
  }

  private func hydrate() {
    guard !hydrated, let config = store.storageConfiguration else { return }
    backend = config.backend
    retentionDays = config.outboundRetentionDays
    hydrated = true
  }

  private func save() async {
    busy = true; notice = nil; defer { busy = false }
    do {
      try await store.saveStorage(backend: backend, retentionDays: retentionDays)
      notice = ("存储设置已保存", false)
    } catch { notice = (error.localizedDescription, true) }
  }
}

private struct StorageOption: View {
  let title: String
  let subtitle: String
  let icon: String
  let selected: Bool
  let enabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: icon)
          .font(.title3).foregroundStyle(selected ? MailEdgePalette.blue : Color.secondary)
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.callout.weight(.semibold))
          Text(subtitle).font(.caption2).foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(selected ? MailEdgePalette.blue : Color.secondary)
      }
      .padding(13)
      .frame(maxWidth: .infinity, minHeight: 68)
      .background(
        selected ? MailEdgePalette.blue.opacity(0.09) : Color.primary.opacity(0.02),
        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 14).strokeBorder(
          selected ? MailEdgePalette.blue.opacity(0.34) : Color.primary.opacity(0.09), lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
  }
}

struct MailboxSettingsPanel: View {
  @Bindable var store: AppStore
  @State private var address = ""
  @State private var displayName = ""
  @State private var isCatchAll = false
  @State private var editingID: String?
  @State private var editingName = ""
  @State private var busy = false
  @State private var notice: (String, Bool)?
  @State private var pendingDelete: Mailbox?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let notice { SettingsInlineNotice(message: notice.0, isError: notice.1) }
      SettingsSurface {
        Text("现有信箱").font(.headline)
        if store.mailboxes.isEmpty {
          Text("还没有信箱").foregroundStyle(.secondary)
        } else {
          ForEach(store.mailboxes) { mailbox in
            HStack(spacing: 12) {
              ZStack {
                Circle().fill(MailEdgePalette.blue.opacity(0.11))
                Image(systemName: mailbox.isCatchAll ? "at.badge.plus" : "at")
                  .foregroundStyle(MailEdgePalette.blue)
              }
              .frame(width: 38, height: 38)
              VStack(alignment: .leading, spacing: 2) {
                if editingID == mailbox.id {
                  TextField("显示名称", text: $editingName)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 180)
                } else {
                  Text(mailbox.title).font(.callout.weight(.semibold))
                }
                Text(mailbox.address).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Toggle("全域收件", isOn: catchAllBinding(mailbox)).toggleStyle(.switch)
                .labelsHidden().help("设为 @\(mailbox.domain) 的全域收件地址")
              if editingID == mailbox.id {
                Button { Task { await saveName(mailbox) } } label: { Image(systemName: "checkmark") }
                  .circularGlassButton(size: 36)
                Button { editingID = nil } label: { Image(systemName: "xmark") }
                  .circularGlassButton(size: 36)
              } else {
                Button {
                  editingID = mailbox.id
                  editingName = mailbox.displayName ?? ""
                } label: { Image(systemName: "pencil") }
                .circularGlassButton(size: 36)
              }
              Button(role: .destructive) { pendingDelete = mailbox } label: {
                Image(systemName: "trash")
              }
              .circularGlassButton(tint: .red.opacity(0.09), size: 36)
            }
            .padding(.vertical, 2)
            if mailbox.id != store.mailboxes.last?.id { Divider().opacity(0.35) }
          }
        }
      }

      SettingsSurface {
        Text("添加信箱").font(.headline)
        SettingsFormRow("显示名称", hint: "可选，最多 40 个字符") {
          TextField("例如：工作邮箱", text: $displayName).settingsTextField()
        }
        SettingsFormRow("收件地址") {
          TextField("you@yourdomain.com", text: $address).settingsTextField()
        }
        SettingsFormRow("全域收件", hint: "同一域名只能有一个全域收件信箱") {
          Toggle("接收该域名下未单独创建的地址", isOn: $isCatchAll).toggleStyle(.switch)
        }
        Button("创建信箱") { Task { await create() } }
          .prominentGlassButton()
          .disabled(busy || address.nilIfBlank == nil)
      }
    }
    .confirmationDialog(
      "删除信箱？", isPresented: Binding(
        get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
      ), titleVisibility: .visible
    ) {
      Button("永久删除", role: .destructive) {
        guard let mailbox = pendingDelete else { return }
        Task { await remove(mailbox) }
      }
      Button("取消", role: .cancel) { pendingDelete = nil }
    } message: {
      Text("删除后该地址将不再收件；若为全域收件地址，需要重新指定其他信箱。")
    }
  }

  private func catchAllBinding(_ mailbox: Mailbox) -> Binding<Bool> {
    Binding(
      get: { store.mailboxes.first { $0.id == mailbox.id }?.isCatchAll ?? mailbox.isCatchAll },
      set: { next in Task { await updateCatchAll(mailbox, next: next) } }
    )
  }

  private func create() async {
    busy = true; notice = nil; defer { busy = false }
    do {
      _ = try await store.createMailbox(address: address, displayName: displayName, isCatchAll: isCatchAll)
      address = ""; displayName = ""; isCatchAll = false
      notice = ("信箱已创建", false)
    } catch { notice = (error.localizedDescription, true) }
  }

  private func saveName(_ mailbox: Mailbox) async {
    busy = true; notice = nil; defer { busy = false }
    do {
      try await store.updateMailbox(mailbox, displayName: editingName.nilIfBlank, isCatchAll: nil)
      editingID = nil; notice = ("显示名称已更新", false)
    } catch { notice = (error.localizedDescription, true) }
  }

  private func updateCatchAll(_ mailbox: Mailbox, next: Bool) async {
    busy = true; notice = nil; defer { busy = false }
    do {
      try await store.updateMailbox(mailbox, displayName: mailbox.displayName, isCatchAll: next)
      notice = (next ? "已设为全域收件" : "已取消全域收件", false)
    } catch { notice = (error.localizedDescription, true) }
  }

  private func remove(_ mailbox: Mailbox) async {
    busy = true; notice = nil; defer { busy = false; pendingDelete = nil }
    do {
      try await store.deleteMailbox(mailbox)
      notice = ("信箱已删除", false)
    } catch { notice = (error.localizedDescription, true) }
  }
}

struct AccountSettingsPanel: View {
  @Bindable var store: AppStore
  let dismissSettings: () -> Void
  @State private var currentPassword = ""
  @State private var newPassword = ""
  @State private var busy = false
  @State private var notice: (String, Bool)?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let notice { SettingsInlineNotice(message: notice.0, isError: notice.1) }
      SettingsSurface {
        SettingsFormRow("邮箱") { Text(store.user?.email ?? "—").textSelection(.enabled) }
        SettingsFormRow("名称") { Text(store.user?.name?.nilIfBlank ?? "未设置") }
        SettingsFormRow("权限") {
          Text(store.user?.role == "admin" ? "管理员" : "用户")
            .font(.caption.weight(.semibold)).foregroundStyle(MailEdgePalette.blue)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(MailEdgePalette.blue.opacity(0.10), in: Capsule())
        }
      }

      SettingsSurface {
        Text("修改密码").font(.headline)
        SettingsFormRow("当前密码") {
          SecureField("当前密码", text: $currentPassword).settingsTextField()
        }
        SettingsFormRow("新密码", hint: "至少 8 位") {
          SecureField("新密码", text: $newPassword).settingsTextField()
        }
        Button("更新密码") { Task { await changePassword() } }
          .prominentGlassButton()
          .disabled(busy || currentPassword.isEmpty || newPassword.count < 8)
      }

      SettingsSurface {
        HStack(spacing: 14) {
          Image(systemName: "key.fill")
            .font(.title2).foregroundStyle(MailEdgePalette.blue)
            .frame(width: 44, height: 44)
            .background(MailEdgePalette.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
          VStack(alignment: .leading, spacing: 3) {
            Text("Passkey").font(.headline)
            Text("通行密钥注册会打开同一实例的网页版，由已配置的 Associated Domains 完成验证。")
              .font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Button("打开注册") {
            if let url = URL(string: "\(store.serverURL)/settings/account") { NSWorkspace.shared.open(url) }
          }
          .glassButton()
        }
      }

      HStack {
        Button("退出登录", role: .destructive) {
          dismissSettings()
          Task { await store.logout() }
        }
        .glassButton(tint: .red.opacity(0.10))
        Spacer()
        Text("退出不会删除服务器上的邮件").font(.caption).foregroundStyle(.tertiary)
      }
    }
  }

  private func changePassword() async {
    busy = true; notice = nil; defer { busy = false }
    do {
      try await store.changePassword(current: currentPassword, new: newPassword)
      currentPassword = ""; newPassword = ""; notice = ("密码已更新", false)
    } catch { notice = (error.localizedDescription, true) }
  }
}

struct LegalSettingsPanel: View {
  @Bindable var store: AppStore

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      SettingsSurface {
        HStack(spacing: 14) {
          MailEdgeMark(size: 52)
          VStack(alignment: .leading, spacing: 3) {
            MailEdgeWordmark(size: 24)
            Text("开源、自托管的边缘邮件工作台")
              .font(.callout).foregroundStyle(.secondary)
          }
        }
        Divider().opacity(0.4)
        legalRow("应用", "MailEdge 原生 macOS 客户端")
        legalRow("服务", store.serverURL)
        legalRow("许可", "以项目仓库 LICENSE 文件为准")
        legalRow("数据", "邮件、附件与设置直接保存在你的 Cloudflare 实例")
      }

      SettingsSurface {
        Label("隐私与安全", systemImage: "hand.raised.fill").font(.headline)
        Text("原生客户端直接连接你的 Worker，不经过第三方中转。HTML 邮件默认禁用 JavaScript、表单和远程资源，外部链接交给默认浏览器打开。")
          .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }

      Button {
        if let url = URL(string: "https://github.com/anghunk/MailEdge") { NSWorkspace.shared.open(url) }
      } label: {
        Label("查看项目源码", systemImage: "arrow.up.right.square")
      }
      .glassButton()
    }
  }

  private func legalRow(_ title: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title).foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
      Text(value).fontWeight(.medium).textSelection(.enabled)
      Spacer()
    }
    .font(.callout)
  }
}
