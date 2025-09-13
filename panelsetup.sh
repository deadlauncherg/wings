#!/usr/bin/env bash
# termux-debian-final.sh
# Final, user-friendly installer: Debian (proot-distro) for Termux.
# NOTE: This does NOT provide Android device/kernel root. It creates a proot container.

set -euo pipefail
LOGFILE="$HOME/termux-debian-final.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "=== Termux → Debian (proot-distro) final installer ==="
echo "Log: $LOGFILE"
echo

# Quick Termux check (best-effort)
if [ -z "${PREFIX:-}" ] || ! echo "$PREFIX" | grep -qi "com.termux"; then
  echo "[WARN] PREFIX doesn't look like Termux. Script intended for Termux on Android."
fi

echo "[1/6] Update Termux packages and install proot-distro..."
pkg update -y
pkg upgrade -y
pkg install -y proot-distro proot wget tar curl git nano

DISTRO_NAME="debian"
DEBIAN_RELEASE="stable"   # change to 'bookworm' or 'bookworm' if you prefer specific

# If Debian not installed, install it
if ! proot-distro list | grep -qi "^${DISTRO_NAME}"; then
  echo "[2/6] Installing Debian (${DEBIAN_RELEASE}) via proot-distro..."
  # The default proot-distro install will fetch a Debian tarball automatically.
  proot-distro install "${DISTRO_NAME}"
else
  echo "[2/6] Debian already installed; skipping install."
fi

echo "[3/6] Configuring Debian: update, upgrade, install packages..."
# Run apt commands inside the container; ensure DEBIAN_FRONTEND noninteractive to avoid prompts
proot-distro login "${DISTRO_NAME}" -- bash -lc "
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -y || (echo '[ERR] apt-get update failed' && exit 1)
apt-get upgrade -y
# Essential packages you likely want — add/remove as needed
apt-get install -y sudo openssh-server build-essential curl wget git python3 python3-pip nodejs npm iproute2 htop nano locales ca-certificates gnupg lsb-release
# Set locales to avoid warnings (optional)
if ! locale -a | grep -q en_US.utf8; then
  apt-get install -y locales
  sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen || true
  locale-gen
fi
# Set root password to 'root' (change after login)
echo 'root:root' | chpasswd || true
# Create a normal user 'termuxuser' if not exists
if ! id -u termuxuser >/dev/null 2>&1; then
  useradd -m -s /bin/bash termuxuser || true
  echo 'termuxuser:termux' | chpasswd || true
  usermod -aG sudo termuxuser || true
fi
# (Optional) enable passwordless sudo for termuxuser — uncomment to enable
# mkdir -p /etc/sudoers.d
# echo 'termuxuser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/termuxuser
# chmod 0440 /etc/sudoers.d/termuxuser

# Configure SSHD to allow password login (useful for tunneling/testing)
mkdir -p /var/run/sshd
sed -ri 's/^#?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || true
sed -ri 's/^#?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
if grep -q '^UsePAM' /etc/ssh/sshd_config; then
  sed -ri 's/^UsePAM.*/UsePAM no/' /etc/ssh/sshd_config || true
else
  echo 'UsePAM no' >> /etc/ssh/sshd_config
fi

# Cleanup
apt-get autoremove -y
apt-get clean
"

echo "[4/6] Creating handy launcher scripts (~/.local/bin)..."
mkdir -p "$HOME/.local/bin"

cat > "$HOME/.local/bin/debian-login" <<'EOF'
#!/usr/bin/env bash
# Login to Debian container as root (interactive)
proot-distro login debian --shared-tmp --env HOME=/root -- bash -l
EOF
chmod +x "$HOME/.local/bin/debian-login"

cat > "$HOME/.local/bin/debian-user" <<'EOF'
#!/usr/bin/env bash
# Login as the normal user 'termuxuser'
proot-distro login debian --user termuxuser -- bash -l
EOF
chmod +x "$HOME/.local/bin/debian-user"

cat > "$HOME/.local/bin/debian-sshd-start" <<'EOF'
#!/usr/bin/env bash
# Start sshd inside Debian proot-distro (in background)
echo "[+] Launching Debian sshd inside proot (background)..."
proot-distro login debian -- bash -lc 'mkdir -p /var/run/sshd && /usr/sbin/sshd -D' &
echo "[+] sshd launched. Use 'ps aux | grep sshd' inside Debian to verify."
EOF
chmod +x "$HOME/.local/bin/debian-sshd-start"

echo "[5/6] Final notes & verification..."
cat << EOF

Finished.
- Use 'debian-login' to enter Debian as root (no sudo required).
- Use 'debian-user' to enter as 'termuxuser' (password: termux) and then 'sudo -i' or 'sudo su' to become root.
- Default passwords (change them immediately inside Debian):
    root : root
    termuxuser : termux

Inside Debian you can run:
  apt update
  apt install <package>
  node --version
  python3 --version
  git --version

A few tips:
- To install packages inside Debian, ALWAYS run apt from inside the container (after debian-login).
- If you want to connect to the Debian sshd from another device, you must forward the port from your Android device (e.g., via adb or a tunneling service). Android may block direct inbound ports on some devices/ROMs.
- This environment gives a full Debian userland with apt — it does NOT change Android kernel/device root.

EOF

echo "[6/6] Quick automated verification (inside container):"
proot-distro login debian -- bash -lc "echo 'VERIFIED: inside Debian'; uname -a || true; which apt || true; apt --version || true; node --version || true; python3 --version || true"

echo "Installer log: $LOGFILE"
