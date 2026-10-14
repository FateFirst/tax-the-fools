#!/bin/sh
# Download the two OFL fonts the theme uses, as static TTFs (the 1.12 client
# cannot use variable fonts), plus their licences.
set -e
cd "$(dirname "$0")/.."
OUT=TaxTheFools/media/fonts
mkdir -p "$OUT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

GF=https://raw.githubusercontent.com/google/fonts/main/ofl/rajdhani
curl -fsSL -o "$OUT/Rajdhani-Bold.ttf" "$GF/Rajdhani-Bold.ttf"
curl -fsSL -o "$OUT/Rajdhani-SemiBold.ttf" "$GF/Rajdhani-SemiBold.ttf"
curl -fsSL -o "$OUT/OFL-Rajdhani.txt" "$GF/OFL.txt"

curl -fsSL -o "$TMP/inter.zip" https://github.com/rsms/inter/releases/download/v4.0/Inter-4.0.zip
unzip -q -o "$TMP/inter.zip" -d "$TMP/inter"
cp "$(find "$TMP/inter" -name 'Inter-Regular.ttf' | head -1)" "$OUT/Inter-Regular.ttf"
cp "$(find "$TMP/inter" -name 'Inter-SemiBold.ttf' | head -1)" "$OUT/Inter-SemiBold.ttf"
cp "$(find "$TMP/inter" -name 'LICENSE.txt' | head -1)" "$OUT/OFL-Inter.txt"

for f in "$OUT"/*.ttf; do
  magic=$(xxd -p -l 4 "$f")
  [ "$magic" = "00010000" ] || { echo "$f is not a TrueType font (magic $magic)" >&2; exit 1; }
  echo "$f ok"
done
