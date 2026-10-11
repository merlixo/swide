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
    public var maxWindows = 3
    public var searchRoot = "~/dev"
    public var protect = Protect()

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hotkey = try c.decodeIfPresent(String.self, forKey: .hotkey) ?? hotkey
        maxWindows = max(1, try c.decodeIfPresent(Int.self, forKey: .maxWindows) ?? maxWindows)
        searchRoot = try c.decodeIfPresent(String.self, forKey: .searchRoot) ?? searchRoot
        protect = try c.decodeIfPresent(Protect.self, forKey: .protect) ?? protect
    }

    /// Reads the config file, creating it with defaults on first launch.
    public static func load(from url: URL = Paths.configFile) -> Config {
        if let data = try? Data(contentsOf: url), let config = try? JSONDecoder().decode(Config.self, from: data) {
            return config
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            let e = JSONEncoder()
            e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try? e.encode(Config()).writeAtomically(to: url)
        }
        return Config()
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
