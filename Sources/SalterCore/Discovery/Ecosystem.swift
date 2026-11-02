import Foundation

/// A language toolchain family; launch.json and manifest discovery are matched per ecosystem.
public enum Ecosystem: String, Sendable, CaseIterable {
    case go, rust, node, python, java, dotnet

    /// The ecosystem a VS Code launch configuration `type` belongs to.
    public static func forLaunchType(_ type: String) -> Ecosystem? {
        switch type {
        case "go": return .go
        case "lldb", "codelldb": return .rust
        case "node", "pwa-node": return .node
        case "debugpy", "python": return .python
        case "java": return .java
        case "coreclr": return .dotnet
        default: return nil
        }
    }
}
