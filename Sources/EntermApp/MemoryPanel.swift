import AppKit
import EntermCore
import SwiftUI

/// What Activity Monitor calls memory. Under pressure the resident size that ps shows falls while the load stays.
func memoryFootprintKB(_ pid: Int32) -> Int? {
    var info = rusage_info_current()
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0) }
    }
    return result == 0 ? Int(info.ri_phys_footprint / 1024) : nil
}

/// The machine's memory as Activity Monitor shows it: in use, swap and pressure.
struct SystemMemory: Equatable {
    var totalMB = 0
    var usedMB = 0
    var swapUsedMB = 0
    var swapTotalMB = 0
    /// 1 normal, 2 warning, 4 critical, as the kernel reports it.
    var pressure = 1

    static func read() -> SystemMemory {
        var result = SystemMemory()
        result.totalMB = Int(ProcessInfo.processInfo.physicalMemory / 1_048_576)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        if status == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            // App memory, wired and compressed: the "Memory Used" of Activity Monitor.
            let app = UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count)
            let pages = app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
            result.usedMB = Int(pages * page / 1_048_576)
        }
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            result.swapUsedMB = Int(swap.xsu_used / 1_048_576)
            result.swapTotalMB = Int(swap.xsu_total / 1_048_576)
        }
        var level: Int32 = 1
        size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 { result.pressure = Int(level) }
        return result
    }
}

/// Where the memory goes, session by session. It measures once when opened and again only when asked.
struct MemoryPanel: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var model = AppModel.shared
    @ObservedObject var power = PowerCenter.shared
    @State private var rows: [Row] = []
    @State private var own = 0
    @State private var measured = false
    @State private var system = SystemMemory()

    struct Row: Identifiable {
        let id: UInt32
        let name: String
        let tool: String
        let rssKB: Int
        let children: Int
    }

    var body: some View {
        let palette = Theme.palette
        Panel {
            PanelHeader(title: "Bellek") {
                // 30 in the 48 band leaves 9 above and below; pulled to 9 from the edge so its hover fill is even on three sides.
                IconBtn("arrow.clockwise", label: "Yeniden Ölç") { measure() }
                    .help("Yeniden Ölç")
                    .padding(.trailing, -11)
            }
            if measured { machine }
            VStack(spacing: 0) {
                if !measured {
                    HStack { Dim("Ölçülüyor"); Spacer() }.padding(.horizontal, 20).padding(.vertical, 12).frame(minHeight: 44)
                }
                ForEach(rows) { row in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            T(row.name).lineLimit(1)
                            Dim(row.children > 0 ? "\(row.tool) · \(row.children) Alt Süreç" : row.tool).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        T(Self.size(row.rssKB), style: .secondary, weight: .medium)
                        IconBtn("xmark", label: "Oturumu Kapat") { close(row.id) }
                            .help("Oturumu Kapat")
                    }
                    // The same rhythm as Row: 12 above and below, so two-line rows do not touch the lines.
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(minHeight: 44)
                    .overlay(alignment: .top) { Line() }
                }
                if measured {
                    HStack(spacing: 8) {
                        Circle().fill(Color(palette.add)).frame(width: 7, height: 7).neon(palette.add, radius: 3)
                        T("Enterm", bold: true)
                        Spacer()
                        T(Self.size(own), style: .secondary, weight: .semibold)
                        // The close button's slot (4 + 8 = the rows' 12), so the sizes line up in one column.
                        Color.clear.frame(width: 30, height: 1).padding(.leading, 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(minHeight: 44)
                    .overlay(alignment: .top) { Line() }
                }
            }
            Dim("Programların yükü Enterm'in elinde değildir. Aynı anda çalışan oturum sayısıyla azalır.")
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .overlay(alignment: .top) { Line() }
        }
        .frame(width: 420)
        .onAppear(perform: measure)
    }

    /// The whole machine first: whether memory is short at all decides whether the rows below matter.
    private var machine: some View {
        let palette = Theme.palette
        let color: NSColor = system.pressure >= 4 ? palette.err : (system.pressure >= 2 ? palette.limit : palette.add)
        let state = system.pressure >= 4 ? "Bellek Çok Sıkışık" : (system.pressure >= 2 ? "Bellek Sıkışık" : "Bellek Rahat")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(Color(color)).frame(width: 7, height: 7).neon(color, radius: 3)
                T(state, bold: true)
                Spacer()
                T("\(Self.size(system.usedMB * 1024)) / \(Self.size(system.totalMB * 1024))", style: .secondary, weight: .medium)
            }
            Meter(percent: system.totalMB > 0 ? Double(system.usedMB) * 100 / Double(system.totalMB) : 0, warn: system.pressure >= 2)
            HStack {
                Dim("Swap (Diske Taşan Bellek)")
                Spacer()
                T(system.swapUsedMB > 0 ? Self.size(system.swapUsedMB * 1024) : "Kullanılmıyor", style: .secondary)
            }
            if system.swapUsedMB > 512 || system.pressure >= 2 {
                Dim("Swap'ı macOS yönetir; hiçbir uygulama onu doğrudan boşaltamaz. Bellek açıldıkça kendiliğinden azalır. En çok yer tutan oturumu aşağıdan kapatmak en hızlı çaredir.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // The first row below draws the line between them.
        .padding(20)
    }

    static func size(_ kb: Int) -> String {
        kb >= 1024 * 1024 ? String(format: "%.1f GB", Double(kb) / 1024 / 1024) : "\(kb / 1024) MB"
    }

    private func close(_ number: UInt32) {
        model.confirm(title: "Oturum Kapatılsın mı?", detail: "İçinde çalışan program da kapanır.", action: "Kapat", danger: true) {
            model.close(number)
        }
    }

    private func measure() {
        let sessions = model.sessions
        let labels = sessions.map { (number: $0.number, name: model.name(for: $0), tool: $0.tool.title, pid: $0.pid) }
        DispatchQueue.global(qos: .utility).async {
            let machine = SystemMemory.read()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-axo", "pid=,ppid=,rss=,comm="]
            process.environment = ["LC_ALL": "C"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let entries = ProcessTree.parse(String(decoding: data, as: UTF8.self)).map {
                ProcessTree.Entry(pid: $0.pid, parent: $0.parent, rssKB: memoryFootprintKB($0.pid) ?? $0.rssKB, name: $0.name)
            }
            let rows = labels.compactMap { label -> Row? in
                guard let pid = label.pid else { return nil }
                let total = ProcessTree.total(root: pid, in: entries)
                return Row(id: label.number, name: label.name, tool: label.tool, rssKB: total.rssKB, children: total.children)
            }.sorted { $0.rssKB > $1.rssKB }
            let own = entries.filter { $0.name == "EntermApp" || $0.name == "entermd" }.reduce(0) { $0 + $1.rssKB }
            DispatchQueue.main.async {
                self.rows = rows
                self.own = own
                self.system = machine
                self.measured = true
            }
        }
    }
}
