#!/usr/bin/env bash
set -Eeuo pipefail

base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
lock="$base/images.lock"
[[ -s $lock ]] || { echo "Image lock file missing: $lock" >&2; exit 1; }

if [[ ${VERIFY_ONLY:-0} != 1 && -f $base/images.tar.zst ]]; then
  echo 'Loading bundled images.tar.zst'
  zstd -dc "$base/images.tar.zst" | docker load
elif [[ ${VERIFY_ONLY:-0} != 1 && -f $base/images.tar ]]; then
  echo 'Loading bundled images.tar'
  docker load -i "$base/images.tar"
fi

while IFS='|' read -r tag digest expected_id archive_id; do
  [[ -z $tag || $tag == \#* ]] && continue
  [[ $digest =~ ^sha256:[0-9a-f]{64}$ && $expected_id =~ ^sha256:[0-9a-f]{64}$ && $archive_id =~ ^sha256:[0-9a-f]{64}$ ]] || {
    echo "Invalid image lock entry: $tag" >&2; exit 1;
  }
  actual=$(docker image inspect "$tag" --format '{{.Id}}' 2>/dev/null || true)
  if [[ $actual != "$expected_id" && $actual != "$archive_id" ]]; then
    if [[ ${VERIFY_ONLY:-0} == 1 ]]; then
      echo "Missing or incorrect image: $tag" >&2
      exit 1
    fi
    repository=${tag%:*}
    echo "Pulling $repository@$digest"
    docker pull "$repository@$digest"
    docker tag "$repository@$digest" "$tag"
    actual=$(docker image inspect "$tag" --format '{{.Id}}')
  fi
  [[ $actual == "$expected_id" || $actual == "$archive_id" ]] || {
    echo "Image ID mismatch for $tag: got $actual" >&2
    exit 1
  }
  echo "Verified $tag ($actual)"
done < "$lock"
