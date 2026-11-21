import Foundation

/// 스티커 설정(위치, 크기, 스타일, 연결된 목록, 정렬 순서)을
/// ~/Library/Application Support/StickerTodo/stickers.json 에 저장해요.
/// 할 일 자체는 미리 알림 앱에 저장되므로 여기에는 없어요.
@MainActor
final class StickerStore: ObservableObject {
    @Published private(set) var stickers: [Sticker] = []
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StickerTodo", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("stickers.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Sticker].self, from: data) {
            stickers = decoded
        }
    }

    func sticker(_ id: UUID) -> Sticker? {
        stickers.first { $0.id == id }
    }

    func add(_ sticker: Sticker) {
        stickers.append(sticker)
        save()
    }

    func remove(_ id: UUID) {
        stickers.removeAll { $0.id == id }
        save()
    }

    func update(_ id: UUID, _ change: (inout Sticker) -> Void) {
        guard let index = stickers.firstIndex(where: { $0.id == id }) else { return }
        var copy = stickers[index]
        change(&copy)
        guard copy != stickers[index] else { return }
        stickers[index] = copy
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(stickers) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
