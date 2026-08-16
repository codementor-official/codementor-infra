#!/usr/bin/env bash
set -euo pipefail

COMPOSE_VERSION="${COMPOSE_VERSION:-v5.1.4}"
TARGET_USER="${SUDO_USER:-ec2-user}"

sudo dnf install -y docker git
sudo systemctl enable --now docker
sudo usermod -aG docker "$TARGET_USER"

plugin_dir=/usr/local/lib/docker/cli-plugins
plugin_path="$plugin_dir/docker-compose"
download_url="https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64"
checksum_url="${download_url}.sha256"

sudo mkdir -p "$plugin_dir"
tmp_binary="$(mktemp)"
tmp_checksum="$(mktemp)"
trap 'rm -f "$tmp_binary" "$tmp_checksum"' EXIT

curl -fsSL "$download_url" -o "$tmp_binary"
curl -fsSL "$checksum_url" -o "$tmp_checksum"
expected_checksum="$(awk '{print $1}' "$tmp_checksum")"
printf '%s  %s\n' "$expected_checksum" "$tmp_binary" | sha256sum --check --status
sudo install -m 0755 "$tmp_binary" "$plugin_path"

if ! swapon --show=NAME --noheadings | grep -q .; then
  sudo fallocate -l 2G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
fi

if ! grep -q '^/swapfile ' /etc/fstab; then
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
fi

sudo docker --version
sudo docker compose version
free -h
