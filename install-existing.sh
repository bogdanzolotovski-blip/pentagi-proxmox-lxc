#!/usr/bin/env bash
set -Eeuo pipefail

(( EUID == 0 )) || { echo 'Run as root on the Proxmox node.' >&2; exit 1; }
ctid=${1:?Usage: ./install-existing.sh CTID /path/to/ssh-public-key}
public_key=${2:?Usage: ./install-existing.sh CTID /path/to/ssh-public-key}
[[ $ctid =~ ^[0-9]+$ ]] || { echo 'CTID must be numeric.' >&2; exit 1; }
[[ -f $public_key ]] || { echo "SSH public key missing: $public_key" >&2; exit 1; }
config=$(pct config "$ctid") || { echo "CT $ctid is unavailable." >&2; exit 1; }
grep -Eq '^unprivileged: 1$' <<<"$config" || { echo 'CT must be unprivileged.' >&2; exit 1; }
features=$(sed -n 's/^features: //p' <<<"$config")
[[ ,$features, == *,nesting=1,* && ,$features, == *,keyctl=1,* ]] || {
  echo 'CT requires nesting=1,keyctl=1. Set those features while stopped, then retry.' >&2; exit 1;
}
if ! pct status "$ctid" | grep -q running; then pct start "$ctid"; fi
ready=0
for _ in {1..30}; do
  if pct exec "$ctid" -- getent hosts archive.ubuntu.com >/dev/null 2>&1; then ready=1; break; fi
  sleep 2
done
(( ready == 1 )) || { echo 'CT networking/DNS is not ready.' >&2; exit 1; }

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
for file in install-inside-ct.sh prefetch-images.sh verify-inside-ct.sh images.lock docker-compose.override.yml; do
  [[ -s $source_dir/payload/$file ]] || { echo "Missing payload/$file" >&2; exit 1; }
done
for file in docker-compose.yml .env.example example.custom.provider.yml example.ollama.provider.yml EULA.md LICENSE; do
  [[ -s $source_dir/upstream/$file ]] || { echo "Missing upstream/$file" >&2; exit 1; }
done
if [[ -f $source_dir/images.tar.zst && ${ARCHIVE_VERIFIED:-0} != 1 ]]; then
  (cd "$source_dir" && sha256sum -c images.sha256)
fi

pct exec "$ctid" -- mkdir -p /root/pentagi-setup/upstream
for file in install-inside-ct.sh prefetch-images.sh verify-inside-ct.sh images.lock docker-compose.override.yml; do
  pct push "$ctid" "$source_dir/payload/$file" "/root/pentagi-setup/$file"
done
for file in docker-compose.yml .env.example example.custom.provider.yml example.ollama.provider.yml EULA.md LICENSE; do
  pct push "$ctid" "$source_dir/upstream/$file" "/root/pentagi-setup/upstream/$file"
done
pct push "$ctid" "$public_key" /root/pentagi-setup/authorized_key.pub
if [[ -f $source_dir/images.tar.zst ]]; then
  pct push "$ctid" "$source_dir/images.tar.zst" /root/pentagi-setup/images.tar.zst
  expected=$(awk '{print $1}' "$source_dir/images.sha256")
  actual=$(pct exec "$ctid" -- sha256sum /root/pentagi-setup/images.tar.zst | awk '{print $1}')
  [[ $actual == "$expected" ]] || { echo 'Image archive corrupted during pct push.' >&2; exit 1; }
elif [[ -f $source_dir/images.tar ]]; then
  pct push "$ctid" "$source_dir/images.tar" /root/pentagi-setup/images.tar
fi
pct exec "$ctid" -- bash /root/pentagi-setup/install-inside-ct.sh
