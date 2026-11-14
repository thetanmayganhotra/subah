import Foundation
import Security

struct Place: Codable, Equatable {
    var query = ""
    var name = ""
    var lat = 0.0
    var lon = 0.0
    var tz = TimeZone.current.identifier
    var resolved: Bool { !name.isEmpty }
    var timeZone: TimeZone { TimeZone(identifier: tz) ?? .current }
}

struct AlarmSettings: Codable, Equatable {
    var enabled = false
    var hour = 6
    var minute = 30
    var weekdays: Set<Int> = [1, 2, 3, 4, 5, 6, 7] // Calendar weekday: 1 = Sunday
    var snoozeMinutes = 9
    var volume = 65
    var fullVolume = true          // alarm always takes the Mac to 100%
    var fadeSeconds = 90
    var wakeMac = true
    var userName = ""
    var hasBirth = false
    var birthLocal = Calendar.current.date(from: DateComponents(year: 1995, month: 1, day: 1, hour: 12, minute: 0)) ?? Date(timeIntervalSince1970: 631_152_000)
    var birthPlace = Place()
    var city = Place()
    var autoLocate = true

    init() {}

    /// Tolerant decoding so adding a setting never wipes what someone already configured.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AlarmSettings()
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? d.enabled
        hour = (try? c.decode(Int.self, forKey: .hour)) ?? d.hour
        minute = (try? c.decode(Int.self, forKey: .minute)) ?? d.minute
        weekdays = (try? c.decode(Set<Int>.self, forKey: .weekdays)) ?? d.weekdays
        snoozeMinutes = (try? c.decode(Int.self, forKey: .snoozeMinutes)) ?? d.snoozeMinutes
        volume = (try? c.decode(Int.self, forKey: .volume)) ?? d.volume
        fullVolume = (try? c.decode(Bool.self, forKey: .fullVolume)) ?? d.fullVolume
        fadeSeconds = (try? c.decode(Int.self, forKey: .fadeSeconds)) ?? d.fadeSeconds
        wakeMac = (try? c.decode(Bool.self, forKey: .wakeMac)) ?? d.wakeMac
        userName = (try? c.decode(String.self, forKey: .userName)) ?? d.userName
        hasBirth = (try? c.decode(Bool.self, forKey: .hasBirth)) ?? d.hasBirth
        birthLocal = (try? c.decode(Date.self, forKey: .birthLocal)) ?? d.birthLocal
        birthPlace = (try? c.decode(Place.self, forKey: .birthPlace)) ?? d.birthPlace
        city = (try? c.decode(Place.self, forKey: .city)) ?? d.city
        autoLocate = (try? c.decode(Bool.self, forKey: .autoLocate)) ?? d.autoLocate
    }

    /// Birth moment as a real instant: wall-clock picked in the UI, re-read in the birthplace's time zone.
    var birthInstant: Date? {
        guard hasBirth, birthPlace.resolved else { return nil }
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: birthLocal)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = birthPlace.timeZone
        return cal.date(from: comps)
    }

    static func load() -> AlarmSettings {
        guard let d = UserDefaults.standard.data(forKey: "settings.v1"),
              let s = try? JSONDecoder().decode(AlarmSettings.self, from: d) else { return AlarmSettings() }
        return s
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: "settings.v1") }
    }
}

struct SongPick: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var artist: String
    var why = ""
    var greeting = ""
    var mood = ""
    var source = "playlist"
    var forDate = Date()
    var madeAt = Date()
    var refined = false
    var artworkURL: String?
    var previewURL: String?
    var storeURL: String?
    var durationMs: Int?
}

struct HistoryItem: Codable, Equatable {
    var date: Date
    var title: String
    var artist: String
}

enum Store {
    static func loadPick() -> SongPick? {
        guard let d = UserDefaults.standard.data(forKey: "pick.v1") else { return nil }
        return try? JSONDecoder().decode(SongPick.self, from: d)
    }
    static func save(pick: SongPick?) {
        if let p = pick, let d = try? JSONEncoder().encode(p) { UserDefaults.standard.set(d, forKey: "pick.v1") }
        else { UserDefaults.standard.removeObject(forKey: "pick.v1") }
    }
    static func loadHistory() -> [HistoryItem] {
        guard let d = UserDefaults.standard.data(forKey: "history.v1") else { return [] }
        return (try? JSONDecoder().decode([HistoryItem].self, from: d)) ?? []
    }
    static func save(history: [HistoryItem]) {
        if let d = try? JSONEncoder().encode(history.suffix(400)) { UserDefaults.standard.set(d, forKey: "history.v1") }
    }
}
