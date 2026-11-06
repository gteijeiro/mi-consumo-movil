import Foundation

enum SessionState: String, Codable {
    case demo
    case active
    case needsLogin
    case unavailable
}

struct DataPack: Codable, Identifiable {
    var name: String
    var remainingGB: Double
    var totalGB: Double
    var remainingDisplay: String
    var expiresAt: Date

    var id: String { "\(name)-\(expiresAt.timeIntervalSince1970)" }
}

enum PackDateFormat {
    static func long(_ date: Date) -> String { format(date, as: "dd/MM/yyyy 'a las' HH:mm") }
    static func short(_ date: Date) -> String { format(date, as: "dd/MM HH:mm") }
    static func day(_ date: Date) -> String { format(date, as: "dd/MM") }

    private static func format(_ date: Date, as pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_AR")
        formatter.timeZone = TimeZone(identifier: "America/Argentina/Cordoba")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

struct UsageSnapshot: Codable {
    var usedGB: Double?
    var totalGB: Double?
    var remainingDisplay: String?
    var periodDescription: String?
    var packs: [DataPack]
    var updatedAt: Date?
    var state: SessionState
    var message: String

    static let initial = UsageSnapshot(
        usedGB: nil,
        totalGB: nil,
        remainingDisplay: nil,
        periodDescription: nil,
        packs: [],
        updatedAt: nil,
        state: .unavailable,
        message: "Abrí la app para actualizar"
    )

    static let signedOut = UsageSnapshot(
        usedGB: nil, totalGB: nil, remainingDisplay: nil,
        periodDescription: nil, packs: [], updatedAt: nil,
        state: .needsLogin, message: "Sesión cerrada. Iniciá sesión para ver tus gigas."
    )
}

enum SharedSettings {
    static let appGroup = "6WV47G2CGZ.PersonalDataWidget"
    static let widgetKind = "PersonalUsageWidget"
    static let loginURL = URL(string: "personaldatawidget://login")!
    static let appURL = URL(string: "personaldatawidget://open")!
}

struct SnapshotStore {
    private let key = "usageSnapshot.v2"

    func load() -> UsageSnapshot {
        guard let defaults = UserDefaults(suiteName: SharedSettings.appGroup),
              let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data)
        else { return .initial }
        return snapshot
    }

    @discardableResult
    func save(_ snapshot: UsageSnapshot) -> Bool {
        guard let defaults = UserDefaults(suiteName: SharedSettings.appGroup),
              let data = try? JSONEncoder().encode(snapshot)
        else { return false }
        defaults.set(data, forKey: key)
        return true
    }
}
