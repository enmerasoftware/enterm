import ActivityKit
import SwiftUI
import WidgetKit

@main
struct EntermWidgets: WidgetBundle {
    var body: some Widget { AgentActivityWidget() }
}

/// Plain colours: a Live Activity draws outside the app's theme, on any wallpaper.
private let lime = Color(red: 0.84, green: 0.95, blue: 0.27)
private let amber = Color(red: 1.0, green: 0.72, blue: 0.24)

struct AgentActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgentActivityAttributes.self) { context in
            LockScreenView(state: context.state, mac: context.attributes.mac)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(state.working)", systemImage: "bolt.fill").foregroundStyle(lime)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if state.waiting > 0 { Label("\(state.waiting)", systemImage: "hand.raised.fill").foregroundStyle(amber) }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(state.lead) · \(state.leadStatus)").font(.footnote).lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "bolt.fill").foregroundStyle(lime)
            } compactTrailing: {
                Text(state.waiting > 0 ? "\(state.waiting)!" : "\(state.working)")
                    .foregroundStyle(state.waiting > 0 ? amber : lime)
            } minimal: {
                Image(systemName: state.waiting > 0 ? "hand.raised.fill" : "bolt.fill")
                    .foregroundStyle(state.waiting > 0 ? amber : lime)
            }
        }
    }
}

private struct LockScreenView: View {
    let state: AgentActivityAttributes.ContentState
    let mac: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Enterm · \(mac)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(state.updatedAt, style: .time).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Label("\(state.working) Çalışıyor", systemImage: "bolt.fill").foregroundStyle(lime)
                if state.waiting > 0 {
                    Label("\(state.waiting) Onay Bekliyor", systemImage: "hand.raised.fill").foregroundStyle(amber)
                }
            }
            .font(.subheadline.weight(.semibold))
            Text("\(state.lead) · \(state.leadStatus)").font(.footnote).foregroundStyle(.white).lineLimit(1)
        }
        .padding(14)
    }
}
