#!/usr/bin/env bash
# Runs INSIDE the image rootfs (chroot, as root) on the target architecture.
# Installs the toolchain requested for this N1 build:
#   - python3 (pip/venv), rust (rustc/cargo), build tools
#   - Metasploit Framework (optional) with PostgreSQL support
# Keep it minimal: server edition, --no-install-recommends, docs/man/locale excluded.
set -euo pipefail

INSTALL_MSF="${1:-true}"
PROFILE="${2:-base}"
XRAY_ZIP_URL="${3:-}"
V2RAYA_DEB_URL="${4:-}"
export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8

if [[ "${PROFILE}" == "pentest" && "${INSTALL_MSF}" == "true" ]]; then
  echo "[*] pentest profile: metasploit disabled (disk budget on 8G eMMC)"
  INSTALL_MSF="false"
fi

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
  build-essential pkg-config git curl wget ca-certificates unzip zip \
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

  # Debian ships some gems (xmlrpc, ...) as apt packages with gemspecs, which
  # confuses bundler's install phase ("Could not find X.gem for installation").
  # Pre-install the known offender and auto-recover from the rest.
  gem install xmlrpc --no-document || true
  set +e
  bundle_rc=1
  for attempt in 1 2 3 4 5; do
    out="$(bundle install 2>&1)"; bundle_rc=$?
    echo "${out}" | tail -n 150
    [ ${bundle_rc} -eq 0 ] && break
    gem_file="$(echo "${out}" | grep -oE 'Could not find [a-zA-Z0-9_.-]+\.gem' | head -n 1 | sed -E 's/^Could not find //; s/\.gem$//')"
    [ -n "${gem_file}" ] || break
    gem_name="${gem_file%-*}"
    gem_ver="${gem_file##*-}"
    echo "[*] bundler stuck on ${gem_name}-${gem_ver}; pre-installing with gem"
    gem install "${gem_name}" -v "${gem_ver}" --no-document || break
  done
  set -e
  [ ${bundle_rc} -eq 0 ] || { echo "[!] bundle install failed"; exit 1; }
  for m in msfconsole msfdb msfrpc msfvenom msfupdate; do
    if [ -f "/opt/metasploit-framework/${m}" ]; then
      ln -sf "/opt/metasploit-framework/${m}" "/usr/local/bin/${m}"
    fi
  done
  echo "[*] enabling postgresql (for msfdb init)"
  systemctl enable postgresql 2>/dev/null || true
  bundle clean --force 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# pentest profile: common pentest tools + v2rayA (Xray core, arm64)
# ---------------------------------------------------------------------------
install_v2raya() {
  mkdir -p /usr/local/share/xray

  # Xray core (arm64): direct "latest" download URL, no api.github.com needed
  # (anonymous API quotas are exhausted on shared runner IPs -> 403)
  local xzip="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip"
  echo "[*] Xray core: ${xzip}"
  curl -fsSL --retry 3 "${xzip}" -o /tmp/xray.zip
  unzip -o /tmp/xray.zip xray -d /usr/local/bin/ >/dev/null && chmod +x /usr/local/bin/xray
  rm -f /tmp/xray.zip
  curl -fsSL --retry 3 "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" -o /usr/local/share/xray/geoip.dat
  curl -fsSL --retry 3 "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" -o /usr/local/share/xray/geosite.dat

  # v2rayA: official apt repo first, host-resolved deb URL as fallback
  if ! dpkg -s v2raya >/dev/null 2>&1; then
    echo "[*] v2rayA via apt.v2raya.org"
    curl -fsSL --retry 3 "https://apt.v2raya.org/key/public-key.asc" -o /usr/share/keyrings/v2raya.asc
    echo "deb [signed-by=/usr/share/keyrings/v2raya.asc] https://apt.v2raya.org greatwall main" >/etc/apt/sources.list.d/v2raya.list
    apt-get update >/dev/null 2>&1 || true
    apt-get install -y v2raya >/dev/null 2>&1 || true
  fi
  if ! dpkg -s v2raya >/dev/null 2>&1 && [ -n "${V2RAYA_DEB_URL}" ]; then
    echo "[*] v2rayA fallback: ${V2RAYA_DEB_URL}"
    curl -fsSL --retry 3 "${V2RAYA_DEB_URL}" -o /tmp/v2raya.deb
    if [ "$(stat -c%s /tmp/v2raya.deb 2>/dev/null || echo 0)" -lt 1048576 ]; then
      echo "[skip] v2rayA deb download invalid"; rm -f /tmp/v2raya.deb; return 0
    fi
    apt-get install -y /tmp/v2raya.deb || dpkg -i /tmp/v2raya.deb || true
    rm -f /tmp/v2raya.deb
  fi
  systemctl enable v2raya 2>/dev/null || true
}

