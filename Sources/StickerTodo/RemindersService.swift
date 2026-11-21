import AppKit
import EventKit

/// 화면에 표시하기 위한 할 일 스냅샷 (EKReminder를 직접 들고 다니지 않아요)
struct TodoItem: Identifiable, Equatable {
    let id: String
    let title: String
    let isCompleted: Bool
    let completionDate: Date?
    let priority: Priority
    let dueDate: Date?
    let hasDueTime: Bool
    let creationDate: Date?

    init(_ r: EKReminder) {
        id = r.calendarItemIdentifier
        title = r.title ?? ""
        isCompleted = r.isCompleted
        completionDate = r.completionDate
        priority = Priority(ekValue: r.priority)
        if let comps = r.dueDateComponents {
            dueDate = Calendar.current.date(from: comps)
            hasDueTime = comps.hour != nil
        } else {
            dueDate = nil
            hasDueTime = false
        }
        creationDate = r.creationDate
    }

    var dueKey: Double { dueDate?.timeIntervalSince1970 ?? .greatestFiniteMagnitude }
    var createdKey: Double { creationDate?.timeIntervalSince1970 ?? 0 }
}

/// Apple 미리 알림(EventKit) 연동. iCloud를 통해 아이폰과 자동으로 동기화돼요.
@MainActor
final class RemindersService: ObservableObject {
    let store = EKEventStore()

    @Published private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    @Published private(set) var lists: [EKCalendar] = []
    @Published private(set) var items: [String: [TodoItem]] = [:]
    @Published var lastError: String?

    var onAuthorized: (() -> Void)?

    private var watched = Set<String>()
    private var observer: NSObjectProtocol?

    var isAuthorized: Bool { status == .fullAccess }
    var isDenied: Bool { status == .denied || status == .restricted }
    var defaultListID: String? { store.defaultCalendarForNewReminders()?.calendarIdentifier }

    init() {
        // 아이폰이나 미리 알림 앱에서 바뀌면 자동으로 다시 불러와요
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reloadAll() }
        }
    }

    // MARK: 권한

    func requestAccessIfNeeded() {
        status = EKEventStore.authorizationStatus(for: .reminder)
        if isAuthorized {
            didAuthorize()
        } else if status == .notDetermined {
            requestAccess()
        }
    }

    func requestAccess() {
        Task {
            _ = try? await store.requestFullAccessToReminders()
            status = EKEventStore.authorizationStatus(for: .reminder)
            if isAuthorized { didAuthorize() }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    private func didAuthorize() {
        reloadLists()
        onAuthorized?()
        reloadAll()
    }

    // MARK: 목록

    func reloadLists() {
        lists = store.calendars(for: .reminder)
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    func list(_ id: String?) -> EKCalendar? {
        guard let id else { return nil }
        return lists.first { $0.calendarIdentifier == id }
    }

    func createList(_ title: String) -> String? {
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = title
        guard let source = store.defaultCalendarForNewReminders()?.source
                ?? store.sources.first(where: { $0.sourceType == .local }) else {
            lastError = "목록을 만들 계정을 찾지 못했어요."
            return nil
        }
        calendar.source = source
        do {
            try store.saveCalendar(calendar, commit: true)
            reloadLists()
            return calendar.calendarIdentifier
        } catch {
            lastError = "목록을 만들지 못했어요: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: 할 일 불러오기

    func watch(_ listID: String?) {
        guard let listID else { return }
        watched.insert(listID)
        reload(listID)
    }

    func reloadAll() {
        guard isAuthorized else { return }
        reloadLists()
        for id in watched { reload(id) }
    }

    func reload(_ listID: String) {
        guard isAuthorized else { return }
        guard let calendar = store.calendar(withIdentifier: listID) else {
            items[listID] = []
            return
        }
        let openPredicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: [calendar])
        // 완료한 항목은 최근 24시간 것만 보여줘요 (줄 긋고 연하게 표시 후 다음 날 사라짐)
        let since = Calendar.current.date(byAdding: .hour, value: -24, to: Date())
        let donePredicate = store.predicateForCompletedReminders(
            withCompletionDateStarting: since, ending: nil, calendars: [calendar])

        let store = self.store
        Task {
            let open = await Self.fetch(store, openPredicate)
            let done = await Self.fetch(store, donePredicate)
            self.items[listID] = open + done
        }
    }

    nonisolated private static func fetch(_ store: EKEventStore, _ predicate: NSPredicate) async -> [TodoItem] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(TodoItem.init))
            }
        }
    }

    // MARK: 할 일 수정

    @discardableResult
    func add(_ input: QuickInput, to listID: String) -> String? {
        guard let calendar = store.calendar(withIdentifier: listID) else { return nil }
        let reminder = EKReminder(eventStore: store)
        reminder.title = input.title
        reminder.calendar = calendar
        reminder.priority = input.priority.rawValue
        reminder.dueDateComponents = input.due
        return save(reminder) ? reminder.calendarItemIdentifier : nil
    }

    func toggle(_ id: String) {
        mutate(id) { $0.isCompleted.toggle() }
    }

    func rename(_ id: String, to title: String) {
        mutate(id) { $0.title = title }
    }

    func setPriority(_ id: String, _ priority: Priority) {
        mutate(id) { $0.priority = priority.rawValue }
    }

    func setDue(_ id: String, _ components: DateComponents?) {
        mutate(id) { $0.dueDateComponents = components }
    }

    func delete(_ id: String) {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        let listID = reminder.calendar?.calendarIdentifier
        do {
            try store.remove(reminder, commit: true)
            if let listID { reload(listID) }
        } catch {
            lastError = "삭제하지 못했어요: \(error.localizedDescription)"
        }
    }

    private func mutate(_ id: String, _ change: (EKReminder) -> Void) {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        change(reminder)
        save(reminder)
    }

    @discardableResult
    private func save(_ reminder: EKReminder) -> Bool {
        do {
            try store.save(reminder, commit: true)
            if let listID = reminder.calendar?.calendarIdentifier { reload(listID) }
            return true
        } catch {
            lastError = "저장하지 못했어요: \(error.localizedDescription)"
            return false
        }
    }
}
