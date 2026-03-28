# Solomon Lab
---

## Origin of the idea

Portfolio project to demonstrate a complete Blue Team pipeline:
**generate real attacks → capture → detect → analyze.**

The differentiator is that the entire environment spins up with a single command (`vagrant up`),
with no manual configuration of VMs, networks, or dependencies.

---

## Tools that make up the lab

| Project | Role | Repo |
|---|---|---|
| **Naberius** | SSH Honeypot — captures login attempts on port 2222 | [gustavonogvi/naberius-honeypot](https://github.com/gustavonogvi/naberius-honeypot) |
| **Vassago** | Analyzer — reads Naberius's SQLite, applies rules, detects MITRE patterns | [gustavonogvi/vassago-analyzer](https://github.com/gustavonogvi/vassago-analyzer) |
| **log-parsing** | Windows event parser — reads the host's Security Event Log | local (CBS-blue-team) |

Each tool is an independent project and can be used standalone — refer to their individual repositories for setup and usage details.

---

## Network architecture

```
┌─────────────────────────────────────────────────────┐
│              Host-Only Network: 192.168.56.0/24      │
│                                                      │
│  [Kali — 192.168.56.10]                              │
│   └─ hydra / medusa / crackmapexec / nmap            │
│       │                          │                   │
│       ▼                          ▼                   │
│  [Debian — 192.168.56.20]   [Windows 11 — .56.1]    │
│   └─ Naberius :2222          └─ user's host          │
│   └─ naberius.db             └─ native log-parsing   │
│   └─ Vassago (analysis)      └─ SMB/RDP target       │
└─────────────────────────────────────────────────────┘
```

**Note:** Windows 11 is the host itself (not a VM). VirtualBox exposes the host
at IP `192.168.56.1` on the host-only network. This eliminates the need to download
a Windows box (~15 GB) without losing the scenario's functionality.

---

## Flow per scenario

### Scenario 1 — SSH brute force (Naberius + Vassago)

```
Kali runs hydra → Debian port 2222
Naberius captures: IP, username, attempted password, timestamp
Data saved to naberius.db (SQLite)
Vassago reads naberius.db → applies JSON rules → detects T1110.001
Report generated with severity and mapped TTPs
```

### Scenario 2 — Windows event log monitoring

```
Kali runs crackmapexec → Windows 11 host via SMB
Windows generates events 4625 (login failure)
log-parsing reads the Security Event Log
Parser displays attempts, timestamps, source
```

---

## Architecture decisions

| Decision | Discarded alternative | Reason |
|---|---|---|
| Vagrant + VirtualBox | Docker / Docker Compose | Scenarios require real VMs (SSH, SMB, Windows events) |
| Host Windows as target | Windows box in Vagrant | Box weighs ~15 GB; host already exists and generates real events |
| Debian minimal as server VM | Ubuntu Server / BSD | Same apt ecosystem, ~300 MB less disk, ~120 MB less RAM idle, no rewrite needed |
| 2 VMs (Kali + Debian) | 3 VMs | Reduces required RAM (~3 GB total vs ~8 GB) |
| Provisioning via shell scripts | Ansible / Chef | Less dependency, more readable for portfolio |
| Clone repos during provision | Local synced folder | Allows anyone to clone and run, not just the author |

---

## End-user prerequisites

- VirtualBox 7.x installed
- Vagrant 2.4.x installed
- Windows 11 (host) with firewall allowing SMB/RDP from the `192.168.56.0/24` network
- ~4.5 GB free (Kali ~4 GB + Debian ~200 MB on first run)

## Host setup (one-time)

These steps only need to be done once before the first `vagrant up`.

### 1. Verify VirtualBox host-only network
VirtualBox must have a host-only adapter at `192.168.56.1/255.255.255.0`. Verify via PowerShell:

```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" list hostonlyifs
```

Expected output includes `IPAddress: 192.168.56.1` and `Status: Up`.
If missing, create it:

```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" hostonlyif create
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" hostonlyif ipconfig "VirtualBox Host-Only Ethernet Adapter" --ip 192.168.56.1 --netmask 255.255.255.0
```

### 2. Windows Firewall — allow SMB and RDP from the lab network
Run PowerShell as Administrator:

```powershell
New-NetFirewallRule -DisplayName "Solomon Lab - SMB" -Direction Inbound -Protocol TCP -LocalPort 445 -RemoteAddress 192.168.56.0/24 -Action Allow
New-NetFirewallRule -DisplayName "Solomon Lab - RDP" -Direction Inbound -Protocol TCP -LocalPort 3389 -RemoteAddress 192.168.56.0/24 -Action Allow
```

### 3. Enable RDP on the host
Settings → System → Remote Desktop → Enable Remote Desktop.

---

## File structure

```
solomon/
├── Vagrantfile
├── SOLOMON.md          ← this file
├── README.md           ← usage guide (public)
└── provision/
    ├── kali.sh         ← ensures attack tools are present
    └── debian.sh       ← installs Naberius + Vassago
```

---

## What runs on each VM

### Debian (192.168.56.20)

| Component | How it runs | Port |
|---|---|---|
| Naberius honeypot | systemd service (`naberius-honeypot.service`) | 2222 |
| Naberius API | systemd service (`naberius-api.service`) | 5000 |
| Vassago analyzer | cron job every 5 minutes (`/etc/cron.d/vassago`) | — |

Both services start automatically on boot. Vassago reads `/opt/naberius/data/naberius.db` via symlink at `/opt/vassago/data/naberius.db`. All processes run as the `naberius` system user. Python 3.12 is managed by `uv` and stored at `/opt/uv-python`.

### Kali (192.168.56.10)

Attack tools available: `hydra`, `medusa`, `nmap`, `netexec`.

---

## Useful commands

```bash
# start the lab
vagrant up

# start only one VM
vagrant up debian
vagrant up kali

# SSH into a VM
vagrant ssh debian
vagrant ssh kali

# re-run provisioning without destroying
vagrant provision debian

# check services on Debian
systemctl status naberius-honeypot naberius-api

# confirm honeypot is listening
ss -tlnp | grep 2222

# check captured events
sqlite3 /opt/naberius/data/naberius.db "SELECT * FROM events;"

# run Vassago manually
cd /opt/vassago && uv run python main.py

# check alerts generated by Vassago
sqlite3 /opt/vassago/data/alerts.db "SELECT * FROM alerts;"

# shut down the lab
vagrant halt

# destroy everything
vagrant destroy -f
```

---

## Current status

- [x] Architecture defined
- [x] Decisions documented
- [x] Naberius ready for automatic provisioning
- [x] Vassago ready for automatic provisioning
- [x] Vagrantfile
- [x] Provisioning scripts
- [ ] Kali tested end-to-end
- [ ] Public README
