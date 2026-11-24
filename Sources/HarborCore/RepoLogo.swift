import Foundation

/// Depo logosu: depodaki uygulama ikonu, logo ya da favicon. Yalnızca dosya sistemine bakar (ağ yok).
public enum RepoLogo {
    /// Aranmayan klasörler (büyük ya da üretilmiş).
    static let skipped: Set<String> = [
        ".git", "node_modules", ".build", "build", "dist", ".next", "Pods", "DerivedData", ".expo",
        "vendor", "target", ".venv", "venv", "__pycache__", ".swiftpm", "Carthage", "out", "coverage",
    ]

    static let extensions: Set<String> = ["png", "jpg", "jpeg", "svg", "ico", "icns", "webp"]

    /// Dosya adına göre öncelik (küçük olan daha iyi); logo değilse nil.
    static func rank(_ fileName: String) -> Int? {
        let lower = fileName.lowercased()
        let ext = (lower as NSString).pathExtension
        guard extensions.contains(ext) else { return nil }
        let base = (lower as NSString).deletingPathExtension
        switch base {
        case "icon", "appicon", "app-icon", "app_icon": return ext == "icns" ? 1 : 0
        case "logo", "logo-icon", "logo_icon", "logomark": return 2
        case "apple-touch-icon", "apple-icon": return 3
        case "ic_launcher": return 4
        case "favicon": return ext == "ico" ? 6 : 5
        default: return nil
        }
    }

    /// En iyi aday dosyanın tam yolu. `maxDepth` klasör derinliği (kök = 0).
    public static func find(in repo: String, maxDepth: Int = 5) -> String? {
        let fm = FileManager.default
        var best: (rank: Int, depth: Int, path: String)?
        func consider(_ rank: Int, _ depth: Int, _ path: String) {
            if let b = best, (b.rank, b.depth) <= (rank, depth) { return }
            best = (rank, depth, path)
        }
        var queue: [(String, Int)] = [(repo, 0)]
        var visited = 0
        while !queue.isEmpty, visited < 4000 {
            let (dir, depth) = queue.removeFirst()
            visited += 1
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in names.sorted() {
                let path = dir + "/" + name
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir) else { continue }
                if isDir.boolValue {
                    if name == "AppIcon.appiconset", let png = largestPNG(in: path) {
                        consider(0, depth, png)
                    } else if depth < maxDepth, !skipped.contains(name), !name.hasPrefix(".") {
                        queue.append((path, depth + 1))
                    }
                } else if let r = rank(name) {
                    consider(r, depth, path)
                }
            }
        }
        return best?.path
    }

    /// Bir `.appiconset` içindeki en büyük PNG.
    static func largestPNG(in dir: String) -> String? {
        let fm = FileManager.default
        func size(_ p: String) -> Int { ((try? fm.attributesOfItem(atPath: p))?[.size] as? Int) ?? 0 }
        let pngs = ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.lowercased().hasSuffix(".png") }
        return pngs.max { size(dir + "/" + $0) < size(dir + "/" + $1) }.map { dir + "/" + $0 }
    }

    /// GitHub avatarı (depoda logo yoksa): sahibin profil resmi.
    public static func avatarURL(owner: String, size: Int = 128) -> URL? {
        URL(string: "https://github.com/\(owner).png?size=\(size)")
    }
}
