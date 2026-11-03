#!/bin/bash
# Ionian Harness config reader. Flat TOML only: [section] headers and key = "value" lines.
# Usage: config.sh <repo-dir> <section.key> [default]
# Lookup order: <repo>/harness.toml, $IONIAN_HOME/harness/<repo-name>.toml (default IONIAN_HOME: ~/Ionian), then default.
# config.sh <repo-dir> --exists: exit 0 if either file exists, 1 if neither.
repo="$1"; key="$2"; default="$3"
name="$(basename "$repo")"
ih="${IONIAN_HOME:-$HOME/Ionian}"
case "$ih" in "~"|"~/"*) ih="$HOME${ih#"~"}" ;; esac  # a literal leading ~ expands against HOME
home_cfg="$ih/harness/$name.toml"
if [ "$key" = "--exists" ]; then
  [ -f "$repo/harness.toml" ] || [ -f "$home_cfg" ]; exit
fi
for f in "$repo/harness.toml" "$home_cfg"; do
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
