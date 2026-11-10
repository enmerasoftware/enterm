import ActivityKit
import Combine
import EntermCore
import Foundation

/// Keeps one Live Activity in step with the Mac's sessions while there is work. iOS lets the app update it only
/// while the app runs; once it is suspended the picture stays as it was until the app returns.
/// Updates from the Mac while the phone sleeps need the relay to push them (APNs `liveactivity`); not yet.
@MainActor
final class LiveStatus {
    static let shared = LiveStatus()
    private var activity: Activity<AgentActivityAttributes>?
    private var watching: AnyCancellable?

    func start(model: PhoneModel) {
        guard watching == nil else { return }
        // Several session messages arrive at once; one update for them is enough.
        watching = model.$sessions
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self, weak model] sessions in
                guard let self, let model else { return }
                self.apply(sessions, mac: model.peerName)
            }
    }

    private func apply(_ sessions: [SessionInfo], mac: String) {
        let agents = sessions.filter { $0.tool != .terminal }
        let waiting = agents.filter { $0.status == .needsApproval }
        let working = agents.filter { $0.status == .running }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if waiting.isEmpty && working.isEmpty {
            end()
            return
        }
        let lead = waiting.first ?? working.min { $0.startedAt < $1.startedAt }!
        let state = AgentActivityAttributes.ContentState(
            working: working.count, waiting: waiting.count,
            lead: lead.name.isEmpty ? (lead.title ?? lead.tool.title) : lead.name,
            leadStatus: lead.status.title, updatedAt: Date())
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(15 * 60))
        if let activity {
            Task { await activity.update(content) }
        } else {
            // Starting needs the app in front; when it is not, the next change while it is will start it.
            activity = try? Activity.request(attributes: AgentActivityAttributes(mac: mac), content: content, pushType: nil)
        }
    }

    private func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .default) }
    }
}

extension PhoneModel {
    var peerName: String { peer?.name ?? "Mac" }
}
