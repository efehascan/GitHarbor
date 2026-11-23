---
id: diff-hunk-content-lines
lang: swift
signatures:
  - testemptyandcontentstartingwithdashes
  - testmodifiedfilewithtwohunks
keywords: [diff, hunk, "+++", "@@", parça]
verified: true
source: gh-03-diff (Qwen 3 tur; Claude yeniden yazdı)
---
## Belirti
Parça içindeki `+++ artı` ya da `---- başlık` satırı içerik yerine dosya başlığı sanılıyor; satır sayısı bir fazla çıkıyor; ikili dosyanın yolu nil.

## Kök sebep
`---`/`+++` kontrolü parça durumuna bakmadan yapıldı; metnin sonundaki boş satır içerik sayıldı; ikili dosyada `---`/`+++` olmadığı için yol `diff --git` satırından alınmadı.

## Çözüm
- Durum makinesi kur: `hunk != nil` iken ilk karakter (+, -, \, boşluk) belirleyicidir; `---`/`+++` yalnızca parça başlamadan önce başlıktır.
- `components(separatedBy: "\n")` sonrası son eleman "" ise at.
- Dosyada `---` ya da `rename from` yoksa yolları `diff --git a/X b/Y` satırından al (" b/" SON geçtiği yerden böl).
