#!/usr/bin/env bash
set -e

# --- tools ---

# kali rolling boxes vary — force install rather than assume
apt-get update -qq
apt-get install -y -qq hydra medusa nmap netexec
