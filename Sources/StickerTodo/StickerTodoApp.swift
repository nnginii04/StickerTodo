import SwiftUI

@main
struct StickerTodoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var controller = AppController.shared

    var body: some Scene {
        // 메뉴바 아이콘 (Dock에는 나타나지 않아요)
        MenuBarExtra("스티커 투두", systemImage: "note.text") {
            Button("새 스티커") { controller.newSticker() }
                .keyboardShortcut("n")
            Button("빠른 추가  ⌃⌥T") { controller.toggleQuickAdd() }
            Divider()
            Button("모두 바탕화면에 붙이기") { controller.setAllModes(.desktop) }
            Button("모두 다른 창 위에 띄우기") { controller.setAllModes(.floating) }
            Divider()
            Toggle("로그인 시 자동 실행", isOn: Binding(
                get: { controller.launchAtLogin },
                set: { controller.setLaunchAtLogin($0) }
            ))
            Divider()
            Button("종료") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppController.shared.start()
    }
}
