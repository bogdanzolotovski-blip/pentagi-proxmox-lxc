#!/usr/bin/env bash
set -Eeuo pipefail
command -v podman >/dev/null || { echo 'podman is required for local staging verification.' >&2; exit 1; }
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
count=0
while IFS='|' read -r tag expected_digest expected_id archive_id; do
  [[ -z $tag || $tag == \#* ]] && continue
  actual=$(podman image inspect --format '{{.Digest}}|{{.Id}}' "$tag")
  [[ $actual == "$expected_digest|${expected_id#sha256:}" ]] || {
    echo "Digest or image ID mismatch for $tag: $actual" >&2; exit 1;
  }
  echo "Verified $tag"
  ((count+=1))
done < "$base/payload/images.lock"
[[ $count == 6 ]] || { echo "Expected six images, found $count" >&2; exit 1; }
podman run --rm --network none docker.io/vxcontrol/kali-linux:latest \
  /bin/sh -lc 'for tool in nmap sqlmap nikto nuclei ffuf hydra msfconsole gobuster feroxbuster amass; do command -v "$tool" >/dev/null || exit 1; done'
echo 'All six images and ten checked Kali tools are available locally.'
