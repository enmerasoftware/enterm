import AppKit
import EntermCore
import SwiftUI

struct PageRouter: View {
    let page: Page
    var body: some View {
        switch page {
        case .notYet(let name): NotYet(name: name)
        default: NotYet(name: "Henüz Yok")
        }
    }
}

struct DetailTabs: View {
    let info: SessionInfo
    var body: some View { VStack { Dim("Henüz Yok") } }
}

struct NewSessionOptions: View { var body: some View { Dim("Henüz Yok") } }
struct LinkPermissionDialog: View { let from: UInt32; let to: UInt32; var body: some View { Dim("Henüz Yok") } }
struct LinkDetailDialog: View { let id: String; var body: some View { Dim("Henüz Yok") } }
struct ApprovalDialog: View { let id: String; var body: some View { Dim("Henüz Yok") } }
struct LimitDialog: View { let number: UInt32; var body: some View { Dim("Henüz Yok") } }

enum Approvals { static func decide(id: String, decision: String) {} }
enum LimitActions { static func perform(index: Int) {} }

final class VoiceInput {
    static let shared = VoiceInput()
    func flagsChanged(_ event: NSEvent) {}
}

final class BoardStore: ObservableObject {
    static let shared = BoardStore()
    @Published var board = Board.load()
    func reload() { board = Board.load() }
}
final class TeamStore: ObservableObject {
    static let shared = TeamStore()
    @Published var team = Team.load()
    func reload() { team = Team.load() }
}
