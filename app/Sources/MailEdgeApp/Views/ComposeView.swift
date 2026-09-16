import SwiftUI
import UniformTypeIdentifiers

struct ComposeView: View {
  @Bindable var store: AppStore
  @Environment(\.dismiss) private var dismiss
  private let initialSeed: ComposeSeed
  @State private var from: String
  @State private var to: String
  @State private var cc = ""
  @State private var bcc = ""
  @State private var subject: String
  @State private var messageBody: String
  @State private var showCopyFields = false
  @State private var attachments: [UploadedAttachment]
  @State private var fileImporterPresented = false
  @State private var isUploading = false
  @State private var isSending = false
  @State private var sent = false
  @State private var errorMessage: String?
  @State private var closeConfirmationPresented = false
  @State private var attemptedDraftRestore = false
  @State private var restoredLocalDraft = false
  @State private var contactsPanelPresented = false
  @State private var contactSearch = ""
  @FocusState private var focusedField: ComposeFocusField?

  init(store: AppStore, seed: ComposeSeed, initialAttachments: [UploadedAttachment] = []) {
    self.store = store
    initialSeed = seed
    _from = State(initialValue: seed.from)
    _to = State(initialValue: seed.to)
    _subject = State(initialValue: seed.subject)
    _messageBody = State(initialValue: seed.body)
    _attachments = State(initialValue: initialAttachments)
  }

