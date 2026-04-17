#!/usr/bin/env bash
set -e

# --- dns ---

# VirtualBox NAT DNS is always at 10.0.2.3 — set it explicitly so provisioning
# works regardless of what the base box ships with in /etc/resolv.conf
echo "nameserver 10.0.2.3" > /etc/resolv.conf

# --- bootstrap ---

apt-get update -qq
apt-get install -y -qq curl git

# uv manages python versions on its own — no need to install python3.12 via apt

# uv installed globally so both root and the naberius user can call it
# UV_PYTHON_INSTALL_DIR ensures python is stored in a shared path, not under /root/.local
curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh
export UV_PYTHON_INSTALL_DIR=/opt/uv-python

# --- system user ---

# dedicated user matches what the systemd units expect (User=naberius)
id naberius &>/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin naberius

# --- naberius ---

test -d /opt/naberius/.git || git clone -b main https://github.com/gustavonogvi/naberius-honeypot.git /opt/naberius

uv --directory /opt/naberius sync
uv --directory /opt/naberius run python db/init_db.py  # creates data/naberius.db

chown -R naberius:naberius /opt/naberius

# --- vassago ---

test -d /opt/vassago/.git || git clone -b main https://github.com/gustavonogvi/vassago-analyzer.git /opt/vassago

(cd /opt/vassago && uv sync)

# vassago reads naberius.db directly by file — symlink avoids copying or configuring paths
ln -s /opt/naberius/data/naberius.db /opt/vassago/data/naberius.db

chown -R naberius:naberius /opt/vassago

# --- services ---

cp /opt/naberius/deploy/naberius-honeypot.service /etc/systemd/system/
cp /opt/naberius/deploy/naberius-api.service      /etc/systemd/system/

systemctl daemon-reload
systemctl enable --now naberius-honeypot naberius-api

# --- vassago cron ---

# runs every 5 minutes as the naberius user; log goes to /var/log/vassago.log
echo "*/5 * * * * naberius /opt/vassago/run.sh >> /var/log/vassago.log 2>&1" \
    > /etc/cron.d/vassago
