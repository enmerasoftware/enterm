import Combine
import EntermCore
import SwiftUI

/// The races on the Mac, from the phone: who finished in which place, and the winner picked with a thumb.
struct RaceScreen: View {
    @EnvironmentObject var model: PhoneModel
    var body: some View {
        VStack(spacing: 0) {
            RouteHeader(back: "Ayarlar", trailing: "Yarışlar")
            Loaded(call: PhoneCall("races"), type: [Race].self) { races, reload in
                RaceList(races: races, reload: reload)
            }
        }
        .background(Palette.bg)
    }
}

private struct RaceList: View {
    @EnvironmentObject var model: PhoneModel
    let races: [Race]
    let reload: () -> Void
    /// While someone is still running, the places change; a look every few seconds is enough.
    private let tick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if races.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "flag.checkered").font(.system(size: 34)).foregroundColor(Palette.text3)
                        Txt("Henüz Yarış Yok", bold: true)
                        DimTxt("Mac'te ⋯ menüsünden Yarış Başlat'ı seçin. Aynı görev birkaç ajana verilir, kazananı buradan da seçersiniz.")
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                } else {
                    ForEach(races) { race in RaceCard(race: race, reload: reload) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .onReceive(tick) { _ in
            if races.contains(where: { !$0.closed && !$0.isFinished }) { reload() }
        }
    }
}

private struct RaceCard: View {
    @EnvironmentObject var model: PhoneModel
    let race: Race
    let reload: () -> Void
    @State private var merging: RaceEntrant?
    @State private var dropping = false
    @State private var problem: String?

    var body: some View {
        Card {
            Txt(race.task, bold: true).lineLimit(3)
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Txt(status, color: Palette.text2, style: .subheadline)
            }
            VStack(spacing: 0) {
                ForEach(Array(race.standings.enumerated()), id: \.element.id) { index, entrant in
                    if index > 0 { Rectangle().fill(Palette.hair).frame(height: 1) }
                    row(entrant)
                }
            }
            if let problem { Txt(problem, color: Palette.err, style: .subheadline) }
            if !race.closed {
                ButtonPair {
                    ActionButton("Yarışı Bırak", style: .destructive) { dropping = true }
                } main: {
                    ActionButton("Hepsini Test Et") { send(PhoneCall("raceTest", args: ["id": race.id])) }
                        .disabled(race.testCommand == nil)
                        .opacity(race.testCommand == nil ? 0.4 : 1)
                }
            }
        }
        .confirmationDialog(L("\(merging?.title ?? "") Birleştirilsin mi?"), isPresented: Binding(get: { merging != nil }, set: { if !$0 { merging = nil } }), titleVisibility: .visible) {
            Button(L("Birleştir")) {
                if let entrant = merging { send(PhoneCall("raceMerge", args: ["id": race.id, "branch": entrant.branch]), success: true) }
            }
            Button(L("Vazgeç"), role: .cancel) {}
        } message: {
            Text("Dalı ana klasöre birleştirilir. Diğer kutular kapanır, bütün worktree'ler silinir.")
        }
        .confirmationDialog(L("Yarış Bırakılsın mı?"), isPresented: $dropping, titleVisibility: .visible) {
            Button(L("Yarışı Bırak"), role: .destructive) { send(PhoneCall("raceDrop", args: ["id": race.id])) }
            Button(L("Vazgeç"), role: .cancel) {}
        } message: {
            Text("Bütün kutular kapanır, worktree'ler ve dallar silinir. Ana klasörünüz değişmez.")
        }
    }

    private var status: String {
        if let winner = race.winner, let entrant = race.entrants.first(where: { $0.branch == winner }) { return L("Kazanan: \(entrant.title)") }
        if race.closed { return "Bırakıldı" }
        return race.isFinished ? "Herkes Bitirdi · Kazananı Seçin" : "Yarış Sürüyor"
    }

    private var statusColor: Color {
        if race.winner != nil { return Palette.need }
        if race.closed { return Palette.text3 }
        return race.isFinished ? Palette.need : Palette.add
    }

    private func row(_ entrant: RaceEntrant) -> some View {
        let place = race.place(of: entrant.branch)
        let winner = race.winner == entrant.branch
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(Self.medal(place)).frame(width: 30, height: 30)
                Text(verbatim: place.map { "\($0)" } ?? "…")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(place == nil ? Palette.text2 : Palette.btnfg)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Txt(entrant.title, weight: .semibold).lineLimit(1)
                    if winner { Image(systemName: "trophy.fill").font(.caption).foregroundColor(Palette.need) }
                }
                Txt("\(Self.clock(entrant.duration)) · \(Self.files(entrant.stat.files)) · +\(entrant.stat.insertions) −\(entrant.stat.deletions)",
                    color: Palette.text2, style: .footnote).lineLimit(1)
                if let tests = entrant.tests {
                    Txt(tests == .passed ? "✓ Testler Geçti" : (tests == .failed ? "✗ Testler Kaldı" : "Test Sürüyor…"),
                        color: tests == .passed ? Palette.add : (tests == .failed ? Palette.err : Palette.text2), style: .footnote, weight: .medium)
                }
            }
            Spacer(minLength: 8)
            if !race.closed, race.isFinished {
                Button { merging = entrant } label: {
                    Txt("Kazanan Bu", color: Palette.btnfg, style: .subheadline, weight: .semibold)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(Palette.btn)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
    }

    private func send(_ call: PhoneCall, success: Bool = false) {
        Task {
            switch await model.call(call, as: PhoneNothing.self) {
            case .success:
                problem = nil
                if success { Haptic.success() }
                reload()
            case .failure(let error):
                problem = error.message
            }
        }
    }

    static func medal(_ place: Int?) -> Color {
        switch place {
        case 1?: return Color(hex: 0xF4C84A)
        case 2?: return Color(hex: 0xC9D1D6)
        case 3?: return Color(hex: 0xD39A6A)
        case _?: return Palette.text3
        case nil: return Palette.fill
        }
    }

    static func clock(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "–" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func files(_ count: Int) -> String {
        Loc.isTurkish ? "\(count) dosya" : (count == 1 ? "1 file" : "\(count) files")
    }
}
