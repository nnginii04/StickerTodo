import AppKit
import SwiftUI

extension Notification.Name {
    static let quickAddShown = Notification.Name("StickerTodo.quickAddShown")
}

/// ⌃⌥T 로 어디서든 띄우는 빠른 추가 창 (Spotlight 같은 느낌)
@MainActor
final class QuickAddController: NSObject, NSWindowDelegate {
    private let panel: StickerPanel

    init(controller: AppController) {
        panel = StickerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = QuickAddView(
            controller: controller,
            store: controller.store,
            close: { [weak self] in self?.hide() }
        )
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        panel.contentView = host
        panel.delegate = self
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        if let screen = NSScreen.main?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2,
                                         y: screen.maxY - screen.height * 0.28))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .quickAddShown, object: nil)
    }

    func hide() {
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}

struct QuickAddView: View {
    let controller: AppController
    @ObservedObject var store: StickerStore
    let close: () -> Void

    @State private var text = ""
    @State private var target: UUID?
    @FocusState private var focused: Bool

    private var linked: [Sticker] { store.stickers.filter { $0.listID != nil } }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            TextField("할 일 추가  (예: 보고서 제출 내일 !!)", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($focused)
                .onSubmit(submit)
                .onExitCommand(perform: close)
            Picker("", selection: $target) {
                ForEach(linked) { sticker in
                    Text(sticker.title).tag(Optional(sticker.id))
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onReceive(NotificationCenter.default.publisher(for: .quickAddShown)) { _ in
            text = ""
            if target == nil || !linked.contains(where: { $0.id == target }) {
                target = controller.lastQuickAddTarget ?? linked.first?.id
            }
            focused = true
        }
    }

    private func submit() {
        let raw = text.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty, let id = target else {
            close()
            return
        }
        controller.quickAdd(raw, to: id)
        close()
    }
}
