import Foundation

// Sidereal (Lahiri) astronomy: low-precision but plenty for nakshatra / tithi / dasha.
// Sun & Moon from truncated Meeus series (~0.02 deg), planets from JPL Keplerian elements.

struct Placement: Identifiable {
    var id: String { name }
    let name: String
    let lon: Double // sidereal, 0..360
    var sign: Int { Int(lon / 30) % 12 }
    var degInSign: Double { lon.truncatingRemainder(dividingBy: 30) }
    var nakIndex: Int { Int(lon / (360.0 / 27)) % 27 }
    var pada: Int { Int(lon.truncatingRemainder(dividingBy: 360.0 / 27) / (360.0 / 108)) + 1 }
}

struct NatalInfo {
    var lagnaSign: Int
    var placements: [Placement]
    var moon: Placement
    var maha: String
    var antar: String
    var chandrabala: Int          // transit Moon house counted from natal Moon
    var tara: Int                 // 1...9
    var jupiterFromMoon: Int
    var saturnFromMoon: Int
    var sadeSati: Bool
}

struct SkyReport {
    var date: Date
    var tz: TimeZone
    var tithi: Int                // 1...30
    var moon: Placement
    var sun: Placement
    var yoga: String
    var vara: String
    var natal: NatalInfo?

    var paksha: String { tithi <= 15 ? "Shukla (waxing)" : "Krishna (waning)" }
    var tithiName: String { Astro.tithiNames[(tithi - 1) % 15] }
    var nakshatra: String { Astro.nakshatras[moon.nakIndex] }
    var moonSignName: String { Astro.signs[moon.sign] }
    var sunSignName: String { Astro.signs[sun.sign] }

    var headline: String {
        "Moon in \(nakshatra) · \(paksha.split(separator: " ")[0]) \(tithiName) · \(vara)"
    }

    var taraName: String? {
        guard let n = natal else { return nil }
        return Astro.taraNames[n.tara - 1]
    }

    var taraGood: Bool {
        guard let n = natal else { return true }
        return ![3, 5, 7].contains(n.tara)
    }

    var chandrabalaGood: Bool {
        guard let n = natal else { return true }
        return [1, 3, 6, 7, 10, 11].contains(n.chandrabala)
    }

    func promptText() -> String {
        var s = """
        Panchang at wake-up time (\(Astro.stamp(date, tz))):
        - Vara (weekday): \(vara)
        - Tithi: \(paksha) \(tithiName) (#\(tithi) of 30)
        - Moon nakshatra: \(nakshatra) pada \(moon.pada), ruled by \(Astro.nakLords[moon.nakIndex % 9]); Moon in \(moonSignName)
        - Sun in \(sunSignName) (sidereal); Yoga: \(yoga)
        """
        if let n = natal {
            let p = n.placements.map { "\($0.name) \(Astro.signs[$0.sign]) \(String(format: "%.0f", $0.degInSign))°" }.joined(separator: ", ")
            s += """


            Person's natal chart (sidereal, Lahiri): Lagna \(Astro.signs[n.lagnaSign]); natal Moon in \(Astro.signs[n.moon.sign]), \(Astro.nakshatras[n.moon.nakIndex]) pada \(n.moon.pada).
            Placements: \(p)
            Vimshottari dasha now: \(n.maha) mahadasha / \(n.antar) antardasha
            Today's transits: Moon is in house \(n.chandrabala) from natal Moon (\(chandrabalaGood ? "supportive" : "tender/tricky")); Tarabala \(n.tara) = \(taraName ?? "") (\(taraGood ? "favourable" : "unfavourable")); Jupiter in house \(n.jupiterFromMoon) and Saturn in house \(n.saturnFromMoon) from natal Moon\(n.sadeSati ? "; Sade Sati is active" : "").
            """
        }
        return s
    }
}

