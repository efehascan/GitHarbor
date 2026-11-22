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

## Fark (DiffParser)
- Girdi `git diff --no-color --no-ext-diff [--cached] -- <yol>` metni; satırlara `\n` ile bölünür (sondaki boş satır yok sayılır).
- Her `diff --git a/X b/Y` yeni bir `FileDiff` başlatır. İlk `@@`'ye kadar olan satırlar `header`'a aynen eklenir (`diff --git` satırı dahil).
- Yollar: `--- a/X` → oldPath X, `--- /dev/null` → oldPath nil; `+++ b/Y` → newPath Y, `+++ /dev/null` → newPath nil. `---`/`+++` satırı yoksa (ikili dosya, salt yeniden adlandırma) yollar `rename from`/`rename to` satırından, o da yoksa `diff --git a/X b/Y` satırından (" b/" son geçtiği yerden bölünür).
- `new file mode` → isNewFile, `deleted file mode` → isDeletedFile, `Binary files ` ile başlayan satır → isBinary.
- `@@ -a[,b] +c[,d] @@[ bölüm]`: virgülsüz sayı 1 demektir. section = ikinci `@@`'den sonraki metin, baştaki tek boşluk atılmış.
- Parça satırları (parça başladıktan sonra, yeni `diff --git` ya da `@@`'ye kadar): ilk karakter `' '` context, `'+'` added, `'-'` removed, `'\\'` noNewline; metin = ilk karakterden sonrası. Numara: context ikisini de alır ve ikisini artırır; removed eskiyi; added yeniyi; noNewline hiçbirini. Boş satır (karakter yok) context sayılır, metin "".
- Parçanın içindeyken `---`/`+++` ile başlayan satır başlık DEĞİL, içerik satırıdır.

## Geçmiş ve dallar (LogParser)
- `parseLog`: metin 0x1e ile kayıtlara bölünür; her kayıt baştaki/sondaki boşluk ve satır sonlarından kırpılır, boşsa atlanır. 0x1f ile tam 7 alana bölünmeli (`omittingEmptySubsequences: false`), değilse atlanır. Ebeveynler boşlukla ayrılır (boşsa []). Zaman Int'e çevrilemezse kayıt atlanır. Referanslar ", " ile bölünür (boşsa []).
- `parseBranches`: satır satır; boş satır atlanır; 0x1f ile tam 6 alan. `refs/heads/` öneki → yerel (ad öneksiz), `refs/remotes/` → uzak (ad öneksiz, ör. "origin/main"); başka ref (etiket) atlanır; uzak adı "/HEAD" ile bitiyorsa atlanır. upstream boşsa nil. Takip: "gone" → upstreamGone; değilse ", " ile bölünür, "ahead N" / "behind N". HEAD alanı "*" ise isHead. Zaman çevrilemezse satır atlanır. Sıra korunur.

## GitHub (GitHubParsing)
- `repoID(fromRemote:)`: önce baştaki/sondaki boşluk kırpılır. Biçimler: `https://[kullanıcı@]github.com/O/R[.git][/]`, `ssh://git@github.com/O/R[.git]`, `git@github.com:O/R[.git]`. Sunucu tam olarak `github.com` olmalı (büyük/küçük harf duyarsız). Yol tam iki parça olmalı (sondaki `/` önemsiz); R sonundaki `.git` atılır (yalnızca sondaki). Aksi nil.
- `summarize`: boş → `.none`. Başarısız sayılanlar: `completed` ve conclusion ∈ {failure, timed_out, cancelled, action_required, startup_failure, stale}. Herhangi biri başarısızsa `.failure(failed:, total:)`. Değilse tamamlanmamış (status != "completed") varsa `.pending(done: tamamlanan, total:)`. Değilse `.success(total:)` (success, neutral, skipped başarılı sayılır).
- `issueNumbers(in:)`: `#` ardından en az bir rakam; `#`'tan önceki karakter harf ya da rakamsa sayılmaz; rakamlardan hemen sonra harf geliyorsa (ör. `#0x`) sayılmaz. Sıra korunur, tekrarlar atılır.
