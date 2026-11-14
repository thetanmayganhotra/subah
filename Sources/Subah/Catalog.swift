import Foundation

/// One verified song. Every entry in CatalogData was checked against the iTunes catalog (title, artist, length).
struct CatalogSong: Hashable {
    let title: String
    let artist: String
    let tags: Set<String>
    let durationMs: Int
    var key: String { (title + "|" + artist).lowercased() }
}

enum Catalog {
    static let songs: [CatalogSong] = CatalogData.raw.split(separator: "\n").compactMap { line in
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 4 else { return nil }
        return CatalogSong(title: f[0], artist: f[1], tags: Set(f[2].split(separator: " ").map(String.init)), durationMs: Int(f[3]) ?? 0)
    }
}

/// Picks the day's song from the playlist. No AI: the Vedic sky and the weather set what the morning wants,
/// the playlist supplies songs that fit, and a long no-repeat window keeps every day different.
enum Chooser {
    struct Desires {
        var w: [String: Double] = [:]
        mutating func add(_ tags: String, _ v: Double) { for t in tags.split(separator: " ") { w[String(t), default: 0] += v } }
    }

    // Moon-nakshatra character (traditional groupings): what kind of music the day leans towards.
    // 0 laghu (light), 1 ugra (fierce), 2 mishra (mixed), 3 dhruva (fixed), 4 mridu (soft), 5 tikshna (sharp), 6 chara (moving)
    static let nakType = [0, 1, 2, 3, 4, 5, 6, 0, 5, 1, 1, 3, 0, 4, 6, 2, 4, 5, 5, 1, 3, 6, 6, 6, 1, 3, 4]

    static let nakQuality = [
        "swift and fresh, a star of new starts", "deep and steady", "clear and bright", "lush and tender", "curious and gentle",
        "stormy, the kind of star that cleans the air", "the star of returning light", "nourishing, one of the most auspicious stars",
        "quiet and intuitive", "regal and rooted", "playful and restful", "warm and dependable", "light-handed and skilful",
        "shining and well made", "free and breezy", "purposeful and driven", "devoted and friendly", "strong and protective",
        "rooted and deep-clearing", "refreshing, a star of clean energy", "steady, a star of lasting wins",
        "the star of listening", "rhythmic, a star of sound and music", "healing and quiet", "fiery and transforming",
        "calm and deep", "gentle, the star of safe arrivals"
    ]

