import Foundation

// MARK: - iTunes Search (verification, artwork, 30s preview)

struct Resolved {
    var title: String
    var artist: String
    var artwork: String?
    var preview: String?
    var store: String?
    var durationMs: Int?
}

enum ITunes {
    static func norm(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .split(separator: " ").joined(separator: " ")
    }

    static func resolve(title: String, artist: String) async -> Resolved? {
        for country in ["", "IN"] {
            var comps = URLComponents(string: "https://itunes.apple.com/search")!
            comps.queryItems = [.init(name: "term", value: "\(title) \(artist)"), .init(name: "entity", value: "song"),
                                .init(name: "limit", value: "10")]
            if !country.isEmpty { comps.queryItems?.append(.init(name: "country", value: country)) }
            guard let (data, _) = try? await URLSession.shared.data(from: comps.url!),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else { continue }
            let wantTitle = norm(title)
            let artistWords = Set(norm(artist).split(separator: " ").map(String.init).filter { $0.count > 2 })
            for r in results {
                guard let t = r["trackName"] as? String, let a = r["artistName"] as? String else { continue }
                let nt = norm(t)
                let na = Set(norm(a).split(separator: " ").map(String.init))
                let titleOK = nt == wantTitle || nt.hasPrefix(wantTitle) || wantTitle.hasPrefix(nt) || nt.contains(wantTitle)
                let artistOK = artistWords.isEmpty || !artistWords.isDisjoint(with: na)
                if titleOK && artistOK {
                    return Resolved(title: t, artist: a,
                                    artwork: (r["artworkUrl100"] as? String)?.replacingOccurrences(of: "100x100bb", with: "600x600bb"),
                                    preview: r["previewUrl"] as? String, store: r["trackViewUrl"] as? String,
                                    durationMs: r["trackTimeMillis"] as? Int)
                }
            }
        }
        return nil
    }
}

// MARK: - YouTube lookup (video id for the in-app player)

enum YouTube {
    struct Candidate { let id: String; let title: String; let seconds: Int }

    static func search(title: String, artist: String, durationMs: Int?) async -> [String] {
        var comps = URLComponents(string: "https://www.youtube.com/results")!
        comps.queryItems = [.init(name: "search_query", value: "\(title) \(artist) official audio"), .init(name: "hl", value: "en")]
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 12
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.setValue("CONSENT=YES+1; SOCS=CAI", forHTTPHeaderField: "Cookie")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let html = String(data: data, encoding: .utf8) else { return [] }

        let bad = ["cover", "karaoke", "reaction", "remix", "8d", "slowed", "sped up", "instrumental", "tutorial", "lesson", "nightcore",
                   "reverb", "lofi", "lo-fi", "mashup", "piano", "guitar chords", "live", "acoustic version", "1 hour", "10 hours"]
        let wantTitle = title.lowercased()
        var out: [(Candidate, Double)] = []
        var seen = Set<String>()
        let marker = "\"videoRenderer\":{\"videoId\":\""
        var search = html.startIndex..<html.endIndex
        while let r = html.range(of: marker, range: search) {
            let idStart = r.upperBound
            guard let idEnd = html.index(idStart, offsetBy: 11, limitedBy: html.endIndex) else { break }
            let id = String(html[idStart..<idEnd])
            search = idEnd..<html.endIndex
            guard seen.insert(id).inserted, out.count < 12 else { continue }
            let chunk = String(html[idEnd..<(html.index(idEnd, offsetBy: 1800, limitedBy: html.endIndex) ?? html.endIndex)])
            let t = firstMatch(chunk, "\"title\":\\{\"runs\":\\[\\{\"text\":\"(.*?)\"") ?? ""
            let len = firstMatch(chunk, "\"lengthText\":\\{.*?\"simpleText\":\"([0-9:]+)\"") ?? ""
            let secs = len.split(separator: ":").compactMap { Int($0) }.reduce(0) { $0 * 60 + $1 }
            guard secs > 60, secs < 600 else { continue }
            let lower = t.lowercased()
            var score = 0.0
            for w in bad where lower.contains(w) && !wantTitle.contains(w) { score -= 6 }
            if lower.contains(wantTitle) { score += 4 }
            if lower.contains("official") { score += 2 }
            if lower.contains(artist.lowercased().split(separator: " ").first.map(String.init) ?? "~") { score += 2 }
            if let ms = durationMs {
                let diff = abs(secs - ms / 1000)
                score += diff <= 8 ? 5 : (diff <= 25 ? 2 : (diff > 60 ? -4 : 0))
            }
            score -= Double(out.count) * 0.3 // slight rank prior
            out.append((Candidate(id: id, title: t, seconds: secs), score))
        }
        return out.sorted { $0.1 > $1.1 }.prefix(4).map { $0.0.id }
    }

    private static func firstMatch(_ s: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }
}
