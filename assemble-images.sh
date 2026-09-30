#!/usr/bin/env bash
set -Eeuo pipefail

base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$base"
[[ ! -e images.tar.zst ]] || { echo 'images.tar.zst already exists; refusing to overwrite it.' >&2; exit 1; }
[[ -s parts.sha256 ]] || { echo 'parts.sha256 is missing.' >&2; exit 1; }
sha256sum -c parts.sha256
mapfile -t parts < <(awk '{print $2}' parts.sha256)
[[ ${#parts[@]} -ge 2 ]] || { echo 'Expected multiple archive parts.' >&2; exit 1; }
cat -- "${parts[@]}" >images.tar.zst
sha256sum -c images.sha256
echo 'Verified complete images.tar.zst'
