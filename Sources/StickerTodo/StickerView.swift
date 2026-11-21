import SwiftUI
import EventKit

struct StickerView: View {
    let stickerID: UUID
    let controller: AppController
    @ObservedObject var store: StickerStore
    @ObservedObject var reminders: RemindersService

    @Environment(\.colorScheme) private var systemScheme
    @State private var newTitle = ""
    @FocusState private var addFocused: Bool

    var body: some View {
        if let sticker = store.sticker(stickerID) {
            card(sticker)
        } else {
            Color.clear
        }
    }

    // MARK: 카드 전체

    private func card(_ s: Sticker) -> some View {
        VStack(spacing: 0) {
            header(s)
            content(s)
            if let error = reminders.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .onTapGesture { reminders.lastError = nil }
            }
        }
        .foregroundStyle(.primary)
        .background(background(s))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(s.style.isGlass ? 0.25 : 0), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            ResizeGrip().frame(width: 16, height: 16)
        }
        // 포스트잇은 다크 모드에서도 종이처럼 밝게
        .environment(\.colorScheme, s.style.isGlass ? systemScheme : .light)
        .onAppear { reminders.watch(s.listID) }
        .onChange(of: s.listID) { _, newID in reminders.watch(newID) }
    }

    @ViewBuilder
    private func background(_ s: Sticker) -> some View {
        if s.style.isGlass {
            VisualEffectBackground()
        } else {
            s.style.paper
        }
    }

    // MARK: 머리 부분 (잡고 끌어서 이동)

    private func header(_ s: Sticker) -> some View {
        let count = (s.listID.flatMap { reminders.items[$0] } ?? []).filter { !$0.isCompleted }.count
        return HStack(spacing: 6) {
            Text(s.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .allowsHitTesting(false)
            if s.mode == .floating {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .opacity(0.45)
                    .allowsHitTesting(false)
            }
            Spacer(minLength: 4)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.45)
                    .allowsHitTesting(false)
            }
            settingsMenu(s)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(WindowDragHandle())
    }

    private func settingsMenu(_ s: Sticker) -> some View {
        Menu {
            if reminders.isAuthorized {
                Picker("연결된 미리 알림 목록", selection: Binding<String?>(
                    get: { s.listID },
                    set: { if let id = $0 { controller.link(s.id, listID: id) } }
                )) {
                    ForEach(reminders.lists, id: \.calendarIdentifier) { calendar in
                        Text(calendar.title).tag(Optional(calendar.calendarIdentifier))
                    }
                }
                Button("새 미리 알림 목록 만들기…") { controller.createList(for: s.id) }
                Divider()
            }
            Picker("스타일", selection: binding(s, \.style)) {
                ForEach(StickerStyle.allCases) { Text($0.label).tag($0) }
            }
            Picker("정렬", selection: binding(s, \.sortMode)) {
                ForEach(SortMode.allCases) { Text($0.label).tag($0) }
            }
            Toggle("완료한 항목 보기", isOn: binding(s, \.showCompleted))
            Toggle("다른 창 위에 띄우기", isOn: Binding(
                get: { s.mode == .floating },
                set: { controller.setMode(s.id, $0 ? .floating : .desktop) }
            ))
            Divider()
            Button("스티커 이름 바꾸기…") { controller.renameSticker(s.id) }
            Button("스티커 삭제…", role: .destructive) { controller.deleteSticker(s.id) }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func binding<T>(_ s: Sticker, _ keyPath: WritableKeyPath<Sticker, T>) -> Binding<T> {
        Binding(
            get: { s[keyPath: keyPath] },
            set: { value in store.update(s.id) { $0[keyPath: keyPath] = value } }
        )
    }

    // MARK: 본문

    @ViewBuilder
    private func content(_ s: Sticker) -> some View {
        if reminders.isDenied {
            message("미리 알림 접근이 꺼져 있어요.\n시스템 설정에서 켜 주세요.", button: "시스템 설정 열기") {
                reminders.openPrivacySettings()
            }
        } else if !reminders.isAuthorized {
            message("아이폰과 할 일을 동기화하려면\n미리 알림 접근을 허용해 주세요.", button: "접근 허용") {
                reminders.requestAccess()
            }
        } else if let listID = s.listID, reminders.list(listID) != nil {
            todoList(s, listID: listID)
            addField(s, listID: listID)
        } else {
            linkPrompt(s)
        }
    }

    private func message(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Text(text)
                .font(.callout)
                .multilineTextAlignment(.center)
                .opacity(0.75)
            Button(button, action: action)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func linkPrompt(_ s: Sticker) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Text("이 스티커에 연결할\n미리 알림 목록을 골라 주세요.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .opacity(0.75)
            Menu("기존 목록에서 고르기") {
                ForEach(reminders.lists, id: \.calendarIdentifier) { calendar in
                    Button(calendar.title) { controller.link(s.id, listID: calendar.calendarIdentifier) }
                }
            }
            .fixedSize()
            Button("새 목록 만들기…") { controller.createList(for: s.id) }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: 할 일 목록

    private func todoList(_ s: Sticker, listID: String) -> some View {
        let all = reminders.items[listID] ?? []
        let active = sortedActive(all.filter { !$0.isCompleted }, s)
        let done = all.filter { $0.isCompleted }
            .sorted { ($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast) }

        let moveAction: ((IndexSet, Int) -> Void)? =
            s.sortMode == .manual ? makeMoveAction(s, active: active) : nil

        return Group {
            if active.isEmpty && (done.isEmpty || !s.showCompleted) {
                VStack {
                    Spacer()
                    Text("할 일을 모두 끝냈어요")
                        .font(.callout)
                        .opacity(0.4)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(active) { row($0) }
                        .onMove(perform: moveAction)
                    if s.showCompleted {
                        ForEach(done) { row($0) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 24)
            }
        }
    }

    /// 드래그로 순서를 바꾸면 새 순서를 스티커 설정에 저장
    private func makeMoveAction(_ s: Sticker, active: [TodoItem]) -> (IndexSet, Int) -> Void {
        return { from, to in
            var ids = active.map(\.id)
            ids.move(fromOffsets: from, toOffset: to)
            let rest = s.order.filter { !ids.contains($0) }
            store.update(s.id) { $0.order = ids + rest }
        }
    }

    private func row(_ item: TodoItem) -> some View {
        TodoRow(
            item: item,
            onToggle: { reminders.toggle(item.id) },
            onRename: { reminders.rename(item.id, to: $0) },
            onPriority: { reminders.setPriority(item.id, $0) },
            onDue: { reminders.setDue(item.id, $0.components()) },
            onDelete: { reminders.delete(item.id) }
        )
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
    }

    private func sortedActive(_ items: [TodoItem], _ s: Sticker) -> [TodoItem] {
        switch s.sortMode {
        case .priority:
            return items.sorted {
                ($0.priority.rank, $0.dueKey, $0.createdKey) < ($1.priority.rank, $1.dueKey, $1.createdKey)
            }
        case .dueDate:
            return items.sorted {
                ($0.dueKey, $0.priority.rank, $0.createdKey) < ($1.dueKey, $1.priority.rank, $1.createdKey)
            }
        case .manual:
            var position: [String: Int] = [:]
            for (index, id) in s.order.enumerated() where position[id] == nil {
                position[id] = index
            }
            return items.sorted { a, b in
                switch (position[a.id], position[b.id]) {
                case let (x?, y?): return x < y
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return a.createdKey < b.createdKey
                }
            }
        }
    }

    // MARK: 추가 입력칸

    private func addField(_ s: Sticker, listID: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .opacity(0.45)
            TextField("할 일 추가", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($addFocused)
                .onSubmit {
                    let raw = newTitle.trimmingCharacters(in: .whitespaces)
                    guard !raw.isEmpty else { return }
                    controller.quickAdd(raw, to: s.id)
                    newTitle = ""
                    addFocused = true
                }
        }
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.05))
    }
}

// MARK: - 할 일 한 줄

struct TodoRow: View {
    let item: TodoItem
    var onToggle: () -> Void
    var onRename: (String) -> Void
    var onPriority: (Priority) -> Void
    var onDue: (DueOption) -> Void
    var onDelete: () -> Void

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(checkColor)
            }
            .buttonStyle(.plain)

            if editing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .onAppear { focused = true }
                    .onSubmit(commit)
                    .onExitCommand { editing = false }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused && editing { commit() }
                    }
            } else {
                Text(item.title)
                    .font(.system(size: 13))
                    .strikethrough(item.isCompleted)
                    .opacity(item.isCompleted ? 0.4 : 1)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: startEditing)
            }

            if !item.isCompleted, item.priority != .none {
                Text(item.priority.marks)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(item.priority.color)
            }

            if let due = item.dueDate {
                let color = dueColor(due)
                Text(DueFormat.label(due, hasTime: item.hasDueTime))
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(color.opacity(0.15)))
                    .foregroundStyle(color)
                    .opacity(item.isCompleted ? 0.4 : 1)
            }
        }
        .contextMenu {
            Button("이름 수정") { startEditing() }
            Menu("우선순위") {
                ForEach(Priority.allCases) { priority in
                    Button {
                        onPriority(priority)
                    } label: {
                        if priority == item.priority {
                            Label(priority.label, systemImage: "checkmark")
                        } else {
                            Text(priority.label)
                        }
                    }
                }
            }
            Menu("마감일") {
                ForEach(DueOption.allCases, id: \.self) { option in
                    Button(option.label) { onDue(option) }
                }
            }
            Divider()
            Button("삭제", role: .destructive, action: onDelete)
        }
    }

    private var checkColor: Color {
        if item.isCompleted { return .secondary }
        if item.priority == .none { return Color.primary.opacity(0.5) }
        return item.priority.color
    }

    private func dueColor(_ date: Date) -> Color {
        if !item.isCompleted && DueFormat.isOverdue(date, hasTime: item.hasDueTime) { return .red }
        if Calendar.current.isDateInToday(date) { return .orange }
        return Color.primary.opacity(0.6)
    }

    private func startEditing() {
        draft = item.title
        editing = true
    }

    private func commit() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        editing = false
        if !title.isEmpty && title != item.title { onRename(title) }
    }
}
