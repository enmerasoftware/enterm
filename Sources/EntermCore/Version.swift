import Foundation

public enum EntermVersion {
    public static let current = "0.1.4"

    /// Tells two builds apart: a service that outlived an update reports the old value.
    public static func stamp(ofExecutable path: String) -> String? {
        guard let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date else { return nil }
        return String(Int(date.timeIntervalSince1970))
    }
}
