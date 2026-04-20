# Salomon Lab

A self-contained Blue Team home lab that spins up with a single command.

The lab simulates real attacks, captures them, and analyzes the results — covering the full pipeline from attacker activity to detection and reporting.

---

## What it does

**Scenario 1 — SSH Brute Force**
A Kali Linux VM runs `medusa` against an SSH honeypot running on a Debian VM. Every login attempt is captured and stored. An analyzer then reads the data, applies detection rules, maps techniques to MITRE ATT&CK, and generates an alert report.

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

The first run downloads the base boxes and provisions both VMs automatically. DNS is configured automatically during provisioning — no manual network setup required.

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

From your host browser, confirm the API is reachable:

```
http://192.168.56.20:5000/events
```

---

## What runs on the Debian VM

| Component | How it runs | Address |
|---|---|---|
| Naberius honeypot | systemd service | `192.168.56.20:2222` |
| Naberius REST API | systemd service | `http://192.168.56.20:5000` |
| Vassago analyzer | cron every 5 min | — |

Both services start automatically on boot. Vassago reads `/opt/naberius/data/naberius.db` via symlink at `/opt/vassago/data/naberius.db`.

### API endpoints

| Endpoint | Description |
|---|---|
| `GET /events` | All captured events, ordered by most recent |
| `GET /stats/brute-force` | IPs exceeding a threshold of attempts in a time window |
| `GET /stats/top-credentials` | Top 10 most attempted usernames and passwords |

### Dashboard

Open `naberius-honeypot/dashboard/index.html` in your browser while the lab is running. The dashboard reads from the API at `http://192.168.56.20:5000` and shows events in real time.

---

## Running the scenarios

### Scenario 1 — SSH brute force

From the Kali VM:

```bash
vagrant ssh kali
medusa -u root -P /usr/share/wordlists/rockyou.txt -h 192.168.56.20 -n 2222 -M ssh -t 1
```

> **Note:** `hydra` is not compatible with this honeypot — key exchange mismatch between libssh and paramiko. Use `medusa` instead.

Check captured events on the Debian VM:

```bash
vagrant ssh debian
python3 -c "import sqlite3; conn=sqlite3.connect('/opt/naberius/data/naberius.db'); [print(r) for r in conn.execute('SELECT ip, username, password, hassh FROM events')]"
```

Run Vassago to analyze and generate alerts:

```bash
sudo -u naberius bash -c "cd /opt/vassago && UV_CACHE_DIR=/tmp/uv-cache uv run python main.py --report html --output reports/report"
```

Check the alerts:

```bash
python3 -c "import sqlite3; conn=sqlite3.connect('/opt/vassago/data/alerts.db'); [print(r) for r in conn.execute('SELECT severity, rule, ip FROM alerts')]"
```

Vassago also runs automatically every 5 minutes via cron.

### Troubleshooting

**`unable to open database file`**
The `data/` directory is owned by `naberius`. Running as `vagrant` causes a permission error. Always run Vassago as the `naberius` user with `sudo -u naberius`.

**`failed to create directory /home/naberius/.cache/uv: Permission denied`**
The `naberius` user has no home directory. Set `UV_CACHE_DIR` to a writable path like `/tmp/uv-cache`.

**`sqlite3: command not found`**
`sqlite3` CLI is not installed on the Debian VM. Query the database with Python instead:
```bash
python3 -c "import sqlite3; conn=sqlite3.connect('/opt/vassago/data/alerts.db'); [print(r) for r in conn.execute('SELECT * FROM alerts')]"
```

**No internet inside the VM (DNS broken)**
Some base boxes ship with a wrong DNS in `/etc/resolv.conf`. The provisioning scripts fix this automatically on `vagrant up`, but if you're on a VM that was already running before this fix, correct it manually:
```bash
echo "nameserver 10.0.2.3" | sudo tee /etc/resolv.conf
```
`10.0.2.3` is the VirtualBox NAT DNS — always available regardless of your host network. This fix does not persist across reboots; it will be re-applied automatically on the next `vagrant up` via the provisioning scripts.

**`fatal: unable to access ... Could not resolve host: github.com`**
DNS is broken — apply the fix above first, then retry `git pull`.

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

## Managing the lab

### Pausing and resuming

```bash
vagrant suspend   # pause both VMs and save state to disk
vagrant resume    # resume from where you left off (fast)
```

Use `suspend` when you're stepping away but plan to come back. The VMs consume significant RAM while running even if idle (~2 GB for Kali, ~200 MB for Debian).

### Shutting down cleanly

```bash
vagrant halt      # graceful shutdown — next `vagrant up` restarts services
```

### Destroying the VMs

```bash
vagrant destroy -f   # delete VMs entirely — next `vagrant up` re-provisions from scratch
```

### Checking VM status

```bash
vagrant status       # shows whether each VM is running, suspended, or off
```

### Re-provisioning without destroying

```bash
vagrant provision debian   # re-run the provisioning script on a running VM
```

Useful when you update `provision/debian.sh` or want to pull the latest code from GitHub onto the VM.
