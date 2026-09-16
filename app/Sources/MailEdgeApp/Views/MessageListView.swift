import SwiftUI

struct MessageListView: View {
  @Bindable var store: AppStore
  @FocusState private var searchFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(store.selectedFolderTitle).font(.title2.bold())
            Text(mailboxLabel)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button {
            Task { await store.markAllRead() }
          } label: {
            Image(systemName: "envelope.open")
          }
          .help("全部标为已读")
          .circularGlassButton()
          Button {
            Task { await store.refresh() }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .help("刷新")
          .circularGlassButton()
        }

        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
          TextField("搜索发件人、主题或正文", text: $store.searchText)
            .textFieldStyle(.plain)
            .focused($searchFocused)
          if !store.searchText.isEmpty {
            Button {
              store.searchText = ""
            } label: {
              Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .liquidGlass(cornerRadius: 12, interactive: true)
      }
      .padding(14)
      .background(.ultraThinMaterial)

      Divider().opacity(0.4)

      if store.isLoading, store.messages.isEmpty {
        Spacer()
        ProgressView("正在收取邮件…")
        Spacer()
      } else if store.messages.isEmpty {
        ContentUnavailableView(
          store.searchText.isEmpty ? "这里还没有邮件" : "没有找到邮件",
          systemImage: store.searchText.isEmpty ? "tray" : "magnifyingglass",
          description: Text(store.searchText.isEmpty ? "新邮件到达后会显示在这里。" : "试试更换关键词。")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(spacing: 7) {
            ForEach(store.messages) { message in
              MessageRow(
                message: message,
                selected: store.selectedMessageId == message.id,
                onSelect: { Task { await store.selectMessage(message) } },
                onToggleStar: { Task { await store.toggleStar(message) } }
              )
              .contextMenu {
                Button(message.isStarred ? "取消星标" : "添加星标") {
                  Task { await store.toggleStar(message) }
                }
                Divider()
                Button("归档") {
                  Task {
                    await store.selectMessage(message)
                    await store.moveSelected(to: "archive")
                  }
                }
              }
            }

            if store.nextCursor != nil {
              Button {
                Task { await store.loadMore() }
              } label: {
                if store.isLoadingMore {
                  ProgressView().controlSize(.small)
                } else {
                  Text("加载更多")
                }
              }
              .buttonStyle(.plain)
              .foregroundStyle(MailEdgePalette.blue)
              .padding()
            }
          }
          .padding(10)
        }
        .scrollContentBackground(.hidden)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Color.primary.opacity(0.025))
    .task(id: store.searchText) {
      try? await Task.sleep(for: .milliseconds(350))
      guard !Task.isCancelled else { return }
      await store.search()
    }
    .onKeyPress("f", phases: .down) { press in
      guard press.modifiers.contains(.command) else { return .ignored }
      searchFocused = true
      return .handled
    }
  }

  private var mailboxLabel: String {
    store.selectedMailboxId == "all" ? "所有信箱" : (store.selectedMailbox?.address ?? "当前信箱")
  }
}

private struct MessageRow: View {
  let message: MessageSummary
  let selected: Bool
  let onSelect: () -> Void
  let onToggleStar: () -> Void

  var body: some View {
    Button(action: onSelect) {
      HStack(alignment: .top, spacing: 11) {
        SenderAvatar(
          address: message.from.email, name: message.participant, unread: !message.isRead)
        VStack(alignment: .leading, spacing: 5) {
          HStack(spacing: 7) {
            Text(message.participant)
              .font(.callout.weight(message.isRead ? .medium : .bold))
              .lineLimit(1)
            Spacer(minLength: 4)
            Text(dateText)
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
          HStack(spacing: 5) {
            Text(message.displaySubject)
              .font(.callout.weight(message.isRead ? .regular : .semibold))
              .lineLimit(1)
            if message.hasAttachments {
              Image(systemName: "paperclip")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
          Text(message.snippet)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
          if let alias = message.inboundAlias {
            Text("收至 \(alias)")
              .font(.caption2)
              .foregroundStyle(.tertiary)
              .lineLimit(1)
          }

          HStack(spacing: 6) {
            if let category = message.category {
              Text(categoryTitle(category))
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(categoryColor(category).opacity(0.12), in: Capsule())
                .foregroundStyle(categoryColor(category))
            }
            if let mailbox = message.mailboxAddress {
              Text(mailbox)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
            Spacer()
            Button(action: onToggleStar) {
              Image(systemName: message.isStarred ? "star.fill" : "star")
                .foregroundStyle(message.isStarred ? Color.yellow : Color.secondary.opacity(0.65))
            }
            .buttonStyle(.plain)
          }
        }
      }
      .padding(11)
      .contentShape(Rectangle())
      .background(
        selected
          ? MailEdgePalette.blue.opacity(0.13)
          : Color.primary.opacity(message.isRead ? 0.025 : 0.065),
        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .strokeBorder(
            selected ? MailEdgePalette.blue.opacity(0.35) : .white.opacity(0.08), lineWidth: 0.8)
      }
    }
    .buttonStyle(.plain)
  }

  private var dateText: String {
    guard let date = message.receivedDate else { return "" }
    if Calendar.current.isDateInToday(date) {
      return date.formatted(date: .omitted, time: .shortened)
    }
    return date.formatted(.dateTime.month(.abbreviated).day())
  }

  private func categoryTitle(_ value: String) -> String {
    switch value {
    case "important": "重要"
    case "updates": "更新"
    case "promotions": "推广"
    case "verification": "验证码"
    case "social": "社交"
    default: "其他"
    }
  }

  private func categoryColor(_ value: String) -> Color {
    switch value {
    case "important": .red
    case "updates": .green
    case "promotions": .orange
    case "verification": MailEdgePalette.blue
    case "social": MailEdgePalette.violet
    default: .secondary
    }
  }
}

private struct SenderAvatar: View {
  let address: String
  let name: String
  let unread: Bool

  var body: some View {
    ZStack {
      Circle()
        .fill(
          LinearGradient(
            colors: [avatarColor.opacity(0.95), avatarColor.opacity(0.62)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
      Text(String(name.prefix(1)).uppercased())
        .font(.caption.bold())
        .foregroundStyle(.white)
    }
    .frame(width: 34, height: 34)
    .overlay(alignment: .bottomTrailing) {
      if unread {
        Circle().fill(MailEdgePalette.blue).frame(width: 8, height: 8).overlay(
          Circle().stroke(.white, lineWidth: 1.5))
      }
    }
  }

  private var avatarColor: Color {
    let colors: [Color] = [.blue, .purple, .teal, .indigo, .pink, .orange]
    let index = address.unicodeScalars.reduce(0) { $0 + Int($1.value) } % colors.count
    return colors[index]
  }
}
