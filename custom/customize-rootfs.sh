#!/usr/bin/env bash
# Runs INSIDE the image rootfs (chroot, as root) on the target architecture.
# Installs the toolchain requested for this N1 build:
#   - python3 (pip/venv), rust (rustc/cargo), build tools
#   - Metasploit Framework (optional) with PostgreSQL support
# Keep it minimal: server edition, --no-install-recommends, docs/man/locale excluded.
set -euo pipefail

INSTALL_MSF="${1:-true}"
export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8

echo "[*] skip docs/man/locale for newly installed packages"
cat > /etc/dpkg/dpkg.cfg.d/01-tiny <<'EOF'
path-exclude=/usr/share/doc/*
path-exclude=/usr/share/man/*
path-exclude=/usr/share/locale/*
EOF

echo "[*] apt-get update"
apt-get update

echo "[*] installing toolchain packages"
apt-get install -y --no-install-recommends \
  build-essential pkg-config git curl wget ca-certificates \
  python3 python3-pip python3-venv python3-dev \
  rustc cargo \
  ruby-full ruby-dev libyaml-dev libssl-dev libreadline-dev zlib1g-dev \
  libffi-dev libsqlite3-dev libpcap-dev libxml2-dev libxslt1-dev \
  postgresql postgresql-contrib libpq-dev

echo "[*] versions:"
python3 -V
rustc -V
cargo -V

if [[ "${INSTALL_MSF}" == "true" ]]; then
  echo "[*] cloning metasploit-framework"
  git clone --depth=1 https://github.com/rapid7/metasploit-framework /opt/metasploit-framework
  rm -rf /opt/metasploit-framework/.git
  cd /opt/metasploit-framework
  echo "[*] bundle install (heavy step, please wait)"
  gem install bundler --no-document
  bundle config set --local without 'development test'
  bundle config set --local jobs "$(nproc)"
  bundle install || { echo "[*] bundle install failed once, retrying"; sleep 10; bundle install; }
  for m in msfconsole msfdb msfrpc msfvenom msfupdate; do
    if [ -f "/opt/metasploit-framework/${m}" ]; then
      ln -sf "/opt/metasploit-framework/${m}" "/usr/local/bin/${m}"
    fi
  done
  echo "[*] enabling postgresql (for msfdb init)"
  systemctl enable postgresql 2>/dev/null || true
  bundle clean --force 2>/dev/null || true
fi

echo "[*] cleaning up"
apt-get autoremove -y >/dev/null 2>&1 || true
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb /tmp/* /var/tmp/*
rm -rf /root/.cache /root/.gem /root/.bundle /usr/local/lib/ruby/gems/*/cache

echo "[+] rootfs customization done"
