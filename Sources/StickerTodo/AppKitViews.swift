import AppKit
import SwiftUI

/// 반투명 유리 배경 (창 뒤 바탕화면이 비쳐 보여요)
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// 스티커 머리 부분을 잡고 끌면 창이 움직여요
final class DragHandleNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleNSView { DragHandleNSView() }
    func updateNSView(_ nsView: DragHandleNSView, context: Context) {}
}

/// 오른쪽 아래 모서리를 끌어서 크기 조절
final class ResizeGripNSView: NSView {
    private var startFrame = NSRect.zero
    private var startMouse = NSPoint.zero

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        startFrame = window.frame
        startMouse = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - startMouse.x
        let dy = mouse.y - startMouse.y

        // 왼쪽 위 모서리는 고정하고 오른쪽 아래로 늘려요
        let width = max(window.minSize.width, startFrame.width + dx)
        let height = max(window.minSize.height, startFrame.height - dy)
        let frame = NSRect(x: startFrame.minX, y: startFrame.maxY - height, width: width, height: height)
        window.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        (window?.delegate as? StickerWindowController)?.saveFrame()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        for i in 1...3 {
            let offset = CGFloat(i) * 4
            path.move(to: NSPoint(x: bounds.maxX - offset - 2, y: bounds.minY + 3))
            path.line(to: NSPoint(x: bounds.maxX - 3, y: bounds.minY + offset + 2))
        }
        path.stroke()
    }
}

struct ResizeGrip: NSViewRepresentable {
    func makeNSView(context: Context) -> ResizeGripNSView { ResizeGripNSView() }
    func updateNSView(_ nsView: ResizeGripNSView, context: Context) {}
}

/// 이름 입력, 삭제 확인 같은 간단한 대화상자
@MainActor
enum Prompt {
    static func text(title: String, message: String = "", initial: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "취소")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func confirm(title: String, message: String, confirmTitle: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "취소")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func info(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "확인")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
