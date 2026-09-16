import SwiftUI

struct MessageDetailView: View {
  @Bindable var store: AppStore

  var body: some View {
    Group {
      if store.isLoadingDetail {
        ProgressView("正在打开邮件…")
      } else if let message = store.detail {
        detail(message)
      } else {
        ContentUnavailableView(
          "选择一封邮件",
          systemImage: "envelope.open",
          description: Text("邮件内容会在这里安全显示。")
        )
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .background(.regularMaterial)
  }

  private func detail(_ message: MessageDetail) -> some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Button {
          store.startCompose(replyingTo: message)
        } label: {
          Label("回复", systemImage: "arrowshape.turn.up.left")
        }
        .glassButton()

        Button {
          Task { await store.moveSelected(to: "archive") }
        } label: {
          Image(systemName: "archivebox")
        }
        .help("归档")
        .circularGlassButton()

        Button {
          Task { await store.deleteSelected() }
        } label: {
          Image(systemName: "trash")
        }
        .help(message.folder == "trash" ? "永久删除" : "移至废纸篓")
        .circularGlassButton(tint: .red.opacity(0.12))

        Menu {
          Button("收件箱") { Task { await store.moveSelected(to: "inbox") } }
          Button("归档") { Task { await store.moveSelected(to: "archive") } }
          Button("垃圾邮件") { Task { await store.moveSelected(to: "spam") } }
          Divider()
          ForEach(store.folders) { folder in
            Button(folder.name) { Task { await store.moveSelected(to: folder.id) } }
          }
        } label: {
          Label("移动", systemImage: "folder")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()

        Spacer()
        Button {
          Task { await store.toggleDetailStar() }
        } label: {
          Image(systemName: message.isStarred ? "star.fill" : "star")
            .foregroundStyle(message.isStarred ? Color.yellow : Color.secondary)
        }
        .help(message.isStarred ? "取消星标" : "添加星标")
        .circularGlassButton()
      }
      .padding(12)
      .background(.ultraThinMaterial)

      Divider().opacity(0.4)

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          VStack(alignment: .leading, spacing: 10) {
            if let category = message.category {
              Text(category.uppercased())
                .font(.caption2.bold())
                .tracking(0.8)
                .foregroundStyle(MailEdgePalette.blue)
            }
            Text(message.displaySubject)
              .font(.title.bold())
              .textSelection(.enabled)
            HStack(alignment: .top, spacing: 11) {
              SenderBadge(name: message.senderName)
              VStack(alignment: .leading, spacing: 3) {
                Text(message.senderName).font(.callout.bold())
                Text(message.from.email).font(.caption).foregroundStyle(.secondary).textSelection(
                  .enabled)
                Text(recipientLine(message)).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
              }
              Spacer()
              if let date = message.receivedDate {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }

          if let summary = message.aiSummary?.nilIfBlank {
            VStack(alignment: .leading, spacing: 6) {
              Label("AI 摘要", systemImage: "sparkles")
                .font(.caption.bold())
                .foregroundStyle(MailEdgePalette.violet)
              Text(summary).font(.callout).textSelection(.enabled)
            }
            .padding(13)
            .liquidGlass(cornerRadius: 14, tint: MailEdgePalette.violet.opacity(0.08))
          }

          SafeMailWebView(html: message.html, plainText: message.text ?? message.snippet)
            .frame(minHeight: 280, idealHeight: 520)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
            }

          if !message.attachments.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
              Label("附件 · \(message.attachments.count)", systemImage: "paperclip")
                .font(.headline)
              ForEach(message.attachments) { attachment in
                Button {
                  Task { await store.download(attachment) }
                } label: {
                  HStack(spacing: 10) {
                    Image(systemName: "doc.fill").foregroundStyle(MailEdgePalette.blue)
                    VStack(alignment: .leading, spacing: 1) {
                      Text(attachment.filename).lineLimit(1)
                      Text(
                        "\(attachment.size.byteCountText) · \(attachment.mode == "link" ? "智能链接" : "邮件附件")"
                      )
                      .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.down.circle")
                  }
                  .padding(10)
                  .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
              }
            }
          }

          if let error = message.error?.nilIfBlank {
            Label(error, systemImage: "exclamationmark.triangle.fill")
              .font(.caption)
              .foregroundStyle(.red)
              .padding(10)
              .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
          }
        }
        .padding(24)
        .frame(maxWidth: 860, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
      }
    }
  }

  private func recipientLine(_ message: MessageDetail) -> String {
    let recipients = message.to.map(\.email).joined(separator: "、")
    return recipients.isEmpty ? "" : "发送给 \(recipients)"
  }
}

private struct SenderBadge: View {
  let name: String

  var body: some View {
    ZStack {
      Circle().fill(MailEdgePalette.blue.gradient)
      Text(String(name.prefix(1)).uppercased()).font(.callout.bold()).foregroundStyle(.white)
    }
    .frame(width: 38, height: 38)
  }
}
