import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

/// 앱 전체를 관리: 스티커 창들, 미리 알림, 빠른 추가, 단축키
@MainActor
final class AppController: ObservableObject {
    static let shared = AppController()

    let store = StickerStore()
    let reminders = RemindersService()

    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    var lastQuickAddTarget: UUID?

    private var windows: [UUID: StickerWindowController] = [:]
    private var quickAddController: QuickAddController?
    private var hotKey: HotKey?

    func start() {
        if store.stickers.isEmpty {
            store.add(Sticker(title: "할 일", frame: defaultFrame(index: 0)))
        }
        for sticker in store.stickers { openWindow(sticker) }

        reminders.onAuthorized = { [weak self] in self?.autoLinkFirstSticker() }
        reminders.requestAccessIfNeeded()

        // ⌃⌥T : 빠른 추가
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            Task { @MainActor in self?.toggleQuickAdd() }
        }
    }

    // MARK: 스티커 관리

    func newSticker() {
        let styles: [StickerStyle] = [.yellow, .pink, .mint, .sky, .lavender]
        let index = store.stickers.count
        let sticker = Sticker(
            title: "새 스티커",
            style: styles[index % styles.count],
            frame: defaultFrame(index: index)
        )
        store.add(sticker)
        openWindow(sticker)
    }

    func deleteSticker(_ id: UUID) {
        guard Prompt.confirm(
            title: "이 스티커를 삭제할까요?",
            message: "스티커만 사라지고, 미리 알림 목록과 할 일은 그대로 남아 있어요.",
            confirmTitle: "삭제"
        ) else { return }
        windows[id]?.close()
        windows[id] = nil
        store.remove(id)
    }

    func renameSticker(_ id: UUID) {
        guard let sticker = store.sticker(id),
              let name = Prompt.text(title: "스티커 이름", initial: sticker.title) else { return }
        store.update(id) { $0.title = name }
    }

    func setMode(_ id: UUID, _ mode: WindowMode) {
        store.update(id) { $0.mode = mode }
        windows[id]?.apply(mode: mode)
    }

    func setAllModes(_ mode: WindowMode) {
        for sticker in store.stickers { setMode(sticker.id, mode) }
    }

    func link(_ id: UUID, listID: String) {
        let title = reminders.list(listID)?.title
        store.update(id) {
            $0.listID = listID
            $0.order = []
            if let title { $0.title = title }
        }
    }

    func createList(for id: UUID) {
        guard let sticker = store.sticker(id),
              let name = Prompt.text(
                title: "새 미리 알림 목록",
                message: "아이폰 미리 알림 앱에도 같은 이름의 목록이 생겨요.",
                initial: sticker.title == "새 스티커" ? "" : sticker.title
              ),
              let listID = reminders.createList(name) else { return }
        store.update(id) {
            $0.listID = listID
            $0.title = name
            $0.order = []
        }
    }

    // MARK: 할 일 추가 (스티커 입력칸과 빠른 추가 창이 함께 사용)

    func quickAdd(_ raw: String, to stickerID: UUID) {
        guard let sticker = store.sticker(stickerID), let listID = sticker.listID else { return }
        lastQuickAddTarget = stickerID
        if let newID = reminders.add(QuickParser.parse(raw), to: listID) {
            store.update(stickerID) { $0.order.append(newID) }
        }
    }

    func toggleQuickAdd() {
        let quickAdd = quickAddController ?? QuickAddController(controller: self)
        quickAddController = quickAdd
        if quickAdd.isVisible {
            quickAdd.hide()
        } else {
            quickAdd.show()
        }
    }

    // MARK: 로그인 시 자동 실행

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Prompt.info(
                title: "자동 실행 설정을 바꾸지 못했어요",
                message: "앱을 응용 프로그램 폴더로 옮긴 뒤 다시 시도해 주세요.\n(\(error.localizedDescription))"
            )
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: 내부

    private func openWindow(_ sticker: Sticker) {
        let controller = StickerWindowController(sticker: sticker, controller: self)
        windows[sticker.id] = controller
        controller.show()
    }

    /// 첫 실행 때 만든 스티커를 기본 미리 알림 목록에 자동으로 연결
    private func autoLinkFirstSticker() {
        guard store.stickers.count == 1,
              let sticker = store.stickers.first,
              sticker.listID == nil,
              let defaultID = reminders.defaultListID else { return }
        link(sticker.id, listID: defaultID)
    }

    private func defaultFrame(index: Int) -> StickerFrame {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let width: CGFloat = 260
        let height: CGFloat = 320
        let column = CGFloat(index % 4)
        let row = CGFloat(index / 4)
        let x = screen.maxX - width - 40 - column * (width + 20)
        let y = screen.maxY - height - 40 - row * 40
        return StickerFrame(CGRect(x: x, y: y, width: width, height: height))
    }
}
