import SwiftUI

struct OverviewView: View {
  @Bindable var store: AppStore

  private let metricColumns = Array(
    repeating: GridItem(.flexible(minimum: 150), spacing: 14), count: 4)

  private let resourceColumns = Array(
    repeating: GridItem(.flexible(minimum: 190), spacing: 14), count: 4)

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        header

        LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 14) {
          OverviewMetricCard(
            title: "收件箱",
            value: total("inbox"),
            caption: "全部收到的邮件",
            icon: "tray.full.fill",
            tint: MailEdgePalette.blue
          )
          OverviewMetricCard(
            title: "未读邮件",
            value: unreadTotal,
            caption: unreadTotal == 0 ? "已经全部读完" : "等待你处理",
            icon: "envelope.badge.fill",
            tint: .orange
          )
          OverviewMetricCard(
            title: "已发送",
            value: total("sent"),
            caption: "成功发出的邮件",
            icon: "paperplane.fill",
            tint: .indigo
          )
          OverviewMetricCard(
            title: "邮箱地址",
            value: store.mailboxes.count,
            caption: mailboxScopeTitle,
            icon: "at",
            tint: .cyan
          )
        }

        quickActions

        resourceUsage

        ViewThatFits(in: .horizontal) {
          HStack(alignment: .top, spacing: 16) {
            recentMail
              .frame(maxWidth: .infinity)
            mailboxSummary
              .frame(width: 300)
          }

          VStack(spacing: 16) {
            recentMail
            mailboxSummary
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 32)
      .padding(.top, 24)
      .padding(.bottom, 36)
      .frame(maxWidth: .infinity, alignment: .top)
    }
    .background(Color.clear)
    .task {
      if store.usage == nil { await store.refreshOverviewResources() }
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 18) {
      VStack(alignment: .leading, spacing: 6) {
        Text(greeting)
          .font(.system(size: 28, weight: .bold, design: .rounded))
        Text("这里是你的 MailEdge 邮件与账户概览。")
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 16)

      HStack(spacing: 8) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
        Text("已连接")
          .font(.callout.weight(.semibold))
      }
      .padding(.horizontal, 13)
      .frame(height: 40)
      .liquidGlass(cornerRadius: 20, tint: .green.opacity(0.07))

      Button {
        Task { await store.refreshOverview() }
      } label: {
        Image(systemName: "arrow.clockwise")
          .frame(width: 40, height: 40)
      }
      .buttonStyle(.plain)
      .liquidGlass(cornerRadius: 20, interactive: true)
      .help("刷新概览")
      .disabled(store.isLoading)
    }
  }

  private var resourceUsage: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionHeading(title: "存储与数据", subtitle: "Cloudflare 实例的实时资源占用")

      LazyVGrid(columns: resourceColumns, alignment: .leading, spacing: 14) {
        ResourceUsageCard(
          title: "附件空间",
          value: attachmentBytes.byteCountText,
          caption: "\(store.managedAttachments.count) 个可管理附件",
          icon: "paperclip",
          tint: MailEdgePalette.blue,
          loading: store.isLoadingUsage && store.usage == nil
        ) {
          Task { await store.showAttachments() }
        }

        ResourceUsageCard(
          title: "D1 数据库",
          value: optionalBytes(store.usage?.d1.sizeBytes),
          caption: store.usage.map { "\($0.d1.totalRows) 行结构化数据" } ?? "等待服务器数据",
          icon: "cylinder.split.1x2.fill",
          tint: .orange,
          loading: store.isLoadingUsage && store.usage == nil
        )

        ResourceUsageCard(
          title: "Durable Objects",
          value: optionalBytes(store.usage?.durableObjects.sqliteBytes),
          caption: store.usage.map {
            "\($0.durableObjects.messageCount) 封邮件 · \($0.durableObjects.mailboxCount) 个信箱"
          } ?? "等待服务器数据",
          icon: "shippingbox.fill",
          tint: MailEdgePalette.violet,
          loading: store.isLoadingUsage && store.usage == nil
        )

        ResourceUsageCard(
          title: "R2 对象存储",
          value: store.usage?.r2.available == true
            ? (store.usage?.r2.bytes ?? 0).byteCountText : "未绑定",
          caption: store.usage?.r2.available == true
            ? "\(store.usage?.r2.objectCount ?? 0) 个对象"
            : "当前实例未启用 R2",
          icon: "externaldrive.fill",
          tint: .cyan,
          loading: store.isLoadingUsage && store.usage == nil
        )
      }

      if let usage = store.usage {
        HStack(spacing: 6) {
          Image(systemName: "clock.arrow.circlepath")
          Text("资源统计更新于 \(usage.updatedAt)")
          if usage.scope == "instance" {
            Text("· 实例范围")
          }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
      }
    }
  }

  private var quickActions: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionHeading(title: "快捷操作", subtitle: "常用功能一步直达")
      HStack(spacing: 12) {
        Button {
          store.startCompose()
        } label: {
          Label("写邮件", systemImage: "square.and.pencil")
        }
        .prominentGlassButton()

        Button {
          Task { await store.selectFolder("inbox") }
        } label: {
          Label("查看收件箱", systemImage: "tray.full")
        }
        .glassButton(tint: MailEdgePalette.blue.opacity(0.06))

        Button {
          Task { await store.selectFolder("sent") }
        } label: {
          Label("查看已发送", systemImage: "paperplane")
        }
        .glassButton()

        Spacer(minLength: 0)
      }
    }
  }

  private var recentMail: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionHeading(title: "最近邮件", subtitle: "\(store.selectedFolderTitle)中的最新动态")

      VStack(spacing: 0) {
        if store.isLoading, store.messages.isEmpty {
          ProgressView("正在获取邮件…")
            .frame(maxWidth: .infinity, minHeight: 190)
        } else if recentMessages.isEmpty {
          ContentUnavailableView(
            "还没有邮件",
            systemImage: "tray",
            description: Text("新邮件到达后会显示在这里。")
          )
          .frame(maxWidth: .infinity, minHeight: 190)
        } else {
          ForEach(Array(recentMessages.enumerated()), id: \.element.id) { index, message in
            Button {
              Task { await store.selectMessage(message) }
            } label: {
              RecentMessageRow(message: message)
            }
            .buttonStyle(.plain)

            if index < recentMessages.count - 1 {
              Divider().opacity(0.45).padding(.leading, 52)
            }
          }
        }
      }
      .liquidGlass(cornerRadius: 20, tint: Color.primary.opacity(0.018))
    }
  }

  private var mailboxSummary: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionHeading(title: "邮箱地址", subtitle: "当前账户已接入的地址")

      VStack(spacing: 0) {
        if store.mailboxes.isEmpty {
          ContentUnavailableView("暂无邮箱", systemImage: "at")
            .frame(maxWidth: .infinity, minHeight: 170)
        } else {
          ForEach(Array(store.mailboxes.prefix(5).enumerated()), id: \.element.id) {
            index, mailbox in
            Button {
              Task { await store.selectMailbox(mailbox.id) }
            } label: {
              HStack(spacing: 11) {
                ZStack {
                  Circle().fill(MailEdgePalette.blue.opacity(0.12))
                  Image(systemName: mailbox.isCatchAll ? "at.badge.plus" : "at")
                    .foregroundStyle(MailEdgePalette.blue)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                  Text(mailbox.title).font(.callout.weight(.semibold)).lineLimit(1)
                  Text(mailbox.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                  .font(.caption.bold())
                  .foregroundStyle(.tertiary)
              }
              .padding(.horizontal, 14)
              .frame(minHeight: 55)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if index < min(store.mailboxes.count, 5) - 1 {
              Divider().opacity(0.45).padding(.leading, 58)
            }
          }
        }
      }
      .liquidGlass(cornerRadius: 20, tint: MailEdgePalette.blue.opacity(0.025))
    }
  }

  private var recentMessages: [MessageSummary] {
    Array(store.messages.prefix(5))
  }

  private var unreadTotal: Int {
    store.stats.reduce(0) { $0 + $1.unread }
  }

  private func total(_ folder: String) -> Int {
    store.stats.first(where: { $0.folder == folder })?.total ?? 0
  }

  private var greeting: String {
    let hour = Calendar.current.component(.hour, from: Date())
    let salutation = hour < 6 ? "夜深了" : hour < 12 ? "早上好" : hour < 18 ? "下午好" : "晚上好"
    let name = store.user?.displayName.nilIfBlank ?? "MailEdge 用户"
    return "\(salutation)，\(name)"
  }

  private var mailboxScopeTitle: String {
    store.selectedMailboxId == "all" ? "当前账户全部地址" : "当前选中的邮箱"
  }

  private var attachmentBytes: Int {
    store.managedAttachments.reduce(0) { $0 + $1.size }
  }

  private func optionalBytes(_ value: Int?) -> String {
    value.map(\.byteCountText) ?? "不可用"
  }
}

