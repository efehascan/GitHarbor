---
id: porcelain-header-split
lang: swift
signatures:
  - testbranchheaders
keywords: [porcelain, branch.oid, branch.head, başlık]
verified: true
source: gh-01-status (Qwen iki kez 3 tur takıldı; Claude tek satırla düzeltti)
---
## Belirti
`# branch.head main` satırından dal adı nil çıkıyor; testBranchHeaders, testDetachedAndInitial kırmızı.

## Kök sebep
Satır İLK boşluktan bölündü: "#" ile "branch.head main" ayrıldı; anahtar hep boş kaldı.

## Çözüm
Önce sabit öneki at, sonra böl:
```swift
guard record.hasPrefix("# ") else { return }
let parts = record.dropFirst(2).split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
let key = String(parts[0]); let value = String(parts[1])
```
Genel kural: "önek + boşluk + anahtar + boşluk + değer" biçiminde önce öneki düşür.
