# Harita: Git Harbor Desktop

Mac için git istemcisi (macOS 26+, SwiftUI + AppKit). Git işlemleri sistemdeki `/usr/bin/git` ile yapılır; dış paket yok.

## Katmanlar
- `Sources/HarborCore/` arayüzsüz, test edilir:
  - `Models.swift`: `RepoEntry`, `RepoFolder`, `Workspace`, `ChangeKind`, `FileChange`, `RepoStatus`. **Değiştirme.**
  - `Git.swift`: `Git.run/runSync` (kabuk yok, `GIT_TERMINAL_PROMPT=0`, `LC_ALL=C`), `Git.status`.
  - `StatusParser.swift`: porcelain v2 `-z` çıktısı → `RepoStatus`.
  - `WorkspaceEditing.swift`: klasör/depo düzenlemeleri (saf `mutating` fonksiyonlar).
- `Sources/GitHarbor/`: pencere ve görünümler.

## Kalıp
- Git çıktısı her zaman makine biçiminde istenir (`--porcelain=v2 -z`, `--format` + `%x00`); ayrıştırıcı saf fonksiyondur, `Data` alır.
- NUL (`\0`) ile ayrılmış kayıtlar: `split(separator: 0, omittingEmptySubsequences: true)` ile bölünür, her biri `String(decoding:as: UTF8.self)`.
- Bilinmeyen ya da eksik alanlı kayıt atlanır; çökme, `try!`, zorla unwrap yok.
- Yoklama (polling) yok: değişiklik FSEvents ile izlenir.

## porcelain v2 özeti (StatusParser)
- Başlıklar: `# branch.oid <sha|(initial)>`, `# branch.head <ad|(detached)>`, `# branch.upstream <ad>`, `# branch.ab +A -B`.
- `1 XY sub mH mI mW hH hI <yol>`: sıradan değişiklik (yol 9. alandan sonrası; boşluk içerebilir, bu yüzden 8 boşluktan sonra kalan her şey).
- `2 XY sub mH mI mW hH hI Xscore <yol>` ve ardından gelen AYRI kayıt `<eski yol>`: yeniden adlandırma/kopya (yol 9 boşluktan sonrası).
- `u XY sub m1 m2 m3 mW h1 h2 h3 <yol>`: çakışma (yol 10 boşluktan sonrası).
- `? <yol>` izlenmeyen, `! <yol>` yok sayılan (atlanır).
- XY: X sahnedeki (index), Y çalışma klasöründeki durum; `.` değişiklik yok. Harfler: M modified, A added, D deleted, R renamed, C copied, T typeChanged. X ve Y ayrı `FileChange` kayıtlarıdır (önce X/staged, sonra Y).

## Çalışma alanı kuralı
Her depo ya tam bir klasörde ya da `ungrouped` içindedir. Depo adı verilmezse yolun son bileşeni. Yol karşılaştırması `URL(fileURLWithPath:).standardizedFileURL.path` ile (sondaki `/` önemsiz). Ad boşluklardan kırpılır, boş ad yok sayılır. Bilinmeyen kimlikler sessizce yok sayılır.
