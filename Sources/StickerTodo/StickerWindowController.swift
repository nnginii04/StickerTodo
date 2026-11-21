import AppKit
import SwiftUI

/// 테두리 없는 패널이지만 글자 입력을 받을 수 있게 key 창이 될 수 있어요
final class StickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 스티커 한 장 = 창 하나
@MainActor
final class StickerWindowController: NSObject, NSWindowDelegate {
    let stickerID: UUID
    let panel: StickerPanel
    private weak var controller: AppController?

    init(sticker: Sticker, controller: AppController) {
        stickerID = sticker.id
        self.controller = controller
        panel = StickerPanel(
            contentRect: sticker.frame.rect,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.minSize = NSSize(width: 200, height: 150)

        let root = StickerView(
            stickerID: sticker.id,
            controller: controller,
            store: controller.store,
            reminders: controller.reminders
        )
        let host = NSHostingView(rootView: root)
        host.sizingOptions = [] // 내용 크기에 따라 창이 멋대로 커지지 않게
        panel.contentView = host
        panel.delegate = self

        apply(mode: sticker.mode)
    }

    func apply(mode: WindowMode) {
        switch mode {
        case .desktop:
            // 바탕화면 아이콘 바로 위, 일반 창들보다는 아래
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        case .floating:
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        }
        panel.orderFrontRegardless()
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func close() {
        panel.delegate = nil
        panel.orderOut(nil)
    }

    func saveFrame() {
        let frame = panel.frame
        controller?.store.update(stickerID) { $0.frame = StickerFrame(frame) }
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        saveFrame()
    }
}
