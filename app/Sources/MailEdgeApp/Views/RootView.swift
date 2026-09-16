import SwiftUI

struct RootView: View {
  @Bindable var store: AppStore

  var body: some View {
    ZStack {
      LiquidBackdrop()
      switch store.phase {
      case .launching:
        ProgressView("正在启动 MailEdge…")
          .controlSize(.large)
      case .connection:
        ConnectionView(store: store)
      case .setup:
        SetupView(store: store)
      case .signedOut:
        LoginView(store: store)
      case .authenticated:
        MailShellView(store: store)
      }
    }
    .frame(minWidth: 980, minHeight: 640)
    .background {
      UnifiedWindowChrome()
        .allowsHitTesting(false)
    }
    .task { await store.bootstrap() }
  }
}

private struct ConnectionView: View {
  @Bindable var store: AppStore
  @State private var endpoint = ""
  @FocusState private var endpointFocused: Bool

  var body: some View {
    AuthCard(
      eyebrow: "MACOS CLIENT",
      title: "连接 MailEdge",
      subtitle: "填写网页版正在使用的同一地址。账户、信箱与邮件继续保存在你的 Worker 中，客户端不经过其他中转服务。"
    ) {
      VStack(alignment: .leading, spacing: 10) {
        Text("服务器地址")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        AuthInputChrome(isFocused: endpointFocused) {
          TextField("https://your-worker.workers.dev", text: $endpoint)
            .textContentType(.URL)
            .focused($endpointFocused)
            .onSubmit(connect)
        }
        Text("复制网页版地址栏中的域名即可；本地调试可填写 http://127.0.0.1:8787。")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }

      ErrorBanner(message: store.errorMessage)

      Button(action: connect) {
        HStack {
          if store.isLoading { ProgressView().controlSize(.small) }
          Text(store.isLoading ? "正在验证…" : "连接服务器")
          Image(systemName: "arrow.right")
        }
        .frame(maxWidth: .infinity, minHeight: AuthCardLayout.controlHeight)
      }
      .prominentGlassButton()
      .disabled(store.isLoading || endpoint.nilIfBlank == nil)
    }
    .onAppear { endpoint = store.serverURL }
  }

  private func connect() {
    Task { await store.connect(to: endpoint) }
  }
}

private struct LoginView: View {
  private enum Field: Hashable { case email, password }

  @Bindable var store: AppStore
  @State private var email = ""
  @State private var password = ""
  @FocusState private var focusedField: Field?

  var body: some View {
    AuthCard(
      eyebrow: store.serverURL.replacingOccurrences(of: "https://", with: ""),
      title: "欢迎回来",
      subtitle: "登录后即可在 Mac 上处理你的所有 MailEdge 信箱。"
    ) {
      VStack(spacing: 12) {
        AuthInputChrome(isFocused: focusedField == .email) {
          TextField("邮箱", text: $email)
            .textContentType(.username)
            .focused($focusedField, equals: .email)
            .onSubmit { focusedField = .password }
        }
        AuthInputChrome(isFocused: focusedField == .password) {
          SecureField("密码", text: $password)
            .textContentType(.password)
            .focused($focusedField, equals: .password)
            .onSubmit(signIn)
        }
      }

      ErrorBanner(message: store.errorMessage)

      Button(action: signIn) {
        HStack {
          if store.isLoading { ProgressView().controlSize(.small) }
          Text(store.isLoading ? "正在登录…" : "登录")
        }
        .frame(maxWidth: .infinity, minHeight: AuthCardLayout.controlHeight)
      }
      .prominentGlassButton()
      .disabled(store.isLoading || email.nilIfBlank == nil || password.isEmpty)

      Button("更换服务器") { store.changeServer() }
        .buttonStyle(.plain)
        .foregroundStyle(MailEdgePalette.blue)
        .frame(maxWidth: .infinity)
    }
  }

  private func signIn() {
    Task { await store.login(email: email, password: password) }
  }
}

private struct SetupView: View {
  private enum Field: Hashable { case name, email, mailbox, password }

  @Bindable var store: AppStore
  @State private var name = ""
  @State private var email = ""
  @State private var mailbox = ""
  @State private var password = ""
  @FocusState private var focusedField: Field?

