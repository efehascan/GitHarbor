# Git Harbor Desktop

Mac için şık, hafif bir git istemcisi (macOS 26+). Swift 6.2 araç zinciri, Swift 5 dil modu, SwiftUI + AppKit. Dış bağımlılık yok; git işlemleri `/usr/bin/git`.

## Komutlar
- Kontrol: `scripts/check.sh` (derleme + bütün testler), tek grup: `scripts/check.sh StatusParserTests`
- Çalıştır: `swift run GitHarbor` · Paket: `scripts/make-app.sh`
- Komut çalıştıramıyorsan kontrolü kullanıcıya bırak; "geçti" deme.

## Klasörler
- `Sources/HarborCore/`: modeller, git çalıştırıcı, ayrıştırıcılar, çalışma alanı. Arayüz yok.
- `Sources/GitHarbor/`: pencere, görünümler, tema.
- `Tests/HarborCoreTests/`: davranışı tanımlayan testler.
- Harita: `docs/map/harbor.md`. Bir dosyaya dokunmadan önce oku.

## Kurallar
- Sadece görevin izin verdiği dosyaya dokun. Görev tek dosyaysa tek dosyaya.
- `Models.swift`'i ve dosyalardaki public imzaları değiştirme; gövdeleri doldur.
- Dış paket ekleme. Sadece Foundation, AppKit, SwiftUI, Observation, CoreServices.
- Uyarı ya da hata susturma yok; `try!` ve zorla unwrap ile kestirme yok.
- Süreç çalıştırırken `Git.run`/`Git.runSync` kullan; kabuk komutu (`sh -c`) kurma.
- Kullanıcının deposunda geri alınamaz işlem (reset --hard, force push, dal silme) onaysız yapılmaz.
- Testleri değiştirme.

## Test
- Önce sadece etkilenen testleri çalıştır (`scripts/check.sh WorkspaceTests`); bütün paket teslimden önce.
- Testte keyfi bekleme yok; gerçek saate, ağa, paylaşılan duruma bağlı test yok; geçici klasör kullan.
- Test başarısızsa kök sebebi düzelt; assertion silme, beklentiyi gevşetme, testi atlama yok.

## Teslim
- Bitince 1–3 cümle: ne yaptın, hangi dosya. Yapmadığın bir şeyi yaptım deme.

## Ajanlar için (Vardiya)
Claude iskeleti, modelleri ve arayüzü yazar; Qwen tek dosyalık görevleri doldurur; `scripts/check.sh` ve Gemma incelemesi doğrular.
