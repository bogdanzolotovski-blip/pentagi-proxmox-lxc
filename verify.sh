#!/usr/bin/env bash
set -Eeuo pipefail
(( EUID == 0 )) || { echo 'Run as root on the Proxmox node.' >&2; exit 1; }
ctid=${1:?Usage: ./verify.sh CTID}
pct status "$ctid"
pct exec "$ctid" -- bash /root/pentagi-setup/verify-inside-ct.sh
