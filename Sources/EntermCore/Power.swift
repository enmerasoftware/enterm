import Foundation

/// The system's memory pressure, read from the kernel. The dispatch source only reports changes,
/// so pressure that started before launch has to be read directly.
public enum MemoryPressureLevel: Int, Comparable {
    case normal = 1
    case warning = 2
    case critical = 4

    public static func < (lhs: MemoryPressureLevel, rhs: MemoryPressureLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(kernelValue: Int) {
        switch kernelValue {
        case 2: self = .warning
        case 4: self = .critical
        default: self = .normal
        }
    }

    public static func current() -> MemoryPressureLevel {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0) == 0 else { return .normal }
        return MemoryPressureLevel(kernelValue: Int(value))
    }

    public var title: String {
        switch self {
        case .normal: return "Yok"
        case .warning: return "Uyarı"
        case .critical: return "Kritik"
        }
    }
}

public enum PowerRules {
    /// Why a new agent must wait, or nil. Plain terminals never come here.
    /// Under a warning the first agent may still start: on a small Mac the warning can be permanent.
    public static func blockReason(running: Int, maxSessions: Int, cpuLimit: Int, cpuUsed: Double, pressure: MemoryPressureLevel) -> String? {
        if running >= maxSessions { return "Aynı Anda En Çok \(maxSessions) Oturum" }
        guard cpuLimit < 100 else { return nil }
        if cpuUsed >= Double(cpuLimit) { return "İşlemci En Çok %\(cpuLimit)" }
        if pressure == .critical { return "Bellek Baskısı Kritik" }
        if pressure == .warning, running >= 1 { return "Bellek Baskısı" }
        return nil
    }
}
