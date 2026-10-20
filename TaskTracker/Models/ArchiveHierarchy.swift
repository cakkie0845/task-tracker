import Foundation

struct ArchiveYearGroup: Identifiable {
    let year: Int
    let months: [ArchiveMonthGroup]

    var id: Int { year }
    var taskCount: Int { months.reduce(0) { $0 + $1.taskCount } }
}

struct ArchiveMonthGroup: Identifiable {
    let year: Int
    let month: Int
    let weeks: [ArchiveWeekGroup]

    var id: String { "\(year)-\(month)" }
    var title: String { "\(month) 月" }
    var taskCount: Int { weeks.reduce(0) { $0 + $1.taskCount } }
}

struct ArchiveWeekGroup: Identifiable {
    let year: Int
    let month: Int
    let weekOfYear: Int
    let days: [ArchiveDayGroup]

    var id: String { "\(year)-\(month)-\(weekOfYear)" }
    var title: String { "第 \(weekOfYear) 周" }
    var taskCount: Int { days.reduce(0) { $0 + $1.taskCount } }
}

struct ArchiveDayGroup: Identifiable {
    let archive: ArchivedDay

    var id: UUID { archive.id }
    var taskCount: Int { archive.tasks.count }

    var title: String {
        Self.displayFormatter.string(from: archive.date)
    }

    var filenameDate: String {
        Self.filenameFormatter.string(from: archive.date)
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.setLocalizedDateFormatFromTemplate("MdEEEE")
        return formatter
    }()

    private static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum ArchiveHierarchyBuilder {
    static func build(
        from archivedDays: [ArchivedDay],
        calendar: Calendar = .autoupdatingCurrent
    ) -> [ArchiveYearGroup] {
        let byYear = Dictionary(grouping: archivedDays) {
            calendar.component(.year, from: $0.date)
        }

        return byYear.keys.sorted(by: >).map { year in
            let byMonth = Dictionary(grouping: byYear[year, default: []]) {
                calendar.component(.month, from: $0.date)
            }
            let months = byMonth.keys.sorted(by: >).map { month in
                let byWeek = Dictionary(grouping: byMonth[month, default: []]) {
                    calendar.component(.weekOfYear, from: $0.date)
                }
                let weeks = byWeek.keys.sorted(by: >).map { week in
                    let days = byWeek[week, default: []]
                        .sorted { $0.date > $1.date }
                        .map(ArchiveDayGroup.init)
                    return ArchiveWeekGroup(
                        year: year,
                        month: month,
                        weekOfYear: week,
                        days: days
                    )
                }
                return ArchiveMonthGroup(year: year, month: month, weeks: weeks)
            }
            return ArchiveYearGroup(year: year, months: months)
        }
    }
}
