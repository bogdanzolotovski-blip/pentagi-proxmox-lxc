#!/usr/bin/env bash
set -Eeuo pipefail

docker info >/dev/null
docker compose version
VERIFY_ONLY=1 bash /root/pentagi-setup/prefetch-images.sh
docker run --rm --pull never --network none vxcontrol/kali-linux:latest \
  /bin/sh -lc 'for tool in nmap sqlmap nikto nuclei ffuf hydra msfconsole gobuster feroxbuster amass; do command -v "$tool" >/dev/null || exit 1; done'
cd /opt/pentagi
docker compose config --quiet
docker compose ps
docker compose ps --status running --services | grep -Fxq pentagi
docker compose ps --status running --services | grep -Fxq pgvector
docker compose ps --status running --services | grep -Fxq scraper
curl --noproxy '*' --fail --silent --show-error --insecure --max-time 15 \
  https://127.0.0.1:8443/api/v1/info >/dev/null
echo 'PentAGI UI/API and required images are ready.'
