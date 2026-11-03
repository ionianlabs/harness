#!/bin/bash
# Ionian Harness config reader. Flat TOML only: [section] headers and key = "value" lines.
# Usage: config.sh <repo-dir> <section.key> [default]
# Lookup order: <repo>/harness.toml, ~/.config/harness/<repo-name>.toml, then default.
repo="$1"; key="$2"; default="$3"
name="$(basename "$repo")"
for f in "$repo/harness.toml" "$HOME/.config/harness/$name.toml"; do
  [ -f "$f" ] || continue
  val="$(awk -v want="$key" '
    /^[[:space:]]*\[/ { gsub(/[][[:space:]]/, ""); section=$0; next }
    /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/ {
      k=$0; sub(/[[:space:]]*=.*/, "", k); gsub(/[[:space:]]/, "", k)
      v=$0; sub(/^[^=]*=[[:space:]]*/, "", v); sub(/[[:space:]]+#.*$/, "", v)
      gsub(/^"|"$/, "", v)
      if (section "." k == want) { print v; found=1; exit }
    }' "$f")"
  if [ -n "$val" ]; then echo "$val"; exit 0; fi
done
[ -n "$default" ] && echo "$default"
exit 0
