#!/bin/sh
# Görsel test: deneme ortamını kurar, uygulamayı her senaryo için açar, pencerenin gerçek görüntüsünü
# (screencapture) alır. Kullanım: scripts/visual-test.sh <çıktı-klasörü>
# Gerekenler: Ekran Kaydı izni olan bir terminal; scripts/winid (pencere kimliği yardımcı aracı, ilk çalıştırmada derlenir).
set -e
cd "$(dirname "$0")/.."
OUT="$1"; [ -n "$OUT" ] || { echo "çıktı klasörü ver"; exit 1; }
mkdir -p "$OUT"; FX="$OUT/fixtures"
[ -x .build/winid ] || swiftc -O scripts/winid.swift -o .build/winid
swift build -q
shot() { # ad bekleme(sn) argümanlar…  — pencere başlığına göre seçer (ayar penceresi için "settings")
  name=$1; wait=$2; shift 2
  scripts/make-fixtures.sh "$FX" >/dev/null
  .build/debug/GitHarbor --workspace "$FX/workspace.json" --size 1320x820 "$@" >"$OUT/$name.log" 2>&1 &
  pid=$!
  # Önce ana pencere gelsin (ilk açılış derlemeden sonra yavaş olabilir), sonra içerik için bekle.
  n=0; until [ -n "$(.build/winid $pid 2>/dev/null | awk '$5=="1"')" ] || [ $n -ge 60 ]; do sleep 0.5; n=$((n+1)); done
  sleep "$wait"
  if ! kill -0 $pid 2>/dev/null; then echo "$name: ÇÖKTÜ"; tail -3 "$OUT/$name.log"; return; fi
  if echo "$@" | grep -q -- "--settings"; then
    wid=$(.build/winid $pid | awk '$5=="1" && $6!="Git" && $2>300 {print $1; exit}')
  else
    wid=$(.build/winid $pid | awk '$5=="1" && $2>800 {print $1; exit}')
  fi
  if [ -n "$wid" ]; then screencapture -x -o -l "$wid" "$OUT/$name.png" && echo "$name: ok"; else echo "$name: pencere yok"; .build/winid $pid | sed 's/^/    /'; fi
  kill $pid 2>/dev/null; wait $pid 2>/dev/null || true
}
shot changes-dark 5 --select Liman --file app.swift --appearance dark
shot changes-light 5 --select Liman --file app.swift --appearance light
# Değer almayan bayraklar (--history, --pulls, --palette, --settings) en sonda olmalı: AppKit ardından gelen
# değeri açılacak dosya sanar ve ana pencereyi açmaz.
shot history-light 5 --select Liman --appearance light --history
shot history-dark 5 --select Liman --appearance dark --history
shot pulls-dark 5 --select Liman --appearance dark --pulls
shot palette-dark 5 --select Liman --appearance dark --palette
shot attention-light 8 --select Kirli --appearance light
shot conflict-dark 5 --select Catisma --appearance dark
shot publish-light 5 --select Yeni-dal --appearance light
shot settings-light 5 --appearance light --settings-tab genel --settings
shot settings-notify-dark 5 --appearance dark --settings-tab bildirim --settings
shot settings-github-light 5 --appearance light --settings-tab github --settings
shot settings-sync-dark 5 --appearance dark --settings-tab senkron --settings
shot worktrees-dark 6 --select Liman --appearance dark --worktrees
shot empty-dark 4 --appearance dark
shot clone-dark 6 --appearance dark --sheet-clone
shot create-light 5 --appearance light --sheet-create
