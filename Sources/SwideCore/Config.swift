import Foundation

public struct Config: Codable, Equatable, Sendable {
    public struct Protect: Codable, Equatable, Sendable {
        public var pinned = true
        public var claudeWorking = true

        public init() {}
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? true
            claudeWorking = try c.decodeIfPresent(Bool.self, forKey: .claudeWorking) ?? true
        }
    }

    public var hotkey = "option+space"
    public var ide = IDE.cursor
    public var maxWindows = 3
    public var searchRoot = "~/dev"
    /// Seconds before a keyboard selection opens on its own; 0 waits for ↵.
    public var autoOpenDelay = 0.8
    public var protect = Protect()

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hotkey = try c.decodeIfPresent(String.self, forKey: .hotkey) ?? hotkey
        // An unknown IDE falls back to the default instead of rejecting the whole file.
        ide = (try? c.decodeIfPresent(IDE.self, forKey: .ide)) ?? ide
        maxWindows = max(1, try c.decodeIfPresent(Int.self, forKey: .maxWindows) ?? maxWindows)
        searchRoot = try c.decodeIfPresent(String.self, forKey: .searchRoot) ?? searchRoot
        autoOpenDelay = max(0, try c.decodeIfPresent(Double.self, forKey: .autoOpenDelay) ?? autoOpenDelay)
        protect = try c.decodeIfPresent(Protect.self, forKey: .protect) ?? protect
    }

    /// Reads the config file, creating it with defaults on first launch.
    public static func load(from url: URL = Paths.configFile) -> Config {
        if let data = try? Data(contentsOf: url), let config = try? JSONDecoder().decode(Config.self, from: data) {
            return config
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            Config().save(to: url)
        }
        return Config()
    }

    public func save(to url: URL = Paths.configFile) {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try? e.encode(self).writeAtomically(to: url)
    }
}

/// Swide's own memory: pins and last-use times per project path.
public struct AppState: Codable, Equatable, Sendable {
    public var pinned: Set<String> = []
    public var lastActive: [String: Double] = [:]

    public init() {}

    public static func load(from url: URL = Paths.stateFile) -> AppState {
        guard let data = try? Data(contentsOf: url) else { return AppState() }
        return (try? JSONDecoder().decode(AppState.self, from: data)) ?? AppState()
    }

    public func save(to url: URL = Paths.stateFile) {
        try? JSONEncoder().encode(self).writeAtomically(to: url)
    }
}