enum Astro {
    static let rad = Double.pi / 180
    static let signs = ["Mesha (Aries)", "Vrishabha (Taurus)", "Mithuna (Gemini)", "Karka (Cancer)", "Simha (Leo)", "Kanya (Virgo)",
                        "Tula (Libra)", "Vrishchika (Scorpio)", "Dhanu (Sagittarius)", "Makara (Capricorn)", "Kumbha (Aquarius)", "Meena (Pisces)"]
    static let nakshatras = ["Ashwini", "Bharani", "Krittika", "Rohini", "Mrigashira", "Ardra", "Punarvasu", "Pushya", "Ashlesha",
                             "Magha", "Purva Phalguni", "Uttara Phalguni", "Hasta", "Chitra", "Swati", "Vishakha", "Anuradha", "Jyeshtha",
                             "Mula", "Purva Ashadha", "Uttara Ashadha", "Shravana", "Dhanishta", "Shatabhisha", "Purva Bhadrapada",
                             "Uttara Bhadrapada", "Revati"]
    static let nakLords = ["Ketu", "Venus", "Sun", "Moon", "Mars", "Rahu", "Jupiter", "Saturn", "Mercury"]
    static let tithiNames = ["Pratipada", "Dwitiya", "Tritiya", "Chaturthi", "Panchami", "Shashthi", "Saptami", "Ashtami", "Navami",
                             "Dashami", "Ekadashi", "Dwadashi", "Trayodashi", "Chaturdashi", "Purnima/Amavasya"]
    static let yogas = ["Vishkambha", "Priti", "Ayushman", "Saubhagya", "Shobhana", "Atiganda", "Sukarma", "Dhriti", "Shula", "Ganda",
                        "Vriddhi", "Dhruva", "Vyaghata", "Harshana", "Vajra", "Siddhi", "Vyatipata", "Variyana", "Parigha", "Shiva",
                        "Siddha", "Sadhya", "Shubha", "Shukla", "Brahma", "Indra", "Vaidhriti"]
    static let taraNames = ["Janma", "Sampat", "Vipat", "Kshema", "Pratyari", "Sadhana", "Naidhana", "Mitra", "Parama Mitra"]
    static let varas = ["Ravivaar (Sun)", "Somvaar (Moon)", "Mangalvaar (Mars)", "Budhvaar (Mercury)", "Guruvaar (Jupiter)",
                        "Shukravaar (Venus)", "Shanivaar (Saturn)"]
    static let dashaYears: [Double] = [7, 20, 6, 10, 7, 18, 16, 19, 17]

    static func stamp(_ d: Date, _ tz: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = tz
        f.dateFormat = "EEE d MMM yyyy, h:mm a"
        return f.string(from: d)
    }

    // MARK: - basics

    static func jd(_ d: Date) -> Double { d.timeIntervalSince1970 / 86400 + 2440587.5 }
    static func norm(_ x: Double) -> Double {
        let r = x.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }
    static let ayanamsaJ2000 = 23.85306
    static func ayanamsa(_ T: Double) -> Double { ayanamsaJ2000 + 1.39697 * T }

    // MARK: - Sun & Moon (tropical, of date)

    static func sunTropical(_ T: Double) -> Double {
        let L0 = 280.46646 + 36000.76983 * T
        let M = (357.52911 + 35999.05029 * T) * rad
        let C = (1.914602 - 0.004817 * T) * sin(M) + 0.019993 * sin(2 * M) + 0.000289 * sin(3 * M)
        return norm(L0 + C - 0.00569)
    }

    // (D, M, M', F, coeff in 1e-6 deg)
    static let moonTerms: [(Int, Int, Int, Int, Double)] = [
        (0, 0, 1, 0, 6288774), (2, 0, -1, 0, 1274027), (2, 0, 0, 0, 658314), (0, 0, 2, 0, 213618), (0, 1, 0, 0, -185116),
        (0, 0, 0, 2, -114332), (2, 0, -2, 0, 58793), (2, -1, -1, 0, 57066), (2, 0, 1, 0, 53322), (2, -1, 0, 0, 45758),
        (0, 1, -1, 0, -40923), (1, 0, 0, 0, -34720), (0, 1, 1, 0, -30383), (2, 0, 0, -2, 15327), (0, 0, 1, 2, -12528),
        (0, 0, 1, -2, 10980), (4, 0, -1, 0, 10675), (0, 0, 3, 0, 10034), (4, 0, -2, 0, 8548), (2, 1, -1, 0, -7888),
        (2, 1, 0, 0, -6766), (1, 0, -1, 0, -5163), (1, 1, 0, 0, 4987), (2, -1, 1, 0, 4036), (2, 0, 2, 0, 3994),
        (4, 0, 0, 0, 3861), (2, 0, -3, 0, 3665)
    ]

