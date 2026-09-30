#!/usr/bin/env bash
set -Eeuo pipefail

(( EUID == 0 )) || { echo 'Run as root inside the LXC.' >&2; exit 1; }
[[ $(uname -m) == x86_64 ]] || { echo 'This bundle requires amd64.' >&2; exit 1; }
source /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == 24.04 ]] || {
  echo 'This bundle targets Ubuntu 24.04.' >&2; exit 1;
}
(( $(nproc) >= 2 )) || { echo 'At least 2 vCPU are required.' >&2; exit 1; }
(( $(free -m | awk '/^Mem:/ {print $2}') >= 4096 )) || {
  echo 'At least 4 GB RAM is required.' >&2; exit 1;
}
(( $(df -BG / | awk 'NR==2 {gsub(/G/, "", $4); print $4}') >= 20 )) || {
  echo 'At least 20 GB free disk is required.' >&2; exit 1;
}

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl openssl openssh-server gnupg zstd
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
docker info >/dev/null
docker compose version

if ! id pentagi-admin >/dev/null 2>&1; then
  useradd -m -s /bin/bash pentagi-admin
fi
install -d -m 0700 -o pentagi-admin -g pentagi-admin /home/pentagi-admin/.ssh
install -m 0600 -o pentagi-admin -g pentagi-admin \
  /root/pentagi-setup/authorized_key.pub /home/pentagi-admin/.ssh/authorized_keys
cat >/etc/ssh/sshd_config.d/90-pentagi.conf <<'EOF'
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
EOF
systemctl enable --now ssh

install -d -m 0755 /opt/pentagi
cp /root/pentagi-setup/upstream/docker-compose.yml /opt/pentagi/
cp /root/pentagi-setup/upstream/example.*.provider.yml /opt/pentagi/
cp /root/pentagi-setup/docker-compose.override.yml /opt/pentagi/
if [[ ! -e /opt/pentagi/.env ]]; then
  postgres_password=$(openssl rand -hex 32)
  signing_salt=$(openssl rand -hex 32)
  scraper_password=$(openssl rand -hex 24)
  cat >/opt/pentagi/.env <<EOF
PENTAGI_IMAGE=vxcontrol/pentagi:2.1.0
PENTAGI_LISTEN_IP=127.0.0.1
PUBLIC_URL=https://localhost:8443
CORS_ORIGINS=https://localhost:8443
COOKIE_SIGNING_SALT=$signing_salt
PENTAGI_POSTGRES_PASSWORD=$postgres_password
LOCAL_SCRAPER_USERNAME=pentagi
LOCAL_SCRAPER_PASSWORD=$scraper_password
SCRAPER_PRIVATE_URL=https://pentagi:$scraper_password@scraper/
DOCKER_INSIDE=true
DOCKER_NET_ADMIN=false
DOCKER_DEFAULT_IMAGE=debian:latest
DOCKER_DEFAULT_IMAGE_FOR_PENTEST=vxcontrol/kali-linux:latest
OPEN_AI_KEY=
EOF
  chmod 0600 /opt/pentagi/.env
fi

bash /root/pentagi-setup/prefetch-images.sh
cd /opt/pentagi
docker compose config --quiet
docker compose up -d --pull never
bash /root/pentagi-setup/verify-inside-ct.sh
