import SwiftUI

struct MailSidebar: View {
  @Bindable var store: AppStore
  @Binding var settingsPresented: Bool
  @Namespace private var overviewSelection
  @Namespace private var mailboxSelection
  @Namespace private var folderSelection
  @Namespace private var toolSelection

  private let systemFolders: [(id: String, title: String, icon: String)] = [
    ("inbox", "收件箱", "tray.full"),
    ("sent", "已发送", "paperplane"),
    ("archive", "归档", "archivebox"),
    ("spam", "垃圾邮件", "exclamationmark.shield"),
    ("trash", "废纸篓", "trash"),
  ]

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: 7) {
        MailEdgeMark(size: 40)
        MailEdgeWordmark(size: 22)
      }
      .frame(maxWidth: .infinity, alignment: .center)
      .padding(.horizontal, 14)
      .padding(.top, 12)
      .padding(.bottom, 16)

      Button {
        store.startCompose()
      } label: {
        Label("写邮件", systemImage: "square.and.pencil")
          .fontWeight(.semibold)
          .frame(maxWidth: .infinity)
      }
      .prominentGlassButton()
      .keyboardShortcut("n", modifiers: .command)
      .padding(.horizontal, 12)
      .padding(.bottom, 16)

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          SidebarSection(title: "主页") {
            SidebarRow(
              title: "概览",
              subtitle: "邮件与账户动态",
              icon: "rectangle.grid.2x2",
              selected: store.workspace == .overview,
              selectionNamespace: overviewSelection
            ) {
              store.showOverview()
            }
          }

          SidebarSection(title: "信箱") {
            SidebarRow(
              title: "所有信箱",
              subtitle: "\(store.mailboxes.count) 个地址",
              icon: "square.stack.3d.up",
              selected: store.workspace == .mail && store.selectedMailboxId == "all",
              selectionNamespace: mailboxSelection
            ) {
              Task { await store.selectMailbox("all") }
            }
            ForEach(store.mailboxes) { mailbox in
              SidebarRow(
                title: mailbox.title,
                subtitle: mailbox.displayName == nil ? nil : mailbox.address,
                icon: mailbox.isCatchAll ? "at.badge.plus" : "at",
                selected: store.workspace == .mail && store.selectedMailboxId == mailbox.id,
                selectionNamespace: mailboxSelection
              ) {
                Task { await store.selectMailbox(mailbox.id) }
              }
            }
          }

          SidebarSection(title: "邮件") {
            ForEach(systemFolders, id: \.id) { folder in
              SidebarRow(
                title: folder.title,
                badge: unread(folder.id),
                icon: folder.icon,
                selected: store.workspace == .mail && store.selectedFolder == folder.id,
                selectionNamespace: folderSelection
              ) {
                Task { await store.selectFolder(folder.id) }
              }
            }
            ForEach(store.folders) { folder in
              SidebarRow(
                title: folder.name,
                badge: unread(folder.id),
                icon: "folder",
                selected: store.workspace == .mail && store.selectedFolder == folder.id,
                selectionNamespace: folderSelection
              ) {
                Task { await store.selectFolder(folder.id) }
              }
            }
          }

          SidebarSection(title: "工具") {
            SidebarRow(
              title: "附件管理",
              subtitle: store.managedAttachments.isEmpty
                ? "集中管理附件" : "\(store.managedAttachments.count) 个文件",
              icon: "paperclip",
              selected: store.workspace == .attachments,
              selectionNamespace: toolSelection
            ) {
              Task { await store.showAttachments() }
            }

            SidebarRow(
              title: "联系人",
              subtitle: store.contacts.isEmpty ? "通讯录" : "\(store.contacts.count) 位联系人",
              icon: "person.2",
              selected: store.workspace == .contacts,
              selectionNamespace: toolSelection
            ) {
              Task { await store.showContacts() }
            }

            SidebarRow(
              title: "设置",
              subtitle: "服务与账户配置",
              icon: "gearshape",
              selected: settingsPresented,
              selectionNamespace: toolSelection
            ) {
              settingsPresented = true
            }
          }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 16)
      }
      .animation(
        .spring(response: 0.48, dampingFraction: 0.72, blendDuration: 0.16),
        value: store.selectedMailboxId
      )
      .animation(
        .spring(response: 0.48, dampingFraction: 0.72, blendDuration: 0.16),
        value: store.selectedFolder
      )
      .animation(
        .spring(response: 0.48, dampingFraction: 0.72, blendDuration: 0.16),
        value: store.workspace
      )

      Divider().opacity(0.4)
      HStack(spacing: 10) {
        ZStack {
          Circle().fill(MailEdgePalette.blue.opacity(0.18))
          Text(String(store.user?.displayName.prefix(1) ?? "M"))
            .font(.caption.bold())
            .foregroundStyle(MailEdgePalette.blue)
        }
        .frame(width: 30, height: 30)
        VStack(alignment: .leading, spacing: 1) {
          Text(store.user?.displayName ?? "MailEdge").font(.caption.weight(.semibold)).lineLimit(1)
          Text(store.user?.email ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer()
        Button {
          settingsPresented = true
        } label: {
          Image(systemName: "gearshape")
        }
        .buttonStyle(.plain)
        .help("客户端设置")
      }
      .padding(12)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(.ultraThinMaterial)
  }

  private func unread(_ folder: String) -> Int {
    store.stats.first(where: { $0.folder == folder })?.unread ?? 0
  }
}