  var body: some View {
    HStack(spacing: 0) {
      VStack(spacing: 0) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text("新邮件").font(.title2.bold())
          Text("支持 Markdown 与智能附件")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          saveDraftAndDismiss()
        } label: {
          Image(systemName: "doc.badge.plus")
        }
        .buttonStyle(
          ComposeCircleButtonStyle(tint: MailEdgePalette.blue.opacity(0.10))
        )
        .disabled(!hasMeaningfulContent || isSending || isUploading)
        .help("存草稿")
        .accessibilityLabel("存草稿")
        Button {
          requestClose()
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(ComposeCircleButtonStyle())
        .keyboardShortcut(.cancelAction)
        .help("关闭写信")
        .accessibilityLabel("关闭")
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 16)
      .background(.ultraThinMaterial)

      Divider().opacity(0.4)

      if restoredLocalDraft {
        HStack(spacing: 8) {
          Image(systemName: "doc.text.fill")
            .foregroundStyle(MailEdgePalette.blue)
          Text("已恢复上次保存在本机的草稿")
            .fontWeight(.medium)
          Spacer()
          Text("附件需要重新添加")
            .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(MailEdgePalette.blue.opacity(0.055))
        .transition(.move(edge: .top).combined(with: .opacity))
      }

      VStack(spacing: 12) {
        ComposeField(label: "发件人") {
          ZStack {
            Menu {
              ForEach(store.mailboxes) { mailbox in
                Button {
                  from = mailbox.address
                } label: {
                  if mailbox.address == from {
                    Label(senderTitle(mailbox), systemImage: "checkmark")
                  } else {
                    Text(senderTitle(mailbox))
                  }
                }
              }
            } label: {
              HStack(spacing: 10) {
                Image(systemName: "at")
                  .foregroundStyle(MailEdgePalette.blue)
                  .frame(width: 18)
                Text(selectedSenderTitle)
                  .foregroundStyle(.primary)
                  .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                  .font(.caption2.weight(.bold))
                  .foregroundStyle(.secondary)
              }
              .padding(.horizontal, 13)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
          .frame(height: 48)
          .composeControlSurface()
        }

        ComposeField(label: "收件人") {
          HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus")
              .foregroundStyle(focusedField == .to ? MailEdgePalette.blue : Color.secondary)
              .frame(width: 18)
            TextField("name@example.com；多个地址用逗号分隔", text: $to)
              .textFieldStyle(.plain)
              .focused($focusedField, equals: .to)
            Divider().frame(height: 20)
            Button(showCopyFields ? "收起" : "抄送 / 密送") {
              withAnimation(.snappy(duration: 0.24)) { showCopyFields.toggle() }
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(MailEdgePalette.blue)
            Divider().frame(height: 20)
            Button {
              toggleContactsPanel()
            } label: {
              Image(systemName: contactsPanelPresented ? "person.2.fill" : "person.2")
                .font(.callout.weight(.semibold))
                .foregroundStyle(
                  contactsPanelPresented ? MailEdgePalette.blue : Color.secondary
                )
                .frame(width: 28, height: 28)
                .background(
                  contactsPanelPresented ? MailEdgePalette.blue.opacity(0.12) : Color.clear,
                  in: Circle()
                )
            }
            .buttonStyle(.plain)
            .help("联系人")
            .accessibilityLabel("打开联系人")
          }
          .padding(.horizontal, 13)
          .frame(minHeight: 44)
          .composeControlSurface(isFocused: focusedField == .to)
        }

        if showCopyFields {
          ComposeField(label: "抄送") {
            ComposeTextField(
              icon: "person.2", placeholder: "可选", text: $cc,
              focus: $focusedField, field: .cc)
          }
          ComposeField(label: "密送") {
            ComposeTextField(
              icon: "eye.slash", placeholder: "可选", text: $bcc,
              focus: $focusedField, field: .bcc)
          }
          .transition(.move(edge: .top).combined(with: .opacity))
        }

        ComposeField(label: "主题") {
          ComposeTextField(
            icon: "text.alignleft", placeholder: "邮件主题", text: $subject,
            focus: $focusedField, field: .subject)
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 16)

      if let errorMessage {
        ErrorBanner(message: errorMessage)
          .padding(.horizontal, 20)
          .padding(.top, 12)
      }

      HStack(alignment: .top, spacing: 12) {
        Text("正文")
          .font(.callout)
          .foregroundStyle(.secondary)
          .frame(width: 64, alignment: .trailing)
          .padding(.top, 13)

        ZStack(alignment: .topLeading) {
          TextEditor(text: $messageBody)
          .font(.body)
          .focused($focusedField, equals: .body)
          .scrollContentBackground(.hidden)
          .padding(.horizontal, 8)
          .padding(.vertical, 7)
          .frame(maxWidth: .infinity, maxHeight: .infinity)

          if messageBody.isEmpty {
            Text("写点什么…\n\n可以使用 **粗体**、[链接](https://…) 等 Markdown 语法。")
              .foregroundStyle(.tertiary)
              .padding(.horizontal, 13)
              .padding(.vertical, 14)
              .allowsHitTesting(false)
          }
        }
        .composeControlSurface(isFocused: focusedField == .body)
      }
      .padding(.horizontal, 20)
      .padding(.top, 12)
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      if !attachments.isEmpty {
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(attachments) { attachment in
              HStack(spacing: 7) {
                Image(systemName: "doc.fill").foregroundStyle(MailEdgePalette.blue)
                VStack(alignment: .leading, spacing: 1) {
                  Text(attachment.filename).font(.caption).lineLimit(1)
                  Text(attachment.size.byteCountText).font(.caption2).foregroundStyle(.secondary)
                }
                Button {
                  attachments.removeAll { $0.id == attachment.id }
                  Task { await store.removeAttachment(attachment) }
                } label: {
                  Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
              }
              .padding(.horizontal, 10)
              .padding(.vertical, 7)
              .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
            }
          }
          .padding(.horizontal, 16)
          .padding(.top, 10)
        }
        .scrollIndicators(.hidden)
      }

      HStack(spacing: 12) {
        Button {
          fileImporterPresented = true
        } label: {
          Group {
            if isUploading {
              ProgressView().controlSize(.small)
            } else {
              Image(systemName: "paperclip")
            }
          }
        }
        .buttonStyle(ComposeCircleButtonStyle())
        .disabled(isUploading || isSending)
        .help(isUploading ? "正在上传附件" : "添加附件")
        .accessibilityLabel(isUploading ? "正在上传附件" : "添加附件")
        Text("附件先安全暂存到你的 MailEdge，再随邮件发送。")
          .font(.caption)
          .foregroundStyle(.tertiary)
        Spacer()
        Text("⌘ ↩ 发送")
          .font(.caption2)
          .foregroundStyle(.tertiary)
        Button {
          submit()
        } label: {
          Group {
            if isSending {
              ProgressView()
                .controlSize(.small)
                .tint(.white)
            } else {
              Image(systemName: "paperplane.fill")
            }
          }
        }
        .buttonStyle(
          ComposeCircleButtonStyle(tint: MailEdgePalette.blue, prominent: true)
        )
        .keyboardShortcut(.return, modifiers: [.command])
        .disabled(!canSend)
        .help(isSending ? "正在发送" : "发送邮件（⌘↩）")
        .accessibilityLabel(isSending ? "正在发送" : "发送邮件")
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 14)
      .background(.ultraThinMaterial)
      }

      if contactsPanelPresented {
        Divider().opacity(0.55)
        ComposeContactsPanel(
          contacts: store.contacts,
          selectedEmails: selectedRecipientEmails,
          isLoading: store.isLoadingContacts,
          errorMessage: store.contactsErrorMessage,
          searchText: $contactSearch,
          onSelect: addRecipient,
          onRefresh: { Task { await store.loadContacts(force: true) } },
          onClose: { withAnimation(.snappy(duration: 0.28)) { contactsPanelPresented = false } }
        )
        .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
    .frame(
      minWidth: contactsPanelPresented ? 972 : 680,
      idealWidth: contactsPanelPresented ? 1040 : 760,
      minHeight: 560,
      idealHeight: 650
    )
    .background(LiquidBackdrop())
    .animation(.snappy(duration: 0.28), value: contactsPanelPresented)
    .interactiveDismissDisabled(hasMeaningfulContent && !sent)
    .confirmationDialog(
      "要保存这封邮件吗？",
      isPresented: $closeConfirmationPresented,
      titleVisibility: .visible
    ) {
      Button("保存到本机草稿") { saveDraftAndDismiss() }
      Button("放弃邮件", role: .destructive) { discardAndDismiss() }
      Button("继续编辑", role: .cancel) {}
    } message: {
      Text(
        attachments.isEmpty
          ? "保存后，下次新建邮件会自动恢复。"
          : "文字内容会保存到本机；已添加的附件需要下次重新选择。"
      )
    }
    .fileImporter(
      isPresented: $fileImporterPresented,
      allowedContentTypes: [.data],
      allowsMultipleSelection: true
    ) { result in
      switch result {
      case .success(let urls): upload(urls)
      case .failure(let error): errorMessage = error.localizedDescription
      }
    }
    .onAppear { restoreLocalDraftIfNeeded() }
    .onDisappear {
      guard !sent else { return }
      let pending = attachments
      Task { for attachment in pending { await store.removeAttachment(attachment) } }
    }
  }

  private var canSend: Bool {
    !isSending && !isUploading && from.nilIfBlank != nil && to.nilIfBlank != nil
      && messageBody.nilIfBlank != nil
  }

  private var hasMeaningfulContent: Bool {
    to.nilIfBlank != nil || cc.nilIfBlank != nil || bcc.nilIfBlank != nil
      || subject.nilIfBlank != nil || messageBody.nilIfBlank != nil || !attachments.isEmpty
  }

  private var draftContext: String {
    "\(store.serverURL)\n\(store.user?.email ?? "")"
  }

  private var selectedRecipientEmails: Set<String> {
    let value = to.lowercased()
    return Set(
      store.contacts.compactMap { contact in
        value.contains(contact.email.lowercased()) ? contact.email.lowercased() : nil
      }
    )
  }

  private var selectedSenderTitle: String {
    guard let mailbox = store.mailboxes.first(where: { $0.address == from }) else {
      return from.nilIfBlank ?? "选择发件人"
    }
    return senderTitle(mailbox)
  }

  private func senderTitle(_ mailbox: Mailbox) -> String {
    mailbox.displayName.map { "\($0) <\(mailbox.address)>" } ?? mailbox.address
  }

  private func toggleContactsPanel() {
    let shouldOpen = !contactsPanelPresented
    withAnimation(.snappy(duration: 0.28)) { contactsPanelPresented = shouldOpen }
    guard shouldOpen else { return }
    Task { await store.loadContacts() }
  }

  private func addRecipient(_ contact: Contact) {
    guard !selectedRecipientEmails.contains(contact.email.lowercased()) else { return }
    let current = to.trimmingCharacters(in: .whitespacesAndNewlines)
    if current.isEmpty {
      to = contact.email
    } else if current.hasSuffix(",") || current.hasSuffix(";") {
      to = "\(current) \(contact.email)"
    } else {
      to = "\(current), \(contact.email)"
    }
    focusedField = .to
  }

  private func requestClose() {
    focusedField = nil
    if hasMeaningfulContent {
      closeConfirmationPresented = true
    } else {
      dismiss()
    }
  }

  private func saveDraftAndDismiss() {
    do {
      try LocalComposeDraftStore.save(
        LocalComposeDraft(
          context: draftContext,
          from: from,
          to: to,
          cc: cc,
          bcc: bcc,
          subject: subject,
          body: messageBody,
          savedAt: Date()
        )
      )
      store.noticeMessage = "草稿已保存到本机"
      dismiss()
    } catch {
      errorMessage = "保存草稿失败：\(error.localizedDescription)"
    }
  }

  private func discardAndDismiss() {
    LocalComposeDraftStore.clear(context: draftContext)
    dismiss()
  }

  private func restoreLocalDraftIfNeeded() {
    guard !attemptedDraftRestore else { return }
    attemptedDraftRestore = true
    guard initialSeed.to.nilIfBlank == nil,
      initialSeed.subject.nilIfBlank == nil,
      initialSeed.body.nilIfBlank == nil,
      let draft = try? LocalComposeDraftStore.load(context: draftContext)
    else { return }

    from = draft.from
    to = draft.to
    cc = draft.cc
    bcc = draft.bcc
    subject = draft.subject
    messageBody = draft.body
    showCopyFields = draft.cc.nilIfBlank != nil || draft.bcc.nilIfBlank != nil
    restoredLocalDraft = true
  }

  private func upload(_ urls: [URL]) {
    guard !urls.isEmpty else { return }
    isUploading = true
    errorMessage = nil
    Task {
      defer { isUploading = false }
      for url in urls {
        do {
          attachments.append(try await store.uploadAttachment(url: url))
        } catch {
          errorMessage = "\(url.lastPathComponent)：\(error.localizedDescription)"
          break
        }
      }
    }
  }

  private func submit() {
    isSending = true
    errorMessage = nil
    Task {
      defer { isSending = false }
      do {
        _ = try await store.sendMessage(
          from: from,
          to: to,
          cc: cc,
          bcc: bcc,
          subject: subject,
          body: messageBody,
          attachments: attachments
        )
        LocalComposeDraftStore.clear(context: draftContext)
        sent = true
        dismiss()
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }
}

private struct ComposeContactsPanel: View {
  let contacts: [Contact]
  let selectedEmails: Set<String>
  let isLoading: Bool
  let errorMessage: String?
  @Binding var searchText: String
  let onSelect: (Contact) -> Void
  let onRefresh: () -> Void
  let onClose: () -> Void

  private var filteredContacts: [Contact] {
    guard let query = searchText.nilIfBlank?.lowercased() else { return contacts }
    return contacts.filter { contact in
      contact.name.lowercased().contains(query)
        || contact.email.lowercased().contains(query)
        || contact.company?.lowercased().contains(query) == true
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 7) {
            Text("联系人").font(.headline)
            Text("\(contacts.count)")
              .font(.caption2.bold())
              .foregroundStyle(MailEdgePalette.blue)
              .padding(.horizontal, 7)
              .padding(.vertical, 2)
              .background(MailEdgePalette.blue.opacity(0.12), in: Capsule())
          }
          Text("点击即可添加到收件人")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Spacer()
        PanelIconButton(systemImage: "arrow.clockwise", help: "刷新联系人", action: onRefresh)
          .disabled(isLoading)
        PanelIconButton(systemImage: "xmark", help: "关闭联系人", action: onClose)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 15)

      HStack(spacing: 9) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
        TextField("搜索姓名、邮箱或公司", text: $searchText)
          .textFieldStyle(.plain)
        if !searchText.isEmpty {
          Button {
            searchText = ""
          } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
          }
          .buttonStyle(.plain)
          .help("清除搜索")
        }
      }
      .padding(.horizontal, 12)
      .frame(height: 40)
      .composeControlSurface()
      .padding(.horizontal, 14)
      .padding(.bottom, 12)

      Divider().opacity(0.45)

      Group {
        if isLoading && contacts.isEmpty {
          VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("正在加载联系人…")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, contacts.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
              .font(.title2)
              .foregroundStyle(.secondary)
            Text("联系人加载失败")
              .font(.callout.weight(.semibold))
            Text(errorMessage)
              .font(.caption)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
              .lineLimit(3)
            Button("重新加载", action: onRefresh).glassButton()
          }
          .padding(20)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredContacts.isEmpty {
          VStack(spacing: 10) {
            Image(systemName: contacts.isEmpty ? "person.2.slash" : "magnifyingglass")
              .font(.title2)
              .foregroundStyle(.tertiary)
            Text(contacts.isEmpty ? "还没有联系人" : "没有匹配的联系人")
              .font(.callout.weight(.medium))
            Text(contacts.isEmpty ? "可先在网页版联系人中添加" : "请尝试其他关键词")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ScrollView {
            LazyVStack(spacing: 5) {
              ForEach(filteredContacts) { contact in
                let selected = selectedEmails.contains(contact.email.lowercased())
                Button {
                  onSelect(contact)
                } label: {
                  HStack(spacing: 10) {
                    ZStack {
                      Circle().fill(MailEdgePalette.blue.opacity(selected ? 0.20 : 0.11))
                      Text(contact.initials)
                        .font(.caption.bold())
                        .foregroundStyle(MailEdgePalette.blue)
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 2) {
                      Text(contact.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                      Text(contact.email)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                      .foregroundStyle(selected ? MailEdgePalette.blue : Color.secondary)
                  }
                  .padding(.horizontal, 10)
                  .frame(minHeight: 52)
                  .background(
                    selected ? MailEdgePalette.blue.opacity(0.075) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                  )
                  .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(selected)
              }
            }
            .padding(10)
          }
        }
      }

      Divider().opacity(0.45)
      Label("支持连续选择多个联系人", systemImage: "person.2.badge.plus")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
    }
    .frame(width: 286)
    .frame(maxHeight: .infinity)
    .background(.ultraThinMaterial)
  }
}

private struct PanelIconButton: View {
  let systemImage: String
  let help: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.caption.weight(.bold))
        .frame(width: 30, height: 30)
        .background(Color.primary.opacity(0.055), in: Circle())
    }
    .buttonStyle(.plain)
    .help(help)
  }
}

private struct ComposeCircleButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  var tint: Color? = nil
  var prominent = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 16, weight: .semibold))
      .foregroundStyle(prominent ? Color.white : Color.primary)
      .frame(width: 46, height: 46)
      .contentShape(Circle())
      .scaleEffect(configuration.isPressed ? 0.92 : 1)
      .opacity(isEnabled ? 1 : 0.42)
      .modifier(
        ComposeCircleSurface(
          tint: tint,
          prominent: prominent,
          interactive: isEnabled,
          pressed: configuration.isPressed
        )
      )
      .animation(.snappy(duration: 0.18), value: configuration.isPressed)
      .animation(.easeOut(duration: 0.16), value: isEnabled)
  }
}

