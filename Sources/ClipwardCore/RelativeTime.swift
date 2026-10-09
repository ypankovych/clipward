import Foundation

/// Compact "time ago" strings ("now", "5m ago", "3h ago", "2d ago", then a date).
/// Hand-rolled because `RelativeDateTimeFormatter` needs macOS 10.15.
public enum RelativeTime {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    public static func string(for date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "now"
        case ..<3_600: return "\(Int(seconds / 60))m ago"
        case ..<86_400: return "\(Int(seconds / 3_600))h ago"
        case ..<(7 * 86_400): return "\(Int(seconds / 86_400))d ago"
        default: return dateFormatter.string(from: date)
        }
    }
}