if [[ "${PROFILE}" == "pentest" ]]; then
  echo "[*] installing common pentest tools (best-effort, missing ones are skipped)"
  PENTEST_PKGS="nmap masscan whatweb nikto wafw00f dirb dirsearch wfuzz fierce \
dnsrecon dnsenum gobuster ffuf amass hydra john hashcat aircrack-ng hping3 \
macchanger sqlmap sslscan testssl.sh tcpdump tshark netcat-openbsd socat \
proxychains4 smbclient enum4linux onesixtyone seclists pwntools theharvester sublist3r wpscan"
  if ! apt-get install -y --no-install-recommends ${PENTEST_PKGS} >/tmp/pentest-apt.log 2>&1; then
    echo "[*] batch install had failures, retrying packages individually"
    for p in ${PENTEST_PKGS}; do
      apt-get install -y --no-install-recommends "${p}" >>/tmp/pentest-apt.log 2>&1 \
        || echo "[skip] not available in repo: ${p}"
    done
  fi

  echo "[*] python attack libs (impacket)"
  pip3 install --break-system-packages --no-cache-dir impacket || true

  # free the apt deb cache early: the big git clones below need the headroom
  apt-get clean

  echo "[*] Responder"
  git clone --depth=1 https://github.com/lgandx/Responder /opt/Responder 2>/dev/null || true

  echo "[*] seclists"
  [ -d /usr/share/seclists ] || git clone --depth=1 https://github.com/danielmiessler/SecLists /usr/share/seclists 2>/dev/null || true

  echo "[*] exploitdb / searchsploit (gitlab)"
  if ! command -v searchsploit >/dev/null 2>&1; then
    git clone --depth=1 https://gitlab.com/exploit-database/exploitdb /usr/share/exploitdb 2>/dev/null || true
    if [ -f /usr/share/exploitdb/searchsploit ]; then
      ln -sf /usr/share/exploitdb/searchsploit /usr/local/bin/searchsploit
    fi
  fi

  echo "[*] v2rayA + Xray-core"
  install_v2raya || true

  echo "[*] preset proxychains4 -> v2rayA local socks5 (127.0.0.1:20170)"
  if [ -f /etc/proxychains4.conf ]; then
    sed -i -E '/^socks[45][[:space:]]/d' /etc/proxychains4.conf
    echo "socks5 127.0.0.1 20170" >>/etc/proxychains4.conf
  fi

  echo "[*] pentest tool inventory:"
  for t in nmap masscan hydra john hashcat sqlmap nikto gobuster ffuf aircrack-ng \
           hping3 searchsploit impacket-smbclient; do
    command -v "${t}" >/dev/null 2>&1 && echo "  [ok] ${t}" || echo "  [--] ${t} (not installed)"
  done
  [ -d /usr/share/seclists ] && echo "  [ok] seclists (/usr/share/seclists)" || echo "  [--] seclists"
  [ -d /opt/Responder ] && echo "  [ok] Responder (/opt/Responder)" || echo "  [--] Responder"
  python3 -c "import impacket" 2>/dev/null && echo "  [ok] impacket (python)" || echo "  [--] impacket (python)"
  [ -x /usr/local/bin/xray ] && echo "  [ok] xray (/usr/local/bin/xray)" || echo "  [--] xray"
  ls /usr/local/bin/impacket-* >/dev/null 2>&1 && echo "  [ok] impacket CLI tools" || echo "  [--] impacket CLI tools"
  dpkg -s v2raya >/dev/null 2>&1 && echo "  [ok] v2raya (deb)" || echo "  [--] v2raya"
  df -h / | tail -n 1
fi

echo "[*] cleaning up"
apt-get autoremove -y >/dev/null 2>&1 || true
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb /tmp/* /var/tmp/*
rm -rf /root/.cache /root/.gem /root/.bundle /usr/local/lib/ruby/gems/*/cache

echo "[+] rootfs customization done"
