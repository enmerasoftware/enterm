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

/// Where the memory goes, session by session. It measures once when opened and again only when asked.
struct MemoryPanel: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var model = AppModel.shared
    @ObservedObject var power = PowerCenter.shared
    @State private var rows: [Row] = []
    @State private var own = 0
    @State private var measured = false

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
                Btn("Yeniden Ölç", kind: .plain) { measure() }
            }
            VStack(spacing: 0) {
                if !measured {
                    HStack { Dim("Ölçülüyor"); Spacer() }.padding(.horizontal, 20).frame(height: 44)
                }
                ForEach(rows) { row in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            T(row.name).lineLimit(1)
                            Dim(row.children > 0 ? "\(row.tool) · \(row.children) Alt Süreç" : row.tool).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        T(Self.size(row.rssKB), style: .secondary, weight: .medium)
                        Button { close(row.id) } label: {
                            Symbol("xmark", color: palette.text3, size: 10).frame(width: 22, height: 22).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Oturumu Kapat")
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                    .overlay(alignment: .top) { Line() }
                }
                if measured {
                    HStack(spacing: 8) {
                        Circle().fill(Color(palette.add)).frame(width: 7, height: 7).neon(palette.add, radius: 3)
                        T("Enterm", bold: true)
                        Spacer()
                        T(Self.size(own), style: .secondary, weight: .semibold)
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                    .overlay(alignment: .top) { Line() }
                }
            }
            HStack {
                Dim("Programların yükü Enterm'in elinde değildir. Aynı anda çalışan oturum sayısıyla azalır.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20))
        }
        .frame(width: 420)
        .onAppear(perform: measure)
    }

    static func size(_ kb: Int) -> String {
        kb >= 1024 * 1024 ? String(format: "%.1f GB", Double(kb) / 1024 / 1024) : "\(kb / 1024) MB"
    }

    private func close(_ number: UInt32) {
        model.confirm(title: "Oturum Kapatılsın mı?", detail: "İçinde çalışan program da kapanır.", action: "Kapat") {
            model.close(number)
        }
    }

    private func measure() {
        let sessions = model.sessions
        let labels = sessions.map { (number: $0.number, name: model.name(for: $0), tool: $0.tool.title, pid: $0.pid) }
        DispatchQueue.global(qos: .utility).async {
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
                self.measured = true
            }
        }
    }
}