  var body: some View {
    AuthCard(
      eyebrow: "首次初始化",
      title: "创建管理员",
      subtitle: "这是全新的 MailEdge 实例。创建账户并绑定第一个收件地址。"
    ) {
      VStack(spacing: 12) {
        AuthInputChrome(isFocused: focusedField == .name) {
          TextField("显示名称（可选）", text: $name)
            .focused($focusedField, equals: .name)
            .onSubmit { focusedField = .email }
        }
        AuthInputChrome(isFocused: focusedField == .email) {
          TextField("管理员邮箱", text: $email)
            .textContentType(.username)
            .focused($focusedField, equals: .email)
            .onSubmit { focusedField = .mailbox }
        }
        AuthInputChrome(isFocused: focusedField == .mailbox) {
          TextField("首个收件地址（默认同管理员邮箱）", text: $mailbox)
            .focused($focusedField, equals: .mailbox)
            .onSubmit { focusedField = .password }
        }
        AuthInputChrome(isFocused: focusedField == .password) {
          SecureField("密码（至少 8 位）", text: $password)
            .textContentType(.newPassword)
            .focused($focusedField, equals: .password)
            .onSubmit(create)
        }
      }

      ErrorBanner(message: store.errorMessage)

      Button(action: create) {
        HStack {
          if store.isLoading { ProgressView().controlSize(.small) }
          Text(store.isLoading ? "正在创建…" : "创建并进入")
        }
        .frame(maxWidth: .infinity, minHeight: AuthCardLayout.controlHeight)
      }
      .prominentGlassButton()
      .disabled(store.isLoading || email.nilIfBlank == nil || password.count < 8)

      Button("更换服务器") { store.changeServer() }
        .buttonStyle(.plain)
        .foregroundStyle(MailEdgePalette.blue)
        .frame(maxWidth: .infinity)
    }
  }

  private func create() {
    Task { await store.setup(email: email, password: password, name: name, mailbox: mailbox) }
  }
}

private enum AuthCardLayout {
  static let formWidth: CGFloat = 360
  static let cardWidth: CGFloat = 448
  static let controlHeight: CGFloat = 46
}

private struct AuthInputChrome<Content: View>: View {
  let isFocused: Bool
  @ViewBuilder let content: Content

  init(isFocused: Bool, @ViewBuilder content: () -> Content) {
    self.isFocused = isFocused
    self.content = content()
  }

  var body: some View {
    content
      .textFieldStyle(.plain)
      .font(.body)
      .padding(.horizontal, 14)
      .frame(maxWidth: .infinity)
      .frame(height: AuthCardLayout.controlHeight)
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .background(
        MailEdgePalette.blue.opacity(isFocused ? 0.075 : 0.025),
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(
            isFocused ? MailEdgePalette.blue.opacity(0.78) : Color.primary.opacity(0.10),
            lineWidth: isFocused ? 1.6 : 0.8
          )
      }
      .shadow(color: isFocused ? MailEdgePalette.blue.opacity(0.16) : .clear, radius: 8)
      .animation(.easeOut(duration: 0.16), value: isFocused)
  }
}

private struct AuthCard<Content: View>: View {
  let eyebrow: String
  let title: String
  let subtitle: String
  @ViewBuilder let content: Content

  init(eyebrow: String, title: String, subtitle: String, @ViewBuilder content: () -> Content) {
    self.eyebrow = eyebrow
    self.title = title
    self.subtitle = subtitle
    self.content = content()
  }

  var body: some View {
    VStack(spacing: 24) {
      MailEdgeMark(size: 58)
      VStack(spacing: 8) {
        Text(eyebrow.uppercased())
          .font(.caption2.weight(.bold))
          .tracking(1.4)
          .foregroundStyle(MailEdgePalette.blue)
          .lineLimit(1)
        Text(title).font(.largeTitle.bold())
        Text(subtitle)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .frame(width: AuthCardLayout.formWidth)
      }
      VStack(spacing: 16) { content }
        .frame(width: AuthCardLayout.formWidth)
        .controlSize(.large)
    }
    .padding(.vertical, 34)
    .frame(width: AuthCardLayout.cardWidth)
    .liquidGlass(cornerRadius: 30, tint: MailEdgePalette.blue.opacity(0.06))
    .padding(40)
  }
}

struct ErrorBanner: View {
  let message: String?

  var body: some View {
    if let message {
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .font(.callout)
        .foregroundStyle(.red)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }
  }
}
