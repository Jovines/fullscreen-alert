import Foundation

struct Config: Codable {
    var disabled: Bool = false

    static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/fullscreen-alert")
    static let configPath = configDir.appendingPathComponent("config.json")

    static func load() -> Config {
        guard let data = try? Data(contentsOf: configPath),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return Config()
        }
        return config
    }

    func save() {
        try? FileManager.default.createDirectory(at: Config.configDir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Config.configPath, options: .atomic)
    }
}
