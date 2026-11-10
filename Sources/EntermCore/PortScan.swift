import Foundation

/// Which TCP ports a session's programs listen on, from `ps` and `lsof` output. Nothing here runs a process.
public enum PortScan {
    /// `ps -axo pid=,ppid=`: every process and its parent.
    public static func parents(_ text: String) -> [Int32: Int32] {
        var result: [Int32: Int32] = [:]
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 2, let pid = Int32(fields[0]), let parent = Int32(fields[1]) else { continue }
            result[pid] = parent
        }
        return result
    }

    /// The process and everything it started, however deep.
    public static func tree(root: Int32, parents: [Int32: Int32]) -> Set<Int32> {
        var children: [Int32: [Int32]] = [:]
        for (pid, parent) in parents { children[parent, default: []].append(pid) }
        var found: Set<Int32> = [root]
        var stack = [root]
        while let next = stack.popLast() {
            for child in children[next] ?? [] where !found.contains(child) {
                found.insert(child)
                stack.append(child)
            }
        }
        return found
    }

    /// `lsof -nP -iTCP -sTCP:LISTEN -F pn`: a `p<pid>` line, then one `n<address>:<port>` line per socket.
    public static func listening(_ text: String) -> [Int32: [Int]] {
        var result: [Int32: [Int]] = [:]
        var current: Int32?
        for line in text.split(separator: "\n") {
            if line.hasPrefix("p") {
                current = Int32(line.dropFirst())
            } else if line.hasPrefix("n"), let pid = current, let colon = line.lastIndex(of: ":"), let port = Int(line[line.index(after: colon)...]) {
                if !(result[pid]?.contains(port) ?? false) { result[pid, default: []].append(port) }
            }
        }
        return result
    }

    /// The ports of one session, sorted. Nil when there are none, so an unchanged session stays equal.
    public static func ports(root: Int32, parents: [Int32: Int32], listening: [Int32: [Int]]) -> [Int]? {
        let mine = tree(root: root, parents: parents)
        let ports = Set(mine.flatMap { listening[$0] ?? [] }).sorted()
        return ports.isEmpty ? nil : ports
    }
}
