import SwiftUI

struct MailShellView: View {
  @Bindable var store: AppStore
  @State private var settingsPresented = false

  var body: some View {
    Group {
      if store.workspace != .mail {
        NavigationSplitView {
          sidebar
        } detail: {
          switch store.workspace {
          case .overview:
            OverviewView(store: store)
          case .attachments:
            AttachmentManagerView(store: store)
          case .contacts:
            ContactsManagerView(store: store)
          case .mail:
            EmptyView()
          }
        }
        .navigationSplitViewStyle(.balanced)
      } else {
        NavigationSplitView {
          sidebar
        } content: {
          MessageListView(store: store)
            .navigationSplitViewColumnWidth(min: 330, ideal: 390, max: 500)
        } detail: {
          MessageDetailView(store: store)
            .navigationSplitViewColumnWidth(min: 440, ideal: 680)
        }
        .navigationSplitViewStyle(.balanced)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(LiquidBackdrop())
    .toolbarBackground(.hidden, for: .windowToolbar)
    .sheet(isPresented: $store.isComposing) {
      ComposeView(
        store: store,
        seed: store.composeSeed,
        initialAttachments: store.composeAttachments
      )
    }
    .sheet(isPresented: $settingsPresented) {
      SettingsView(store: store)
    }
    .overlay(alignment: .bottom) {
      if let message = store.errorMessage ?? store.noticeMessage {
        ToastView(message: message, isError: store.errorMessage != nil)
          .padding(.bottom, 20)
          .transition(.move(edge: .bottom).combined(with: .opacity))
          .onTapGesture { store.clearNotice() }
      }
    }
    .animation(.snappy, value: store.errorMessage)
    .animation(.snappy, value: store.noticeMessage)
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(60))
        guard !Task.isCancelled else { return }
        await store.refresh()
      }
    }
  }

  private var sidebar: some View {
    MailSidebar(store: store, settingsPresented: $settingsPresented)
      .navigationSplitViewColumnWidth(min: 210, ideal: 238, max: 290)
  }
}

private struct ToastView: View {
  let message: String
  let isError: Bool

  var body: some View {
    Label(message, systemImage: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
      .font(.callout.weight(.medium))
      .foregroundStyle(isError ? Color.red : Color.primary)
      .padding(.horizontal, 16)
      .padding(.vertical, 11)
      .liquidGlass(cornerRadius: 16, tint: isError ? .red.opacity(0.08) : .green.opacity(0.08))
      .shadow(radius: 12)
  }
}
