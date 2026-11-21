import SwiftUI

// MARK: - 스티커 스타일

enum StickerStyle: String, Codable, CaseIterable, Identifiable {
    case yellow, pink, mint, sky, lavender, glass

    var id: String { rawValue }

    var label: String {
        switch self {
        case .yellow: return "노랑 포스트잇"
        case .pink: return "분홍 포스트잇"
        case .mint: return "민트 포스트잇"
        case .sky: return "하늘 포스트잇"
        case .lavender: return "라벤더 포스트잇"
        case .glass: return "반투명 유리"
        }
    }

    var paper: Color {
        switch self {
        case .yellow: return Color(red: 1.00, green: 0.93, blue: 0.60)
        case .pink: return Color(red: 1.00, green: 0.83, blue: 0.87)
        case .mint: return Color(red: 0.78, green: 0.95, blue: 0.86)
        case .sky: return Color(red: 0.79, green: 0.89, blue: 1.00)
        case .lavender: return Color(red: 0.89, green: 0.85, blue: 1.00)
        case .glass: return .clear
        }
    }

    var isGlass: Bool { self == .glass }
}

// MARK: - 창 모드 / 정렬

enum WindowMode: String, Codable {
    case desktop   // 바탕화면에 붙어 있음 (다른 창 뒤)
    case floating  // 다른 창 위에 떠 있음
}

enum SortMode: String, Codable, CaseIterable, Identifiable {
    case manual, priority, dueDate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: return "직접 정렬 (드래그)"
        case .priority: return "우선순위순"
        case .dueDate: return "마감일순"
        }
    }
}

// MARK: - 스티커

struct StickerFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct Sticker: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    /// 연결된 미리 알림 목록 (EKCalendar.calendarIdentifier)
    var listID: String? = nil
    var style: StickerStyle = .yellow
    var mode: WindowMode = .desktop
    var sortMode: SortMode = .manual
    var showCompleted: Bool = true
    var frame: StickerFrame
    /// 직접 정렬 순서 (미리 알림 ID 목록). 미리 알림 앱은 순서를 외부에 공개하지 않아서 앱 안에만 저장해요.
    var order: [String] = []
}

// MARK: - 우선순위 (미리 알림 앱 규칙과 동일: 1~4 높음, 5 보통, 6~9 낮음)

enum Priority: Int, CaseIterable, Identifiable {
    case high = 1, medium = 5, low = 9, none = 0

    var id: Int { rawValue }

    init(ekValue: Int) {
        switch ekValue {
        case 1...4: self = .high
        case 5: self = .medium
        case 6...9: self = .low
        default: self = .none
        }
    }

    var label: String {
        switch self {
        case .high: return "높음  !!!"
        case .medium: return "보통  !!"
        case .low: return "낮음  !"
        case .none: return "없음"
        }
    }

    var marks: String {
        switch self {
        case .high: return "!!!"
        case .medium: return "!!"
        case .low: return "!"
        case .none: return ""
        }
    }

    var rank: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        case .none: return 3
        }
    }

    var color: Color {
        switch self {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        case .none: return .secondary
        }
    }
}

// MARK: - 마감일 빠른 선택

enum DueOption: CaseIterable {
    case today, tomorrow, nextWeek, none

    var label: String {
        switch self {
        case .today: return "오늘"
        case .tomorrow: return "내일"
        case .nextWeek: return "일주일 뒤"
        case .none: return "마감일 없음"
        }
    }

    func components() -> DateComponents? {
        let days: Int
        switch self {
        case .today: days = 0
        case .tomorrow: days = 1
        case .nextWeek: days = 7
        case .none: return nil
        }
        return DueFormat.dayComponents(offset: days)
    }
}

enum DueFormat {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func dayComponents(offset: Int) -> DateComponents {
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        let day = cal.date(byAdding: .day, value: offset, to: base) ?? base
        return cal.dateComponents([.year, .month, .day], from: day)
    }

    static func label(_ date: Date, hasTime: Bool) -> String {
        let cal = Calendar.current
        let day: String
        if cal.isDateInToday(date) {
            day = "오늘"
        } else if cal.isDateInTomorrow(date) {
            day = "내일"
        } else if cal.isDateInYesterday(date) {
            day = "어제"
        } else {
            day = dayFormatter.string(from: date)
        }
        return hasTime ? "\(day) \(timeFormatter.string(from: date))" : day
    }

    static func isOverdue(_ date: Date, hasTime: Bool) -> Bool {
        if hasTime { return date < Date() }
        return date < Calendar.current.startOfDay(for: Date())
    }
}

// MARK: - 빠른 입력 해석
// "보고서 제출 내일 !!" → 제목 "보고서 제출", 마감 내일, 우선순위 보통

struct QuickInput {
    var title: String
    var priority: Priority
    var due: DateComponents?
}

enum QuickParser {
    static func parse(_ raw: String) -> QuickInput {
        var priority = Priority.none
        var dueOffset: Int? = nil
        var kept: [String] = []

        for word in raw.split(separator: " ", omittingEmptySubsequences: true).map(String.init) {
            switch word {
            case "!!!": priority = .high
            case "!!": priority = .medium
            case "!": priority = .low
            case "오늘": dueOffset = 0
            case "내일": dueOffset = 1
            case "모레": dueOffset = 2
            default: kept.append(word)
            }
        }

        let title = kept.joined(separator: " ")
        return QuickInput(
            title: title.isEmpty ? raw.trimmingCharacters(in: .whitespaces) : title,
            priority: priority,
            due: dueOffset.map { DueFormat.dayComponents(offset: $0) }
        )
    }
}
