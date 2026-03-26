import Foundation

extension Date {
    func formatted(as style: DateFormatStyle) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        switch style {
        case .short:
            formatter.dateStyle = .short
            formatter.timeStyle = .none
        case .medium:
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
        case .long:
            formatter.dateStyle = .long
            formatter.timeStyle = .none
        case .dateTime:
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
        case .relative:
            let relative = RelativeDateTimeFormatter()
            relative.unitsStyle = .abbreviated
            return relative.localizedString(for: self, relativeTo: Date())
        case .invoiceDate:
            formatter.dateFormat = "MMM d, yyyy"
        }
        return formatter.string(from: self)
    }

    enum DateFormatStyle {
        case short
        case medium
        case long
        case dateTime
        case relative
        case invoiceDate
    }
}