    static func desires(sky: SkyReport, weather: WeatherSnapshot?, fire: Date) -> Desires {
        var d = Desires()

        if let w = weather {
            let wet = w.precipProb >= 50 || (51...67).contains(w.code) || (80...82).contains(w.code) || w.code >= 95
            if wet { d.add("rain", 3); d.add("cozy", 2); d.add("calm tender", 1) }
            else if w.code <= 1 { d.add("sun", w.temp >= 24 ? 3 : 2); d.add("bright", w.temp >= 24 ? 2 : 1); d.add("groove playful", w.temp >= 24 ? 1 : 0.5); d.add("hopeful", 0.5) }
            else if w.code == 2 { d.add("hopeful", 1.5); d.add("groove bright", 1) }
            else { d.add("calm cozy", 1.5); d.add("tender", 1) }
            if w.temp <= 14 { d.add("cold", 3); d.add("cozy", 2); d.add("calm", 1) }
            if w.temp >= 36 { d.add("calm", 1.5) }
        }

        switch nakType[sky.moon.nakIndex] {
        case 0: d.add("bright", 1.5); d.add("playful", 1); d.add("groove", 0.5)
        case 1: d.add("anthem", 1.2); d.add("groove", 1); d.add("hopeful", 0.5)
        case 2: d.add("groove hopeful", 1)
        case 3: d.add("calm classic", 1.2); d.add("cozy", 0.6)
        case 4: d.add("tender", 1.5); d.add("hopeful", 1); d.add("calm", 0.6)
        case 5: d.add("calm cozy", 1.2); d.add("tender", 0.8)
        default: d.add("groove", 1.2); d.add("bright", 1); d.add("indie", 0.6)
        }

        let t = sky.tithi
        if t <= 14 { d.add("bright hopeful", 1) } else if t <= 29 && t != 30 { d.add("cozy calm", 1) }
        if t == 15 { d.add("hopeful tender", 1); d.add("sacred", 6.5) }
        if t == 30 { d.add("calm", 1.5); d.add("sacred", 6) }
        if t == 11 || t == 26 { d.add("sacred", 6.5); d.add("calm", 1) }

        switch Astro.varas.firstIndex(of: sky.vara) ?? 0 {
        case 0: d.add("bright classic", 1)
        case 1: d.add("calm tender", 1)
        case 2: d.add("groove anthem", 1)
        case 3: d.add("playful indie", 1)
        case 4: d.add("hopeful classic", 1); d.add("sacred", 0.5)
        case 5: d.add("tender desi", 1)
        default: d.add("calm cozy", 1); d.add("jazz", 0.5)
        }

        if sky.natal != nil {
            if sky.chandrabalaGood && sky.taraGood { d.add("bright", 1) } else { d.add("tender", 1.5); d.add("cozy", 1) }
            if sky.natal?.sadeSati == true { d.add("calm cozy", 1) }
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = sky.tz
        let wd = cal.component(.weekday, from: fire)
        if (2...6).contains(wd) { d.add("groove", 0.5) } else { d.add("calm", 0.5) }
        return d
    }

    static func fnv(_ s: String) -> UInt64 {
        var h: UInt64 = 14695981039346656037
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }

    static func choose(sky: SkyReport, weather: WeatherSnapshot?, history: [HistoryItem], fire: Date,
                       exclude: Set<String>, salt: Int) -> CatalogSong {
        let all = Catalog.songs
        let d = desires(sky: sky, weather: weather, fire: fire)

        // No repeats until (almost) the whole playlist has played.
        let window = max(0, min(all.count - 30, 600))
        let recent = history.suffix(window)
        let recentKeys = Set(recent.map { ($0.title + "|" + $0.artist).lowercased() })
        var pool = all.filter { !recentKeys.contains($0.key) && !exclude.contains($0.key) }
        if pool.isEmpty { pool = all.filter { !exclude.contains($0.key) } }

        let last = history.suffix(14).map { $0.artist.lowercased() }
        let lastArtist = history.last?.artist.lowercased()
        let lastTwo = history.suffix(2).compactMap { h in all.first { $0.title.lowercased() == h.title.lowercased() } }
        let genres = ["desi", "classic", "indie", "jazz", "film", "instrumental", "sacred"]
        let day = Int(fire.timeIntervalSince1970 / 86400)

        func score(_ s: CatalogSong) -> Double {
            var v = 0.0
            for t in s.tags { v += d.w[t] ?? 0 }
            if s.tags.contains("sacred") { v -= 4 }
            if s.tags.contains("anthem") { v -= 0.5 }
            let a = s.artist.lowercased()
            if a == lastArtist { v -= 8 } else if last.contains(a) { v -= 4 }
            for g in genres where s.tags.contains(g) && lastTwo.count == 2 && lastTwo.allSatisfy({ $0.tags.contains(g) }) { v -= 1.5 }
            v += Double(fnv("\(day)|\(s.key)|\(salt)") % 1000) / 1000 * 2.5
            return v
        }
        return pool.max { score($0) < score($1) } ?? all[0]
    }

    // MARK: - Words

    static func reason(for s: CatalogSong, sky: SkyReport, weather: WeatherSnapshot?, fire: Date) -> String {
        let seed = Int(fnv("\(Int(fire.timeIntervalSince1970 / 86400))|\(s.key)") % 1000)
        let nak = sky.nakshatra
        let q = nakQuality[sky.moon.nakIndex]
        let vara = sky.vara.components(separatedBy: " ").first ?? sky.vara
        let tithi = "\(sky.paksha.components(separatedBy: " ").first ?? "") \(sky.tithiName)"

        let first: String
        switch seed % 3 {
        case 0: first = "The Moon is in \(nak) today, \(q)."
        case 1: first = "It's \(vara) with the Moon in \(nak), \(q)."
        default: first = "\(tithi) and the Moon in \(nak): \(q)."
        }

        var wx = ""
        if let w = weather {
            wx = "\(Int(w.temp.rounded()))° and \(w.summary) in \(w.placeName)"
        }
        let intent: String
        if s.tags.contains("sacred") { intent = "a still, sacred one for a day like this" }
        else if s.tags.contains("rain") && (weather?.precipProb ?? 0) >= 40 { intent = "one to hear with a warm cup" }
        else if s.tags.contains("sun") || s.tags.contains("bright") { intent = "something bright to walk into the day with" }
        else if s.tags.contains("anthem") { intent = "one with a little chest-out energy" }
        else if s.tags.contains("groove") { intent = "something with a bit of lift in its step" }
        else if s.tags.contains("tender") { intent = "something gentle for the heart" }
        else { intent = "something soft to ease you in" }
        let second = wx.isEmpty ? "So here's \(intent)." : "\(wx.prefix(1).uppercased())\(wx.dropFirst()), so here's \(intent)."

        var third = ""
        if let n = sky.natal {
            let tara = Astro.taraNames[n.tara - 1]
            if n.tara == 1 { third = " It's your birth-star day, so be kind to yourself." }
            else if sky.taraGood && seed % 2 == 0 { third = " Your star is on your side today (\(tara))." }
            else if !sky.taraGood { third = " Tara is \(tara), so a soft landing suits the day." }
        }
        return first + " " + second + third
    }

    static func greeting(name: String, sky: SkyReport, fire: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = sky.tz
        let hr = cal.component(.hour, from: fire)
        let base = timeGreeting(fire, tz: sky.tz)
        let n = name.isEmpty ? "" : ", \(name)"
        let vara = sky.vara.components(separatedBy: " ").first ?? ""
        let seed = Int(fnv("g|\(Int(fire.timeIntervalSince1970 / 86400))") % 100)
        if sky.natal?.tara == 1 { return "Happy birth-star day\(n)." }
        let morning = (4..<12).contains(hr)
        switch seed % 4 {
        case 0: return "\(base)\(n)."
        case 1: return "\(base)\(n). Happy \(vara)."
        case 2: return morning ? "Rise gently\(n)." : "\(base)\(n)."
        default: return morning ? "Subah mubarak\(n)." : "\(base)\(n)."
        }
    }
}
