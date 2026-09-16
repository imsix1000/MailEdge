import SwiftUI

struct ContactsManagerView: View {
  @Bindable var store: AppStore
  @State private var selectedID: String?
  @State private var creating = false
  @State private var query = ""
  @State private var draft = ContactDraft()
  @State private var isSaving = false
  @State private var deletePresented = false
  @State private var formError: String?

  var body: some View {
    HStack(spacing: 0) {
      listPane
        .frame(minWidth: 310, idealWidth: 360, maxWidth: 430)
      Divider().opacity(0.42)
      detailPane
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.clear)
    .task {
      await store.loadContacts(force: store.contacts.isEmpty)
      if selectedID == nil, let first = store.contacts.first { select(first) }
    }
    .confirmationDialog(
      "删除联系人？",
      isPresented: $deletePresented,
      titleVisibility: .visible
    ) {
      Button("删除", role: .destructive) { Task { await removeActive() } }
      Button("取消", role: .cancel) {}
    } message: {
      Text("联系人将从 MailEdge 通讯录中永久移除。")
    }
  }

  private var listPane: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: 10) {
        VStack(alignment: .leading, spacing: 3) {
          Text("联系人").font(.title2.bold())
          Text("\(store.contacts.count) 位联系人")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          Task { await store.loadContacts(force: true) }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .circularGlassButton(size: 38)
        .disabled(store.isLoadingContacts)
        .help("刷新")

        Button { startNew() } label: {
          Image(systemName: "person.badge.plus")
        }
        .circularGlassButton(tint: MailEdgePalette.blue.opacity(0.12), size: 38)
        .help("新建联系人")
      }
      .padding(.horizontal, 18)
      .frame(height: 82)
      .background(.ultraThinMaterial)

      HStack(spacing: 9) {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("搜索姓名、邮箱或公司", text: $query)
          .textFieldStyle(.plain)
      }
      .padding(.horizontal, 12)
      .frame(height: 42)
      .liquidGlass(cornerRadius: 13, tint: Color.primary.opacity(0.015), interactive: true)
      .padding(.horizontal, 14)
      .padding(.vertical, 12)

      Divider().opacity(0.35)

      if store.isLoadingContacts, store.contacts.isEmpty {
        ProgressView("正在加载联系人…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if filteredContacts.isEmpty {
        ContentUnavailableView(
          store.contacts.isEmpty ? "还没有联系人" : "没有搜索结果",
          systemImage: store.contacts.isEmpty ? "person.2" : "magnifyingglass",
          description: Text(store.contacts.isEmpty ? "创建联系人后，写邮件时可以快速选择。" : "请尝试其他关键词。")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(spacing: 6) {
            ForEach(filteredContacts) { contact in
              Button { select(contact) } label: {
                ContactListRow(contact: contact, selected: selectedID == contact.id && !creating)
              }
              .buttonStyle(.plain)
            }
          }
          .padding(9)
        }
      }
    }
    .frame(maxHeight: .infinity)
    .background(.ultraThinMaterial)
  }

  @ViewBuilder
  private var detailPane: some View {
    if activeContact != nil || creating {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          HStack(spacing: 14) {
            ZStack {
              RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(MailEdgePalette.blue.opacity(0.12))
              Image(systemName: creating ? "person.badge.plus" : "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(MailEdgePalette.blue)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
              Text(creating ? "新建联系人" : (activeContact?.name ?? "联系人"))
                .font(.system(size: 27, weight: .bold, design: .rounded))
              Text("保存常用收件人信息，写信时一键填写。")
                .font(.callout)
                .foregroundStyle(.secondary)
            }
          }

          if let formError {
            Label(formError, systemImage: "exclamationmark.circle.fill")
              .font(.callout)
              .foregroundStyle(.red)
              .padding(12)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
          }

          VStack(alignment: .leading, spacing: 18) {
            ContactFormField(title: "姓名", required: true) {
              TextField("联系人姓名", text: $draft.name)
                .textFieldStyle(.plain)
                .onChange(of: draft.name) { _, value in
                  if value.count > 80 { draft.name = String(value.prefix(80)) }
                }
            }
            ContactFormField(title: "邮箱", required: true) {
              TextField("name@example.com", text: $draft.email)
                .textFieldStyle(.plain)
                .onChange(of: draft.email) { _, value in
                  if value.count > 320 { draft.email = String(value.prefix(320)) }
                }
            }
            ContactFormField(title: "公司") {
              TextField("公司或组织（可选）", text: $draft.company)
                .textFieldStyle(.plain)
                .onChange(of: draft.company) { _, value in
                  if value.count > 80 { draft.company = String(value.prefix(80)) }
                }
            }
            ContactFormField(title: "备注", vertical: true) {
              TextEditor(text: $draft.notes)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 130)
                .onChange(of: draft.notes) { _, value in
                  if value.count > 1000 { draft.notes = String(value.prefix(1000)) }
                }
            }
          }
          .padding(20)
          .liquidGlass(cornerRadius: 20, tint: Color.primary.opacity(0.015))

          HStack(spacing: 11) {
            Button {
              Task { await save() }
            } label: {
              Label(creating ? "保存联系人" : "更新联系人", systemImage: "checkmark")
            }
            .prominentGlassButton()
            .disabled(isSaving || draft.name.nilIfBlank == nil || draft.email.nilIfBlank == nil)

            if activeContact != nil, !creating {
              Button(role: .destructive) { deletePresented = true } label: {
                Label("删除", systemImage: "trash")
              }
              .glassButton(tint: .red.opacity(0.10))
              .disabled(isSaving)
            }

            if creating {
              Button("取消") { cancelNew() }
                .glassButton()
                .disabled(isSaving)
            }
            Spacer()
            if isSaving { ProgressView().controlSize(.small) }
          }
        }
        .frame(maxWidth: 760, alignment: .leading)
        .padding(30)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    } else {
      ContentUnavailableView(
        "选择一个联系人",
        systemImage: "person.crop.circle",
        description: Text("联系人资料将在这里显示。")
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private var filteredContacts: [Contact] {
    let value = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !value.isEmpty else { return store.contacts }
    return store.contacts.filter { contact in
      [contact.name, contact.email, contact.company ?? ""]
        .contains { $0.lowercased().contains(value) }
    }
  }

  private var activeContact: Contact? {
    guard !creating else { return nil }
    return store.contacts.first { $0.id == selectedID }
  }

  private func select(_ contact: Contact) {
    creating = false
    selectedID = contact.id
    draft = .init(contact)
    formError = nil
  }

  private func startNew() {
    creating = true
    selectedID = nil
    draft = .init()
    formError = nil
  }

  private func cancelNew() {
    creating = false
    if let first = store.contacts.first { select(first) }
  }

  private func save() async {
    isSaving = true
    formError = nil
    defer { isSaving = false }
    do {
      let contact = try await store.saveContact(
        id: activeContact?.id,
        email: draft.email,
        name: draft.name,
        company: draft.company,
        notes: draft.notes
      )
      select(contact)
    } catch {
      formError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
  }

  private func removeActive() async {
    guard let contact = activeContact else { return }
    isSaving = true
    formError = nil
    defer { isSaving = false }
    do {
      try await store.deleteContact(contact)
      selectedID = nil
      if let next = store.contacts.first { select(next) }
    } catch {
      formError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
  }
}

private struct ContactDraft {
  var email = ""
  var name = ""
  var company = ""
  var notes = ""

  init() {}

  init(_ contact: Contact) {
    email = contact.email
    name = contact.name
    company = contact.company ?? ""
    notes = contact.notes ?? ""
  }
}

private struct ContactListRow: View {
  let contact: Contact
  let selected: Bool

  var body: some View {
    HStack(spacing: 11) {
      ZStack {
        Circle().fill(MailEdgePalette.blue.opacity(selected ? 0.18 : 0.10))
        Text(contact.initials)
          .font(.caption.bold())
          .foregroundStyle(MailEdgePalette.blue)
      }
      .frame(width: 38, height: 38)
      VStack(alignment: .leading, spacing: 3) {
        Text(contact.name).font(.callout.weight(.semibold)).lineLimit(1)
        Text(contact.email).font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
      Spacer(minLength: 4)
      if selected {
        Image(systemName: "chevron.right")
          .font(.caption.bold())
          .foregroundStyle(MailEdgePalette.blue)
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
          .strokeBorder(MailEdgePalette.blue.opacity(0.26), lineWidth: 1)
      }
    }
    .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
  }
}

private struct ContactFormField<Content: View>: View {
  let title: String
  var required = false
  var vertical = false
  @ViewBuilder let content: Content

  init(
    title: String, required: Bool = false, vertical: Bool = false,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.required = required
    self.vertical = vertical
    self.content = content()
  }

  var body: some View {
    if vertical {
      VStack(alignment: .leading, spacing: 8) {
        label
        content
          .padding(10)
          .liquidGlass(cornerRadius: 13, tint: Color.primary.opacity(0.012), interactive: true)
      }
    } else {
      HStack(alignment: .center, spacing: 16) {
        label.frame(width: 76, alignment: .leading)
        content
          .padding(.horizontal, 12)
          .frame(height: 46)
          .liquidGlass(cornerRadius: 13, tint: Color.primary.opacity(0.012), interactive: true)
      }
    }
  }

  private var label: some View {
    HStack(spacing: 3) {
      Text(title).font(.callout.weight(.semibold))
      if required { Text("*").foregroundStyle(.red) }
    }
  }
}
