import Foundation

/// Compares language tags whether they come as ISO 639-1 (`it`), 639-2/B (`ger`),
/// 639-2/T (`deu`) or with a region (`pt-BR`).
enum Languages {
    private static let pairs: [(String, [String])] = [
        ("it", ["ita"]), ("en", ["eng"]), ("de", ["ger", "deu"]), ("fr", ["fre", "fra"]),
        ("es", ["spa"]), ("pt", ["por"]), ("nl", ["dut", "nld"]), ("ru", ["rus"]),
        ("ja", ["jpn"]), ("ko", ["kor"]), ("zh", ["chi", "zho"]), ("ar", ["ara"]),
        ("pl", ["pol"]), ("tr", ["tur"]), ("sv", ["swe"]), ("da", ["dan"]),
        ("no", ["nor"]), ("nb", ["nob"]), ("fi", ["fin"]), ("cs", ["cze", "ces"]),
        ("el", ["gre", "ell"]), ("hu", ["hun"]), ("ro", ["rum", "ron"]), ("uk", ["ukr"]),
        ("he", ["heb"]), ("hi", ["hin"]), ("th", ["tha"]), ("vi", ["vie"]),
        ("id", ["ind"]), ("hr", ["hrv"]), ("sk", ["slo", "slk"]), ("bg", ["bul"]),
        ("sr", ["srp"]), ("sl", ["slv"]), ("ca", ["cat"]), ("fa", ["per", "fas"]),
    ]

    private static let canonical: [String: String] = {
        var map: [String: String] = [:]
        for (short, long) in pairs {
            map[short] = short
            for code in long { map[code] = short }
        }
        return map
    }()

    static func normalized(_ tag: String?) -> String? {
        guard let tag, !tag.isEmpty else { return nil }
        let base = tag.lowercased().split(separator: "-").first.map(String.init) ?? tag.lowercased()
        return canonical[base] ?? base
    }

    static func same(_ a: String?, _ b: String?) -> Bool {
        guard let a = normalized(a), let b = normalized(b) else { return false }
        return a == b
    }
}
