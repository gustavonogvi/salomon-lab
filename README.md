# Salomon Lab

A self-contained Blue Team home lab that spins up with a single command.

The lab simulates real attacks, captures them, and analyzes the results — covering the full pipeline from attacker activity to detection and reporting.

---

## What it does

**Scenario 1 — SSH Brute Force**
A Kali Linux VM runs `hydra` against an SSH honeypot running on a Debian VM. Every login attempt is captured and stored. An analyzer then reads the data, applies detection rules, maps techniques to MITRE ATT&CK, and generates an alert report.

**Scenario 2 — Windows SMB Attack**
Kali runs `netexec` against the host Windows machine via SMB. Windows generates login failure events (Event ID 4625) which are read and parsed by [winlog](https://github.com/gustavonogvi/winlog).

---

## Tools

| Project | Role |
|---|---|
| [naberius-honeypot](https://github.com/gustavonogvi/naberius-honeypot) | SSH honeypot — captures login attempts on port 2222 and stores them in SQLite |
| [vassago-analyzer](https://github.com/gustavonogvi/vassago-analyzer) | Log analyzer — reads the honeypot database, applies detection rules, maps to MITRE ATT&CK |
| [winlog](https://github.com/gustavonogvi/winlog) | Windows event parser — reads the host's Security Event Log and surfaces suspicious activity |

Both are independent projects and can be used outside of this lab.

---

## Requirements

- [VirtualBox 7.x](https://www.virtualbox.org/)
- [Vagrant 2.4.x](https://developer.hashicorp.com/vagrant/install)
- Windows 11 host
- ~5 GB free disk space
- ~4 GB free RAM while the lab is running

---

## Host setup (one-time)

### 1. VirtualBox host-only network

The lab uses the `192.168.56.0/24` network. VirtualBox usually creates this adapter automatically, but verify it exists:

```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" list hostonlyifs
```

You should see `IPAddress: 192.168.56.1` and `Status: Up`. If not, create it:

```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" hostonlyif create
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" hostonlyif ipconfig "VirtualBox Host-Only Ethernet Adapter" --ip 192.168.56.1 --netmask 255.255.255.0
```

### 2. Firewall rules (run PowerShell as Administrator)

```powershell
New-NetFirewallRule -DisplayName "Solomon Lab - SMB" -Direction Inbound -Protocol TCP -LocalPort 445 -RemoteAddress 192.168.56.0/24 -Action Allow
New-NetFirewallRule -DisplayName "Solomon Lab - RDP" -Direction Inbound -Protocol TCP -LocalPort 3389 -RemoteAddress 192.168.56.0/24 -Action Allow
```

### 3. Enable RDP

Settings → System → Remote Desktop → Enable Remote Desktop.

---

## Running the lab

Clone the repo and bring up the VMs:

```bash
git clone https://github.com/gustavonogvi/salomon-lab.git
cd salomon-lab
vagrant up
```

The first run downloads the base boxes and provisions both VMs automatically. No manual steps required after this.

To bring up only one VM:

```bash
vagrant up debian
vagrant up kali
```

---

## Verifying the setup

SSH into the Debian VM and confirm the honeypot is running:

```bash
vagrant ssh debian
systemctl status naberius-honeypot naberius-api
ss -tlnp | grep 2222
```

---

## Running the scenarios

### Scenario 1 — SSH brute force

From the Kali VM:

```bash
vagrant ssh kali
hydra -l root -P /usr/share/wordlists/rockyou.txt ssh://192.168.56.20:2222
```

Check captured events on the Debian VM:

```bash
vagrant ssh debian
sqlite3 /opt/naberius/data/naberius.db "SELECT * FROM events;"
```

Run Vassago to analyze and generate alerts:

```bash
cd /opt/vassago && uv run python main.py
sqlite3 /opt/vassago/data/alerts.db "SELECT * FROM alerts;"
```

Vassago also runs automatically every 5 minutes via cron.

### Scenario 2 — SMB attack

From the Kali VM:

```bash
vagrant ssh kali
netexec smb 192.168.56.1 -u administrator -p /usr/share/wordlists/rockyou.txt
```

Windows will generate Event ID 4625 (logon failure) entries in the Security Event Log.

---

## Network layout

```
┌─────────────────────────────────────────────────────┐
│              Host-Only Network: 192.168.56.0/24     │
│                                                     │
│  [Kali — 192.168.56.10]                             │
│   └─ hydra / medusa / netexec / nmap                │
│       │                          │                  │
│       ▼                          ▼                  │
│  [Debian — 192.168.56.20]   [Windows 11 — .56.1]    │
│   └─ Naberius :2222          └─ host machine        │
│   └─ Naberius API :5000      └─ SMB / RDP target    │
│   └─ Vassago (cron)                                 │
└─────────────────────────────────────────────────────┘
```

The Windows machine is the host itself — not a VM. VirtualBox exposes it at `192.168.56.1` on the host-only network.

---

## Shutting down

```bash
vagrant halt
```

To destroy the VMs completely:

```bash
vagrant destroy -f
```
