import AppKit
import SwiftUI

@MainActor
private final class MailEdgeAppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    MailEdgeBrand.registerFonts()
    if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
      let icon = NSImage(contentsOf: iconURL)
    {
      NSApplication.shared.applicationIconImage = icon
    } else {
      NSApplication.shared.applicationIconImage = MailEdgeBrand.logoImage()
    }
    configureWindowsAfterSceneCreation()
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    configureWindowsAfterSceneCreation()
  }

  private func configureWindowsAfterSceneCreation() {
    Task { @MainActor in
      await Task.yield()
      NSApplication.shared.windows.forEach(UnifiedWindowChrome.configure)
    }
  }
}

@main
struct MailEdgeMacApp: App {
  @NSApplicationDelegateAdaptor(MailEdgeAppDelegate.self) private var appDelegate
  @State private var store = AppStore()

  var body: some Scene {
    WindowGroup {
      RootView(store: store)
    }
    .defaultSize(width: 1320, height: 820)
    .windowResizability(.contentMinSize)
    .windowStyle(.hiddenTitleBar)
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("新建邮件") { store.startCompose() }
          .keyboardShortcut("n", modifiers: .command)
          .disabled(store.phase != .authenticated)
      }
      CommandGroup(after: .sidebar) {
        Button("刷新邮件") {
          Task { await store.refresh() }
        }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(store.phase != .authenticated)
      }
    }

    Settings {
      SettingsView(store: store)
    }
  }
}

struct UnifiedWindowChrome: NSViewRepresentable {
  func makeNSView(context: Context) -> WindowObserverView {
    WindowObserverView()
  }

  func updateNSView(_ nsView: WindowObserverView, context: Context) {
    nsView.configureWindow()
  }

  @MainActor
  static func configure(_ window: NSWindow) {
    window.styleMask.insert(.fullSizeContentView)
    window.title = ""
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.titlebarSeparatorStyle = .none
    window.isMovableByWindowBackground = true
    window.isOpaque = false
    window.backgroundColor = .clear
  }
}

final class WindowObserverView: NSView {
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    configureWindow()
  }

  func configureWindow() {
    guard let window else { return }
    UnifiedWindowChrome.configure(window)
  }
}
