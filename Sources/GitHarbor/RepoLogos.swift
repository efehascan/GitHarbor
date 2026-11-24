import AppKit
import HarborCore
import SwiftUI

/// Depo logoları: depodaki ikon/logo/favicon, yoksa GitHub sahibinin avatarı.
/// 128 px PNG olarak önbelleğe yazılır; kenar çubuğu ve bildirimler aynı dosyayı kullanır.
@MainActor
@Observable
final class RepoLogos {
    static let shared = RepoLogos()

    private(set) var images: [UUID: NSImage] = [:]
    @ObservationIgnored private var loading: Set<UUID> = []

    static let cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("GitHarbor/logos", isDirectory: true)
    }()

    /// Bildirim eki için önbellekteki PNG (varsa).
    func pngURL(for id: UUID) -> URL? {
        let url = Self.cacheDir.appendingPathComponent("\(id.uuidString).png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Önbellekteki logoyu hemen gösterir, ardından depodan (gerekirse ağdan) tazeler.
    func load(_ repo: RepoEntry) {
        guard !loading.contains(repo.id) else { return }
        loading.insert(repo.id)
        if images[repo.id] == nil, let url = pngURL(for: repo.id), let img = NSImage(contentsOf: url) {
            images[repo.id] = img
        }
        let id = repo.id, path = repo.path
        Task {
            let local = await Task.detached(priority: .utility) { RepoLogo.find(in: path) }.value
            var image = local.flatMap { NSImage(contentsOfFile: $0) }
            if image == nil, let owner = await Git.gitHubRepo(in: path)?.owner, let url = RepoLogo.avatarURL(owner: owner),
               let (data, response) = try? await URLSession.shared.data(from: url),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                image = NSImage(data: data)
            }
            if let image, let png = Self.png(image, side: 128) {
                try? FileManager.default.createDirectory(at: Self.cacheDir, withIntermediateDirectories: true)
                try? png.write(to: Self.cacheDir.appendingPathComponent("\(id.uuidString).png"))
                images[id] = NSImage(data: png)
            }
        }
    }

    /// Kare PNG'ye çizer (svg, ico, icns dahil; bildirim eki PNG ister).
    static func png(_ image: NSImage, side: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let size = image.size
        let scale = min(CGFloat(side) / max(size.width, 1), CGFloat(side) / max(size.height, 1))
        let w = size.width * scale, h = size.height * scale
        image.draw(in: NSRect(x: (CGFloat(side) - w) / 2, y: (CGFloat(side) - h) / 2, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
