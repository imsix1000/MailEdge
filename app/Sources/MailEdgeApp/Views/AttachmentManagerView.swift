import AppKit
import SwiftUI

struct AttachmentManagerView: View {
  enum Filter: String, CaseIterable, Identifiable {
    case all
    case message
    case share

    var id: String { rawValue }
    var title: String {
      switch self {
      case .all: "全部"
      case .message: "邮件附件"
      case .share: "分享链接"
      }
    }
  }

  @Bindable var store: AppStore
  @State private var selectedID: String?
  @State private var filter: Filter = .all
  @State private var query = ""
  @State private var pendingDelete: ManagedAttachment?
  @State private var pendingRevoke: ManagedAttachment?
  @State private var isBusy = false

  var body: some View {
    VStack(spacing: 0) {
      hero
      Divider().opacity(0.35)

      if store.isLoadingAttachments, store.managedAttachments.isEmpty {
        ProgressView("正在加载附件…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if store.managedAttachments.isEmpty {
        ContentUnavailableView(
          "还没有附件",
          systemImage: "paperclip",
          description: Text("收发邮件或创建分享链接后，附件会集中显示在这里。")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        statistics
          .padding(.horizontal, 26)
          .padding(.top, 20)

        toolbar
          .padding(.horizontal, 26)
          .padding(.vertical, 16)

        HStack(spacing: 0) {
          listPane
            .frame(minWidth: 330, idealWidth: 390, maxWidth: 470)
          Divider().opacity(0.4)
          detailPane
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 24)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color.clear)
    .task {
      await store.loadManagedAttachments(force: store.managedAttachments.isEmpty)
      reconcileSelection()
    }
    .onChange(of: visibleItems.map(\.stableID)) { _, _ in reconcileSelection() }
    .confirmationDialog(
      "删除附件？",
      isPresented: Binding(
        get: { pendingDelete != nil },
        set: { if !$0 { pendingDelete = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("永久删除", role: .destructive) {
        guard let attachment = pendingDelete else { return }
        Task { await delete(attachment) }
      }
      Button("取消", role: .cancel) { pendingDelete = nil }
    } message: {
      Text("删除后历史邮件中的这个附件也无法再次下载，此操作不可撤销。")
    }
    .confirmationDialog(
      "撤销分享链接？",
      isPresented: Binding(
        get: { pendingRevoke != nil },
        set: { if !$0 { pendingRevoke = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("撤销分享", role: .destructive) {
        guard let attachment = pendingRevoke else { return }
        Task { await revoke(attachment) }
      }
      Button("取消", role: .cancel) { pendingRevoke = nil }
    } message: {
      Text("原分享地址将立即失效。")
    }
  }

  private var hero: some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 5) {
        Label("附件管理", systemImage: "paperclip.circle.fill")
          .font(.system(size: 27, weight: .bold, design: .rounded))
        Text("统一管理邮件附件和对外分享链接。")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        Task {
          await store.loadManagedAttachments(force: true)
          reconcileSelection()
        }
      } label: {
        Label("刷新", systemImage: "arrow.clockwise")
      }
      .glassButton()
      .disabled(store.isLoadingAttachments)
    }
    .padding(.horizontal, 26)
    .padding(.vertical, 22)
    .background(.ultraThinMaterial)
  }

  private var statistics: some View {
    HStack(spacing: 14) {
      AttachmentStat(
        title: "全部文件", value: "\(store.managedAttachments.count)",
        icon: "paperclip", tint: MailEdgePalette.blue)
      AttachmentStat(
        title: "分享链接", value: "\(sharedCount)",
        icon: "link", tint: MailEdgePalette.violet)
      AttachmentStat(
        title: "附件占用", value: totalBytes.byteCountText,
        icon: "externaldrive.fill", tint: .green)
    }
  }

  private var toolbar: some View {
    HStack(spacing: 14) {
      Picker("附件类型", selection: $filter) {
        ForEach(Filter.allCases) { item in Text(item.title).tag(item) }
      }
      .pickerStyle(.segmented)
      .frame(width: 330)

      Spacer(minLength: 12)

      HStack(spacing: 9) {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("搜索文件名、类型、信箱或邮件主题", text: $query)
          .textFieldStyle(.plain)
      }
      .padding(.horizontal, 13)
      .frame(maxWidth: 420, minHeight: 42)
      .liquidGlass(cornerRadius: 13, tint: Color.primary.opacity(0.018), interactive: true)
    }
  }

  private var listPane: some View {
    VStack(spacing: 0) {
      HStack {
        Text("筛选结果").font(.headline)
        Spacer()
        Text("\(visibleItems.count) 个")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 16)
      .frame(height: 48)

      Divider().opacity(0.35)

      if visibleItems.isEmpty {
        ContentUnavailableView("没有匹配的附件", systemImage: "magnifyingglass")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(spacing: 6) {
            ForEach(visibleItems, id: \.stableID) { item in
              Button { selectedID = item.stableID } label: {
                AttachmentListRow(item: item, selected: selectedID == item.stableID)
              }
              .buttonStyle(.plain)
            }
          }
          .padding(8)
        }
      }
    }
    .frame(maxHeight: .infinity)
    .liquidGlass(cornerRadius: 20, tint: MailEdgePalette.blue.opacity(0.018))
  }

  @ViewBuilder
  private var detailPane: some View {
    if let activeItem {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          HStack(alignment: .top, spacing: 15) {
            ZStack {
              RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(MailEdgePalette.blue.opacity(0.12))
              Image(systemName: activeItem.source == "share" ? "link" : "doc.fill")
                .font(.title2)
                .foregroundStyle(MailEdgePalette.blue)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 5) {
              Text(activeItem.filename)
                .font(.title2.bold())
                .textSelection(.enabled)
              Text("\(activeItem.size.byteCountText) · \(activeItem.contentType)")
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(sourceTitle(activeItem))
              .font(.caption.weight(.semibold))
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .background(MailEdgePalette.blue.opacity(0.10), in: Capsule())
          }

          if activeItem.isUnavailable {
            Label("这个分享链接已过期或被撤销。", systemImage: "exclamationmark.triangle.fill")
              .font(.callout.weight(.medium))
              .foregroundStyle(.orange)
              .padding(12)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
          }

          VStack(spacing: 0) {
            AttachmentMetaRow(title: "上传时间", value: dateText(activeItem))
            AttachmentMetaRow(title: "来源", value: sourceTitle(activeItem))
            if let mailbox = activeItem.mailboxAddress {
              AttachmentMetaRow(title: "信箱", value: mailbox)
            }
            if let subject = activeItem.messageSubject {
              AttachmentMetaRow(title: "邮件", value: subject)
            }
            if activeItem.source == "share" {
              AttachmentMetaRow(title: "下载次数", value: "\(activeItem.downloads ?? 0)")
            }
          }
          .liquidGlass(cornerRadius: 18, tint: Color.primary.opacity(0.015))

          if activeItem.source == "share" {
            shareLink(for: activeItem)
          }

          HStack(spacing: 10) {
            Button {
              Task { await store.download(activeItem) }
            } label: {
              Label("下载", systemImage: "arrow.down.circle")
            }
            .glassButton()
            .disabled(activeItem.isUnavailable || isBusy)

            Button {
              Task { await store.compose(with: activeItem) }
            } label: {
              Label("插入到邮件", systemImage: "envelope.badge")
            }
            .prominentGlassButton()
            .disabled(activeItem.isUnavailable || isBusy)

            if activeItem.source == "share", activeItem.revoked != true {
              Button {
                pendingRevoke = activeItem
              } label: {
                Label("撤销分享", systemImage: "link.badge.minus")
              }
              .glassButton(tint: .orange.opacity(0.09))
              .disabled(isBusy)
            }

            Spacer()

            Button(role: .destructive) {
              pendingDelete = activeItem
            } label: {
              Label("删除", systemImage: "trash")
            }
            .glassButton(tint: .red.opacity(0.10))
            .disabled(isBusy)
          }
        }
        .padding(22)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .liquidGlass(cornerRadius: 20, tint: Color.primary.opacity(0.012))
    } else {
      ContentUnavailableView("选择一个附件", systemImage: "paperclip")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func shareLink(for item: ManagedAttachment) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "link").foregroundStyle(MailEdgePalette.blue)
      Text(item.token.map { "\(store.serverURL)/d/\($0)" } ?? "—")
        .font(.system(.caption, design: .monospaced))
        .lineLimit(1)
        .textSelection(.enabled)
      Spacer()
      Button {
        guard let token = item.token else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(store.serverURL)/d/\(token)", forType: .string)
        store.noticeMessage = "分享链接已复制"
      } label: {
        Image(systemName: "doc.on.doc")
      }
      .circularGlassButton(size: 36)
      Button {
        guard let token = item.token,
          let url = URL(string: "\(store.serverURL)/d/\(token)") else { return }
        NSWorkspace.shared.open(url)
      } label: {
        Image(systemName: "arrow.up.right")
      }
      .circularGlassButton(size: 36)
      .disabled(item.isUnavailable)
    }
    .padding(13)
    .liquidGlass(cornerRadius: 14, tint: MailEdgePalette.blue.opacity(0.025))
  }

  private var visibleItems: [ManagedAttachment] {
    let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return store.managedAttachments.filter { item in
      guard filter == .all || item.source == filter.rawValue else { return false }
      guard !term.isEmpty else { return true }
      return [item.filename, item.contentType, item.mailboxAddress, item.messageSubject]
        .compactMap { $0?.lowercased() }
        .contains { $0.contains(term) }
    }
  }

  private var activeItem: ManagedAttachment? {
    visibleItems.first { $0.stableID == selectedID }
  }

  private var totalBytes: Int {
    store.managedAttachments.reduce(0) { $0 + $1.size }
  }

  private var sharedCount: Int {
    store.managedAttachments.filter { $0.source == "share" }.count
  }

  private func reconcileSelection() {
    if let selectedID, visibleItems.contains(where: { $0.stableID == selectedID }) { return }
    selectedID = visibleItems.first?.stableID
  }

  private func sourceTitle(_ item: ManagedAttachment) -> String {
    if item.source == "share" { return "分享链接" }
    return item.direction == "inbound" ? "收到的附件" : "发出的附件"
  }

  private func dateText(_ item: ManagedAttachment) -> String {
    guard let date = item.uploadedDate else { return item.uploadedAt }
    return date.formatted(date: .abbreviated, time: .shortened)
  }

  private func delete(_ attachment: ManagedAttachment) async {
    isBusy = true
    defer { isBusy = false; pendingDelete = nil }
    do { try await store.deleteManagedAttachment(attachment) } catch {
      store.errorMessage = error.localizedDescription
    }
  }

  private func revoke(_ attachment: ManagedAttachment) async {
    isBusy = true
    defer { isBusy = false; pendingRevoke = nil }
    do { try await store.revokeShare(attachment) } catch {
      store.errorMessage = error.localizedDescription
    }
  }
}

private struct AttachmentStat: View {
  let title: String
  let value: String
  let icon: String
  let tint: Color

  var body: some View {
    HStack(spacing: 13) {
      ZStack {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.12))
        Image(systemName: icon).foregroundStyle(tint)
      }
      .frame(width: 40, height: 40)
      VStack(alignment: .leading, spacing: 1) {
        Text(value).font(.title3.bold()).contentTransition(.numericText())
        Text(title).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(14)
    .frame(maxWidth: .infinity, minHeight: 72)
    .liquidGlass(cornerRadius: 18, tint: tint.opacity(0.025), interactive: true)
  }
}

private struct AttachmentListRow: View {
  let item: ManagedAttachment
  let selected: Bool

  var body: some View {
    HStack(spacing: 11) {
      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(MailEdgePalette.blue.opacity(selected ? 0.16 : 0.08))
        Image(systemName: item.source == "share" ? "link" : "doc")
          .foregroundStyle(selected ? MailEdgePalette.blue : Color.secondary)
      }
      .frame(width: 36, height: 36)

      VStack(alignment: .leading, spacing: 4) {
        Text(item.filename).font(.callout.weight(.semibold)).lineLimit(1)
        HStack(spacing: 5) {
          Text(item.source == "share" ? "分享" : (item.direction == "inbound" ? "收到" : "发出"))
          Text("·")
          Text(item.size.byteCountText)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
      }
      Spacer(minLength: 4)
      if item.isUnavailable {
        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
      }
    }
    .padding(.horizontal, 11)
    .frame(minHeight: 58)
    .background(
      selected ? MailEdgePalette.blue.opacity(0.10) : Color.clear,
      in: RoundedRectangle(cornerRadius: 13, style: .continuous)
    )
    .overlay {
      if selected {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
          .strokeBorder(MailEdgePalette.blue.opacity(0.28), lineWidth: 1)
      }
    }
    .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
  }
}

private struct AttachmentMetaRow: View {
  let title: String
  let value: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 16) {
      Text(title).font(.callout).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
      Text(value).font(.callout.weight(.medium)).textSelection(.enabled)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 15)
    .frame(minHeight: 46)
    .overlay(alignment: .bottom) { Divider().opacity(0.3) }
  }
}
