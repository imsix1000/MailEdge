import SwiftUI

struct SettingsView: View {
  @Bindable var store: AppStore
  @Environment(\.dismiss) private var dismiss
  @State private var selectedSection: SettingsSection = .providers
  @Namespace private var selectionNamespace

  private var visibleSections: [SettingsSection] {
    SettingsSection.allCases.filter { !$0.adminOnly || store.user?.role == "admin" }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        MailEdgeMark(size: 34)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          MailEdgeWordmark(size: 17)
          Text("设置").font(.headline)
        }
        Spacer()
        if store.isLoadingSettings {
          ProgressView().controlSize(.small)
        }
        Button { dismiss() } label: {
          Image(systemName: "xmark")
        }
        .circularGlassButton(size: 40)
        .keyboardShortcut(.cancelAction)
        .help("关闭设置")
      }
      .padding(.horizontal, 18)
      .frame(height: 66)
      .background(.ultraThinMaterial)

      Divider().opacity(0.4)

      HStack(spacing: 0) {
        ScrollView {
          VStack(spacing: 7) {
            ForEach(visibleSections) { section in
              Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                  selectedSection = section
                }
              } label: {
                ZStack {
                  if selectedSection == section {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                      .fill(MailEdgePalette.blue.opacity(0.055))
                      .liquidGlass(
                        cornerRadius: 12,
                        tint: MailEdgePalette.blue.opacity(0.13),
                        interactive: true
                      )
                      .matchedGeometryEffect(id: "settings-selection", in: selectionNamespace)
                  }
                  HStack(spacing: 11) {
                    Image(systemName: section.icon)
                      .frame(width: 19)
                      .foregroundStyle(
                        selectedSection == section ? MailEdgePalette.blue : Color.secondary)
                    Text(section.title)
                      .font(.callout.weight(selectedSection == section ? .semibold : .regular))
                    Spacer()
                  }
                  .padding(.horizontal, 13)
                }
                .frame(height: 44)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
              }
              .buttonStyle(.plain)
            }
          }
          .padding(12)
        }
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)

        Divider().opacity(0.45)

        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            SettingsPageHeader(
              title: selectedSection.title,
              subtitle: selectedSection.subtitle,
              icon: selectedSection.icon
            )
            selectedContent
          }
          .id(selectedSection)
          .padding(26)
          .frame(maxWidth: 840, alignment: .topLeading)
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .frame(width: 980, height: 690)
    .background(LiquidBackdrop())
    .task {
      if !visibleSections.contains(selectedSection) {
        selectedSection = visibleSections.first ?? .account
      }
      await store.loadSettingsData()
    }
    .animation(.snappy(duration: 0.25), value: selectedSection)
  }

  @ViewBuilder
  private var selectedContent: some View {
    switch selectedSection {
    case .providers:
      ProviderSettingsPanel(store: store)
    case .ai:
      AISettingsPanel(store: store)
    case .notifications:
      TelegramSettingsPanel(store: store)
    case .update:
      UpdateSettingsPanel(store: store)
    case .storage:
      StorageSettingsPanel(store: store)
    case .mailboxes:
      MailboxSettingsPanel(store: store)
    case .account:
      AccountSettingsPanel(store: store, dismissSettings: { dismiss() })
    case .legal:
      LegalSettingsPanel(store: store)
    }
  }
}

enum SettingsSection: String, CaseIterable, Identifiable {
  case providers
  case ai
  case notifications
  case update
  case storage
  case mailboxes
  case account
  case legal

  var id: String { rawValue }
  var adminOnly: Bool {
    [.providers, .ai, .notifications, .update, .storage].contains(self)
  }
  var title: String {
    switch self {
    case .providers: "发信渠道"
    case .ai: "AI 智能"
    case .notifications: "通知"
    case .update: "更新"
    case .storage: "存储"
    case .mailboxes: "信箱"
    case .account: "账户"
    case .legal: "许可与开源"
    }
  }
  var subtitle: String {
    switch self {
    case .providers: "配置 Cloudflare、Sendflare、Resend 或 SMTP 发信"
    case .ai: "配置兼容 OpenAI API 的智能邮件能力"
    case .notifications: "通过 Telegram 接收邮件提醒"
    case .update: "检查 MailEdge 服务端版本"
    case .storage: "选择附件存储后端与保留周期"
    case .mailboxes: "创建、命名和管理收件地址"
    case .account: "登录身份、密码与退出操作"
    case .legal: "查看项目许可、源码和数据边界"
    }
  }
  var icon: String {
    switch self {
    case .providers: "paperplane.fill"
    case .ai: "sparkles"
    case .notifications: "bell.fill"
    case .update: "arrow.clockwise.circle.fill"
    case .storage: "externaldrive.fill"
    case .mailboxes: "at"
    case .account: "person.crop.circle.fill"
    case .legal: "checkmark.seal.fill"
    }
  }
}

struct SettingsPageHeader: View {
  let title: String
  let subtitle: String
  let icon: String

  var body: some View {
    HStack(spacing: 14) {
      ZStack {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(MailEdgePalette.blue.opacity(0.12))
        Image(systemName: icon)
          .font(.title3.weight(.semibold))
          .foregroundStyle(MailEdgePalette.blue)
      }
      .frame(width: 48, height: 48)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.title2.bold())
        Text(subtitle).font(.callout).foregroundStyle(.secondary)
      }
    }
  }
}

struct SettingsSurface<Content: View>: View {
  @ViewBuilder let content: Content

  init(@ViewBuilder content: () -> Content) { self.content = content() }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) { content }
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 19, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.8)
      }
  }
}

struct SettingsFormRow<Content: View>: View {
  let title: String
  var hint: String? = nil
  var vertical = false
  @ViewBuilder let content: Content

  init(
    _ title: String, hint: String? = nil, vertical: Bool = false,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.hint = hint
    self.vertical = vertical
    self.content = content()
  }

  var body: some View {
    if vertical {
      VStack(alignment: .leading, spacing: 9) {
        label
        content
      }
    } else {
      HStack(alignment: .center, spacing: 18) {
        label.frame(width: 150, alignment: .leading)
        content.frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var label: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title).font(.callout.weight(.semibold))
      if let hint {
        Text(hint).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

struct SettingsTextFieldSurface: ViewModifier {
  func body(content: Content) -> some View {
    content
      .textFieldStyle(.plain)
      .padding(.horizontal, 12)
      .frame(minHeight: 44)
      .liquidGlass(cornerRadius: 12, tint: Color.primary.opacity(0.012), interactive: true)
  }
}

extension View {
  func settingsTextField() -> some View { modifier(SettingsTextFieldSurface()) }
}

struct SettingsInlineNotice: View {
  let message: String
  let isError: Bool

  var body: some View {
    Label(message, systemImage: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
      .font(.callout)
      .foregroundStyle(isError ? .red : .green)
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        (isError ? Color.red : Color.green).opacity(0.08),
        in: RoundedRectangle(cornerRadius: 12)
      )
  }
}
