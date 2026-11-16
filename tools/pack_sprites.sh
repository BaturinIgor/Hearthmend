#!/bin/sh
# Вырезает спрайты из пака и кладёт их в репозиторий в зашифрованном виде.
#   ASSETS_KEY=... sh tools/pack_sprites.sh <папка Cute_Fantasy>
# Ключ тот же, что в секрете ASSETS_KEY репозитория Hearthmend на GitHub.
set -e
SRC="$1"
[ -n "$SRC" ] || { echo "usage: ASSETS_KEY=... $0 <папка Cute_Fantasy>"; exit 1; }
[ -n "$ASSETS_KEY" ] || { echo "ASSETS_KEY is not set"; exit 1; }
TMP="$(mktemp -d)"
python3 "$(dirname "$0")/sprites.py" "$SRC" "$TMP/Sprites" --sheet "$TMP/sheet.png"
tar -C "$TMP" -czf "$TMP/sprites.tar.gz" Sprites
mkdir -p Art
openssl enc -aes-256-cbc -md sha256 -salt -in "$TMP/sprites.tar.gz" -out Art/sprites.enc -pass env:ASSETS_KEY
rm -rf "$TMP"
ls -lh Art/sprites.enc