private struct ComposeCircleSurface: ViewModifier {
  let tint: Color?
  let prominent: Bool
  let interactive: Bool
  let pressed: Bool

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      content
        .glassEffect(
          .regular.tint(tint).interactive(interactive),
          in: .circle
        )
        .brightness(pressed ? -0.05 : 0)
    } else {
      content
        .background(
          prominent ? MailEdgePalette.blue.opacity(pressed ? 0.78 : 0.94) : Color.clear,
          in: Circle()
        )
        .background(.ultraThinMaterial, in: Circle())
        .overlay {
          Circle().strokeBorder(.white.opacity(prominent ? 0.28 : 0.18), lineWidth: 0.8)
        }
        .shadow(
          color: prominent ? MailEdgePalette.blue.opacity(0.20) : .black.opacity(0.08),
          radius: pressed ? 3 : 8,
          y: pressed ? 1 : 4
        )
    }
  }
}

private enum ComposeFocusField: Hashable {
  case to
  case cc
  case bcc
  case subject
  case body
}

private struct ComposeField<Content: View>: View {
  let label: String
  @ViewBuilder let content: Content

  init(label: String, @ViewBuilder content: () -> Content) {
    self.label = label
    self.content = content()
  }

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Text(label)
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(width: 64, alignment: .trailing)
      content
        .frame(maxWidth: .infinity)
    }
    .frame(minHeight: 44)
  }
}