    static func moonTropical(_ T: Double) -> Double {
        let Lp = 218.3164477 + 481267.88123421 * T
        let D = (297.8501921 + 445267.1114034 * T) * rad
        let M = (357.5291092 + 35999.0502909 * T) * rad
        let Mp = (134.9633964 + 477198.8675055 * T) * rad
        let F = (93.2720950 + 483202.0175233 * T) * rad
        let E = 1 - 0.002516 * T - 0.0000074 * T * T
        var sum = 0.0
        for (d, m, mp, f, c) in moonTerms {
            let arg = Double(d) * D + Double(m) * M + Double(mp) * Mp + Double(f) * F
            let ef = abs(m) == 1 ? E : (abs(m) == 2 ? E * E : 1)
            sum += c * ef * sin(arg)
        }
        let A1 = (119.75 + 131.849 * T) * rad
        let A2 = (53.09 + 479264.290 * T) * rad
        sum += 3958 * sin(A1) + 1962 * sin(Lp * rad - F) + 318 * sin(A2)
        return norm(Lp + sum / 1_000_000)
    }

    // MARK: - Planets (JPL approximate elements, 1800-2050)

    struct El { let a: (Double, Double), e: (Double, Double), i: (Double, Double), L: (Double, Double), w: (Double, Double), o: (Double, Double) }

    static let elements: [String: El] = [
        "Mercury": El(a: (0.38709927, 0.00000037), e: (0.20563593, 0.00001906), i: (7.00497902, -0.00594749),
                      L: (252.25032350, 149472.67411175), w: (77.45779628, 0.16047689), o: (48.33076593, -0.12534081)),
        "Venus": El(a: (0.72333566, 0.00000390), e: (0.00677672, -0.00004107), i: (3.39467605, -0.00078890),
                    L: (181.97909950, 58517.81538729), w: (131.60246718, 0.00268329), o: (76.67984255, -0.27769418)),
        "Earth": El(a: (1.00000261, 0.00000562), e: (0.01671123, -0.00004392), i: (-0.00001531, -0.01294668),
                    L: (100.46457166, 35999.37244981), w: (102.93768193, 0.32327364), o: (0, 0)),
        "Mars": El(a: (1.52371034, 0.00001847), e: (0.09339410, 0.00007882), i: (1.84969142, -0.00813131),
                   L: (-4.55343205, 19140.30268499), w: (-23.94362959, 0.44441088), o: (49.55953891, -0.29257343)),
        "Jupiter": El(a: (5.20288700, -0.00011607), e: (0.04838624, -0.00013253), i: (1.30439695, -0.00183714),
                      L: (34.39644051, 3034.74612775), w: (14.72847983, 0.21252668), o: (100.47390909, 0.20469106)),
        "Saturn": El(a: (9.53667594, -0.00125060), e: (0.05386179, -0.00050991), i: (2.48599187, 0.00193609),
                     L: (49.95424423, 1222.49362201), w: (92.59887831, -0.41897216), o: (113.66242448, -0.28867794))
    ]

    static func helio(_ el: El, _ T: Double) -> (Double, Double, Double) {
        let a = el.a.0 + el.a.1 * T
        let e = el.e.0 + el.e.1 * T
        let I = (el.i.0 + el.i.1 * T) * rad
        let L = el.L.0 + el.L.1 * T
        let wbar = el.w.0 + el.w.1 * T
        let Om = el.o.0 + el.o.1 * T
        let w = (wbar - Om) * rad
        var M = norm(L - wbar)
        if M > 180 { M -= 360 }
        let Mr = M * rad
        var E = Mr + e * sin(Mr)
        for _ in 0..<12 { E -= (E - e * sin(E) - Mr) / (1 - e * cos(E)) }
        let xp = a * (cos(E) - e)
        let yp = a * (1 - e * e).squareRoot() * sin(E)
        let O = Om * rad
        let x = (cos(w) * cos(O) - sin(w) * sin(O) * cos(I)) * xp + (-sin(w) * cos(O) - cos(w) * sin(O) * cos(I)) * yp
        let y = (cos(w) * sin(O) + sin(w) * cos(O) * cos(I)) * xp + (-sin(w) * sin(O) + cos(w) * cos(O) * cos(I)) * yp
        let z = (sin(w) * sin(I)) * xp + (cos(w) * sin(I)) * yp
        return (x, y, z)
    }

    /// Geocentric ecliptic longitude, J2000 frame
    static func planetJ2000(_ name: String, _ T: Double) -> Double {
        let p = helio(elements[name]!, T)
        let e = helio(elements["Earth"]!, T)
        return norm(atan2(p.1 - e.1, p.0 - e.0) / rad)
    }

    static func rahuTropical(_ T: Double) -> Double {
        norm(125.04452 - 1934.136261 * T)
    }

    // MARK: - Chart

    struct Positions { var sidereal: [String: Double]; var T: Double }

