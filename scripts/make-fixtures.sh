#!/bin/sh
# Deneme ortamı: verilen klasöre uzak (bare) depolar, klonlar ve workspace.json kurar.
# Kullanım: scripts/make-fixtures.sh <klasör>   (klasör silinip yeniden oluşturulur)
set -e
B="$1"; [ -n "$B" ] || { echo "klasör ver"; exit 1; }
rm -rf "$B"; mkdir -p "$B/remotes" "$B/repos"
export GIT_AUTHOR_NAME="Efe Hascan" GIT_AUTHOR_EMAIL="efe@example.com" GIT_COMMITTER_NAME="Efe Hascan" GIT_COMMITTER_EMAIL="efe@example.com"
g() { git -c commit.gpgsign=false -c tag.gpgsign=false -c init.defaultBranch=main "$@"; }

# Depo logoları bir kez çizilir ve saklanır (.build/fixture-icons); her depo kendi assets/icon.png'siyle commit'lenir.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; ICONS="$ROOT/.build/fixture-icons"; mkdir -p "$ICONS"
for n in liman geride kirli catisma yeni-dal; do
  [ -s "$ICONS/$n.png" ] || swift "$ROOT/scripts/make-icon.swift" "$n" "$ICONS/$n.png" >/dev/null
  sips -Z 256 "$ICONS/$n.png" >/dev/null
done

mk() { # ad → bare uzak + klon + 3 commit
  g init -q --bare "$B/remotes/$1.git"
  g clone -q "$B/remotes/$1.git" "$B/repos/$1" 2>/dev/null
  cd "$B/repos/$1"
  printf 'import Foundation\n\nlet a = 1\nlet b = 2\nlet c = 3\n' > app.swift
  printf '# %s\n\nDeneme deposu.\n' "$1" > README.md
  mkdir -p assets; cp "$ICONS/$(echo "$1" | tr '[:upper:]' '[:lower:]').png" assets/icon.png
  g add -A && g commit -q -m "İlk commit"
  printf 'let x = 10\n' > util.swift && g add -A && g commit -q -m "Yardımcı dosya eklendi (#12)"
  printf 'import Foundation\n\nlet a = 1\nlet b = 20\nlet c = 3\nlet d = 4\n' > app.swift && g add -A && g commit -q -m "feat: d değişkeni"
  g push -q -u origin main
}
other() { # uzakta başkasının commit'leri
  rm -rf "$B/tmp-$1"; g clone -q "$B/remotes/$1.git" "$B/tmp-$1"; cd "$B/tmp-$1"
  i=1; while [ $i -le "$2" ]; do printf 'satır %s\n' "$i" >> remote.txt; g add -A; g commit -q -m "Uzak değişiklik $i"; i=$((i+1)); done
  g push -q; cd "$B"; rm -rf "$B/tmp-$1"
}

# 1) Liman: zengin depo — değişiklikler, stash, dallar, etiket
mk Liman
cd "$B/repos/Liman"
g tag v1.0
g switch -q -c ozellik/arama; printf 'func ara() {}\n' > search.swift; g add -A; g commit -q -m "Arama iskeleti"; g push -q -u origin ozellik/arama
g switch -q main
printf 'saklanan\n' > notlar.txt; g add notlar.txt; g stash push -q -m "yarım kalan notlar"
printf 'import Foundation\n\nlet a = 1\nlet b = 25\nlet c = 3\nlet d = 4\nlet e = 5\n' > app.swift
printf 'let x = 11\n' > util.swift; g add util.swift
printf 'yeni dosya\n' > yeni.txt
g mv README.md BENIOKU.md
g worktree add -q "$B/repos/Liman-arama" ozellik/arama   # çalışma ağacı paneli için

# 2) Geride: temiz ve 2 commit geride → otomatik ileri sarılmalı
mk Geride; other Geride 2; cd "$B/repos/Geride"; g fetch -q

# 3) Kirli: değişiklik var ve 1 commit geride → uyarı
mk Kirli; other Kirli 1; cd "$B/repos/Kirli"; printf 'yerel\n' >> README.md

# 4) Catisma: birleştirme çakışmada
mk Catisma
rm -rf "$B/tmp-c"; g clone -q "$B/remotes/Catisma.git" "$B/tmp-c"; cd "$B/tmp-c"
printf 'import Foundation\n\nlet a = 100\n' > app.swift; g commit -qam "Onların değişikliği"; g push -q; cd "$B"; rm -rf "$B/tmp-c"
cd "$B/repos/Catisma"; printf 'import Foundation\n\nlet a = 999\n' > app.swift; g commit -qam "Benim değişikliğim"
g pull -q --no-rebase --no-edit 2>/dev/null || true

# 5) Yeni-dal: yayınlanmamış dal, 1 yerel commit
mk Yeni-dal; cd "$B/repos/Yeni-dal"; g switch -q -c deneme/yayin; printf 'x\n' > x.txt; g add -A; g commit -q -m "Yayınlanacak iş"

python3 - "$B" <<'P'
import json, sys, uuid
b = sys.argv[1]
def r(n): return {"id": str(uuid.uuid4()).upper(), "path": f"{b}/repos/{n}", "name": n}
repos = {n: r(n) for n in ["Liman", "Geride", "Kirli", "Catisma", "Yeni-dal"]}
fid = lambda: str(uuid.uuid4()).upper()
ws = {"repos": list(repos.values()),
      "folders": [{"id": fid(), "name": "Ürün", "repoIDs": [repos["Liman"]["id"], repos["Geride"]["id"]]},
                  {"id": fid(), "name": "Sorunlu", "repoIDs": [repos["Kirli"]["id"], repos["Catisma"]["id"]]}],
      "ungrouped": [repos["Yeni-dal"]["id"]]}
json.dump(ws, open(f"{b}/workspace.json", "w"), indent=1)
P
echo "$B"