private struct OverviewMetricCard: View {
  let title: String
  let value: Int
  let caption: String
  let icon: String
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        ZStack {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(tint.opacity(0.12))
          Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint)
        }
        .frame(width: 38, height: 38)

        Spacer()
        Text(title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 3) {
        Text(value, format: .number)
          .font(.system(size: 30, weight: .bold, design: .rounded))
          .contentTransition(.numericText())
        Text(caption)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, minHeight: 138, alignment: .leading)
    .liquidGlass(cornerRadius: 20, tint: tint.opacity(0.035), interactive: true)
  }
}

private struct SectionHeading: View {
  let title: String
  let subtitle: String

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title).font(.headline)
      Text(subtitle).font(.caption).foregroundStyle(.secondary)
      Spacer()
    }
  }
}

private struct ResourceUsageCard: View {
  let title: String
  let value: String
  let caption: String
  let icon: String
  let tint: Color
  let loading: Bool
  var action: (() -> Void)? = nil

  var body: some View {
    Button {
      action?()
    } label: {
      HStack(spacing: 13) {
        ZStack {
          RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(tint.opacity(0.12))
          Image(systemName: icon)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
        }
        .frame(width: 42, height: 42)

        VStack(alignment: .leading, spacing: 3) {
          Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
          if loading {
            ProgressView().controlSize(.small)
          } else {
            Text(value).font(.title3.bold()).contentTransition(.numericText())
          }
          Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer(minLength: 0)
        if action != nil {
          Image(systemName: "chevron.right")
            .font(.caption.bold())
            .foregroundStyle(.tertiary)
        }
      }
      .padding(15)
      .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
      .contentShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
    .buttonStyle(.plain)
    .liquidGlass(cornerRadius: 19, tint: tint.opacity(0.026), interactive: action != nil)
  }
}

private struct RecentMessageRow: View {
  let message: MessageSummary

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        Circle().fill(
          message.isRead ? Color.secondary.opacity(0.10) : MailEdgePalette.blue.opacity(0.14))
        Text(String(message.participant.prefix(1)).uppercased())
          .font(.caption.bold())
          .foregroundStyle(message.isRead ? Color.secondary : MailEdgePalette.blue)
      }
      .frame(width: 36, height: 36)

      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text(message.participant)
            .font(.callout.weight(message.isRead ? .medium : .bold))
            .lineLimit(1)
          Spacer()
          if let date = message.receivedDate {
            Text(date, style: .relative)
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
        }
        Text(message.displaySubject)
          .font(.callout.weight(message.isRead ? .regular : .semibold))
          .lineLimit(1)
        Text(message.snippet)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Image(systemName: "chevron.right")
        .font(.caption2.bold())
        .foregroundStyle(.tertiary)
    }
    .padding(.horizontal, 14)
    .frame(minHeight: 67)
    .contentShape(Rectangle())
  }
}
