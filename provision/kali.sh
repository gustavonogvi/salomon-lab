#!/usr/bin/env bash
set -e

# --- dns ---

# VirtualBox NAT DNS is always at 10.0.2.3 — set it explicitly so provisioning
# works regardless of what the base box ships with in /etc/resolv.conf
echo "nameserver 10.0.2.3" > /etc/resolv.conf

# --- tools ---

# kali rolling boxes vary — force install rather than assume
apt-get update -qq
apt-get install -y -qq hydra medusa nmap netexec
