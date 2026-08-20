import Foundation

nonisolated struct PerformanceDateRange: Equatable, Sendable {
    let startInclusive: Date
    let endExclusive: Date

    init(
        startDate: Date,
        endDate: Date,
        calendar: Calendar = .current
    ) throws {
        let startOfFirstDay = calendar.startOfDay(for: startDate)
        let startOfLastDay = calendar.startOfDay(for: endDate)

        guard startOfFirstDay <= startOfLastDay else {
            throw PerformanceDateRangeError.reversedRange
        }
        guard let startOfFollowingDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: startOfLastDay
        ) else {
            throw PerformanceDateRangeError.cannotCalculateEndDate
        }

        startInclusive = startOfFirstDay
        endExclusive = startOfFollowingDay
    }

    func contains(_ date: Date) -> Bool {
        date >= startInclusive && date < endExclusive
    }
}

nonisolated enum PerformanceDateRangeError: LocalizedError, Equatable {
    case reversedRange
    case cannotCalculateEndDate

    var errorDescription: String? {
        switch self {
        case .reversedRange:
            "마지막 날짜는 시작 날짜보다 앞설 수 없습니다."
        case .cannotCalculateEndDate:
            "선택한 날짜 범위를 계산할 수 없습니다."
        }
    }
}
