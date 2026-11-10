import ActivityKit
import Foundation

/// The Lock Screen and Dynamic Island picture of the Mac's agents: how many work, how many wait for the person.
/// Shared by the app, which starts and updates it, and the widget extension, which draws it.
struct AgentActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var working: Int
        var waiting: Int
        /// The session that needs the person, else the one working longest.
        var lead: String
        var leadStatus: String
        var updatedAt: Date
    }
    /// The paired Mac's name.
    var mac: String
}