    static func positions(at date: Date) -> Positions {
        let T = (jd(date) - 2451545.0) / 36525.0
        let ay = ayanamsa(T)
        var s: [String: Double] = [:]
        s["Sun"] = norm(sunTropical(T) - ay)
        s["Moon"] = norm(moonTropical(T) - ay)
        for p in ["Mercury", "Venus", "Mars", "Jupiter", "Saturn"] {
            s[p] = norm(planetJ2000(p, T) - ayanamsaJ2000)
        }
        s["Rahu"] = norm(rahuTropical(T) - ay)
        s["Ketu"] = norm(s["Rahu"]! + 180)
        return Positions(sidereal: s, T: T)
    }

    static func ascendant(at date: Date, lat: Double, lon: Double) -> Double {
        let J = jd(date)
        let T = (J - 2451545.0) / 36525.0
        let gmst = 280.46061837 + 360.98564736629 * (J - 2451545.0) + 0.000387933 * T * T
        let theta = norm(gmst + lon) * rad
        let eps = (23.439291 - 0.0130042 * T) * rad
        let y = cos(theta)
        let x = -(sin(theta) * cos(eps) + tan(lat * rad) * sin(eps))
        let tropical = norm(atan2(y, x) / rad)
        return norm(tropical - ayanamsa(T))
    }

    static func dasha(moonLon: Double, birth: Date, at: Date) -> (String, String) {
        let nakLen = 360.0 / 27
        let idx = Int(moonLon / nakLen) % 27
        let frac = (moonLon - Double(idx) * nakLen) / nakLen
        var lord = idx % 9
        let year = 365.25 * 86400
        var start = birth.addingTimeInterval(-dashaYears[lord] * frac * year)
        for _ in 0..<40 {
            let dur = dashaYears[lord] * year
            let end = start.addingTimeInterval(dur)
            if at < end {
                var sub = lord
                var s = start
                for _ in 0..<9 {
                    let d = dur * dashaYears[sub] / 120
                    if at < s.addingTimeInterval(d) { return (nakLords[lord], nakLords[sub]) }
                    s = s.addingTimeInterval(d)
                    sub = (sub + 1) % 9
                }
                return (nakLords[lord], nakLords[lord])
            }
            start = end
            lord = (lord + 1) % 9
        }
        return (nakLords[lord], nakLords[lord])
    }

    // MARK: - Report

    static func report(birth: (instant: Date, place: Place)?, at date: Date, tz: TimeZone) -> SkyReport {
        let now = positions(at: date)
        let sunLon = now.sidereal["Sun"]!
        let moonLon = now.sidereal["Moon"]!
        let tithi = Int(norm(moonLon - sunLon) / 12) + 1
        let yogaIdx = Int(norm(moonLon + sunLon) / (360.0 / 27)) % 27
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let wd = cal.component(.weekday, from: date) - 1

        var report = SkyReport(date: date, tz: tz, tithi: min(max(tithi, 1), 30),
                               moon: Placement(name: "Moon", lon: moonLon), sun: Placement(name: "Sun", lon: sunLon),
                               yoga: yogas[yogaIdx], vara: varas[wd], natal: nil)

        if let b = birth {
            let np = positions(at: b.instant)
            let asc = ascendant(at: b.instant, lat: b.place.lat, lon: b.place.lon)
            let order = ["Sun", "Moon", "Mars", "Mercury", "Jupiter", "Venus", "Saturn", "Rahu", "Ketu"]
            let placements = order.map { Placement(name: $0, lon: np.sidereal[$0]!) }
            let nMoon = Placement(name: "Moon", lon: np.sidereal["Moon"]!)
            let (maha, antar) = dasha(moonLon: nMoon.lon, birth: b.instant, at: date)
            let house: (Double) -> Int = { lon in ((Int(lon / 30) - nMoon.sign + 12) % 12) + 1 }
            let count = ((report.moon.nakIndex - nMoon.nakIndex + 27) % 27) + 1
            let tara = count % 9 == 0 ? 9 : count % 9
            let satHouse = house(now.sidereal["Saturn"]!)
            report.natal = NatalInfo(
                lagnaSign: Int(asc / 30) % 12, placements: placements, moon: nMoon, maha: maha, antar: antar,
                chandrabala: house(moonLon), tara: tara, jupiterFromMoon: house(now.sidereal["Jupiter"]!),
                saturnFromMoon: satHouse, sadeSati: [12, 1, 2].contains(satHouse))
        }
        return report
    }
}
