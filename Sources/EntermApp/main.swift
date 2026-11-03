import AppKit

// Sessions come back through the session service, so AppKit's window restoration has nothing to add.
UserDefaults.standard.set(true, forKey: "ApplePersistenceIgnoreState")
UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