private struct ComposeTextField: View {
  let icon: String
  let placeholder: String
  @Binding var text: String
  let focus: FocusState<ComposeFocusField?>.Binding
  let field: ComposeFocusField

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: icon)
        .foregroundStyle(focus.wrappedValue == field ? MailEdgePalette.blue : Color.secondary)
        .frame(width: 18)
      TextField(placeholder, text: $text)
        .textFieldStyle(.plain)
        .focused(focus, equals: field)
    }
    .padding(.horizontal, 13)
    .frame(minHeight: 44)
    .composeControlSurface(isFocused: focus.wrappedValue == field)
  }
}

private struct ComposeControlSurface: ViewModifier {
  let isFocused: Bool

  func body(content: Content) -> some View {
    content
      .background(
        .thinMaterial,
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(
            isFocused ? MailEdgePalette.blue.opacity(0.78) : Color.primary.opacity(0.12),
            lineWidth: isFocused ? 1.5 : 0.8
          )
      }
      .shadow(
        color: isFocused ? MailEdgePalette.blue.opacity(0.15) : .black.opacity(0.035),
        radius: isFocused ? 8 : 3,
        y: 1
      )
      .animation(.easeOut(duration: 0.18), value: isFocused)
  }
}

private extension View {
  func composeControlSurface(isFocused: Bool = false) -> some View {
    modifier(ComposeControlSurface(isFocused: isFocused))
  }
}
