import Foundation

// MARK: - Date Formatting

extension Date {
    var shortTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: self)
    }
}

// MARK: - Optional Unwrap Helper

extension Optional where Wrapped == String {
    var orEmpty: String {
        self ?? ""
    }
}
