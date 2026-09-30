#!/usr/bin/env bash
set -Eeuo pipefail

base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
output=${1:?Usage: ./export-images.sh /path/to/images.tar.zst}
[[ ! -e $output ]] || { echo "Output already exists: $output" >&2; exit 1; }
command -v podman >/dev/null || { echo 'podman is required.' >&2; exit 1; }
command -v zstd >/dev/null || { echo 'zstd is required.' >&2; exit 1; }

images=()
while IFS='|' read -r tag digest expected_id archive_id; do
  [[ -z $tag || $tag == \#* ]] && continue
  repository=${tag%:*}
  podman pull "$repository@$digest"
  podman tag "$repository@$digest" "$tag"
  images+=("$tag")
done < "$base/payload/images.lock"
bash "$base/verify-downloaded.sh"
podman save --multi-image-archive --quiet "${images[@]}" | zstd -T4 -3 -o "$output"
zstd -t "$output"
sha256sum "$output" >"$output.sha256"
echo "Ready: $output"