private struct SidebarSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title.uppercased())
        .font(.caption2.weight(.bold))
        .tracking(0.8)
        .foregroundStyle(.tertiary)
        .padding(.leading, 10)
      content
    }
  }
}

private struct SidebarRow: View {
  let title: String
  var subtitle: String? = nil
  var badge = 0
  let icon: String
  let selected: Bool
  let selectionNamespace: Namespace.ID
  let action: () -> Void
  @State private var hovered = false

  var body: some View {
    Button(action: action) {
      ZStack(alignment: .leading) {
        if selected {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(MailEdgePalette.blue.opacity(0.045))
            .liquidGlass(
              cornerRadius: 12,
              tint: MailEdgePalette.blue.opacity(0.14),
              interactive: true
            )
            .matchedGeometryEffect(id: "sidebar-glass", in: selectionNamespace)

          HStack(spacing: 0) {
            ZStack {
              Rectangle()
                .fill(
                  LinearGradient(
                    colors: [.clear, MailEdgePalette.blue.opacity(0.45), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                  )
                )
                .frame(width: 1)
              Capsule()
                .fill(MailEdgePalette.blue)
                .frame(width: 2.5, height: subtitle == nil ? 25 : 31)
                .shadow(color: MailEdgePalette.blue.opacity(0.95), radius: 7)
            }
            .frame(width: 4)

            LinearGradient(
              colors: [MailEdgePalette.blue.opacity(0.13), .clear],
              startPoint: .leading,
              endPoint: .trailing
            )
            .frame(width: 128)
            Spacer(minLength: 0)
          }
          .matchedGeometryEffect(id: "sidebar-glider", in: selectionNamespace)
          .allowsHitTesting(false)
        } else if hovered {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(0.045))
            .transition(.opacity)
        }

        HStack(spacing: 10) {
          Image(systemName: icon)
            .symbolEffect(.bounce, value: selected)
            .frame(width: 18)
            .foregroundStyle(selected ? MailEdgePalette.blue : Color.secondary)
          VStack(alignment: .leading, spacing: 0) {
            Text(title)
              .fontWeight(selected ? .semibold : .regular)
              .lineLimit(1)
            if let subtitle {
              Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
          }
          Spacer(minLength: 5)
          if badge > 0 {
            Text("\(badge)")
              .font(.caption2.bold())
              .padding(.horizontal, 7)
              .padding(.vertical, 2)
              .background(
                selected ? MailEdgePalette.blue : Color.secondary.opacity(0.14), in: Capsule()
              )
              .foregroundStyle(selected ? Color.white : Color.secondary)
          }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: subtitle == nil ? 40 : 48)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(SidebarTabButtonStyle())
    .onHover { isHovering in
      withAnimation(.easeOut(duration: 0.16)) { hovered = isHovering }
    }
  }
}

private struct SidebarTabButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.985 : 1)
      .opacity(configuration.isPressed ? 0.84 : 1)
      .animation(.snappy(duration: 0.18), value: configuration.isPressed)
  }
}
