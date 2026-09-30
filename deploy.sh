#!/usr/bin/env bash
set -Eeuo pipefail

if (( EUID != 0 )); then
  echo 'Run this script as root on the Proxmox VE node.' >&2
  exit 1
fi
command -v pct >/dev/null || { echo 'pct is missing: run on a Proxmox VE node.' >&2; exit 1; }
command -v pveam >/dev/null || { echo 'pveam is missing.' >&2; exit 1; }

config=${1:-./config.env}
[[ -f "$config" ]] || { echo "Missing config: $config" >&2; exit 1; }
# The administrator owns this local file; never commit credentials in it.
set -a
source "$config"
set +a

: "${CTID:?}" "${PVE_STORAGE:?}" "${TEMPLATE_STORAGE:?}" "${BRIDGE:?}" "${SSH_PUBLIC_KEY_FILE:?}"
[[ $CTID =~ ^[0-9]+$ ]] || { echo 'CTID must be numeric.' >&2; exit 1; }
[[ $PVE_STORAGE =~ ^[a-zA-Z0-9_-]+$ && $TEMPLATE_STORAGE =~ ^[a-zA-Z0-9_-]+$ && $BRIDGE =~ ^[a-zA-Z0-9_.-]+$ ]] || {
  echo 'Invalid storage or bridge name.' >&2; exit 1;
}
[[ -f $SSH_PUBLIC_KEY_FILE ]] || { echo "SSH public key missing: $SSH_PUBLIC_KEY_FILE" >&2; exit 1; }
if pct config "$CTID" >/dev/null 2>&1; then
  echo "CT $CTID already exists. Refusing to modify it." >&2
  exit 1
fi
cores=${CORES:-4}
memory=${MEMORY_MB:-8192}
disk=${ROOTFS_GB:-64}
(( cores >= 2 && memory >= 4096 && disk >= 40 )) || {
  echo 'Provide at least 2 cores, 4096 MB RAM and 40 GB rootfs.' >&2; exit 1;
}
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
for file in install-inside-ct.sh prefetch-images.sh verify-inside-ct.sh images.lock docker-compose.override.yml; do
  [[ -s $source_dir/payload/$file ]] || { echo "Missing payload/$file" >&2; exit 1; }
done
for file in docker-compose.yml .env.example example.custom.provider.yml example.ollama.provider.yml EULA.md LICENSE; do
  [[ -s $source_dir/upstream/$file ]] || { echo "Missing upstream/$file" >&2; exit 1; }
done
if [[ -f $source_dir/images.tar.zst ]]; then
  (cd "$source_dir" && sha256sum -c images.sha256)
fi

template=$(pveam available --section system | awk '$2 ~ /^ubuntu-24\.04-standard_.*_amd64\.tar\.zst$/ {print $2}' | sort -V | tail -1)
[[ -n $template ]] || { echo 'Ubuntu 24.04 LXC template is unavailable.' >&2; exit 1; }
template_volid="$TEMPLATE_STORAGE:vztmpl/$template"
if ! pveam list "$TEMPLATE_STORAGE" | awk '{print $1}' | grep -Fxq "$template_volid"; then
  pveam download "$TEMPLATE_STORAGE" "$template"
fi

net0="name=eth0,bridge=$BRIDGE,ip=${IP_CONFIG:-dhcp},firewall=1"
if [[ -n ${GATEWAY:-} ]]; then net0+=",gw=$GATEWAY"; fi
if [[ -n ${VLAN_TAG:-} ]]; then net0+=",tag=$VLAN_TAG"; fi

echo "Creating unprivileged CT $CTID from $template_volid"
pct create "$CTID" "$template_volid" \
  --hostname "pentagi-$CTID" --ostype ubuntu --arch amd64 \
  --unprivileged 1 --features nesting=1,keyctl=1 \
  --cores "$cores" --memory "$memory" --swap 0 \
  --rootfs "$PVE_STORAGE:$disk" --net0 "$net0" --onboot 1
pct start "$CTID"

ARCHIVE_VERIFIED=1 bash "$source_dir/install-existing.sh" "$CTID" "$SSH_PUBLIC_KEY_FILE"
echo "CT $CTID is provisioned. Run ./verify.sh $CTID and configure an LLM provider in /opt/pentagi/.env."
