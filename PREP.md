# Pre-provisioning Checklist

What needs to be done in each repo before the Vagrantfile and provisioning scripts can be written.

---

## Naberius (`naberius-honeypot`)

### 1. Rename default branch to `main` [done]
The current default branch is `feature/honeypot-core`. Rename it to `main` on GitHub so a plain `git clone` works without an explicit `git checkout`.

### 2. Pin Python to 3.12 [done]
`pyproject.toml` and `.python-version` currently require Python 3.14, which is not available in Debian bookworm repos and must be compiled from source. Changing to 3.12 allows installing from backports via `apt` — simpler and faster provisioning.

```toml
# pyproject.toml
requires-python = ">=3.12"
```

```
# .python-version
3.12
```

### 3. Add `.gitkeep` to `data/` [done]
The `data/` directory is gitignored and not created by the repo. Provisioning scripts should not be responsible for knowing the internal layout. Add a `.gitkeep` so the directory exists after clone.

```
data/.gitkeep
```

### 4. Fix Flask host binding in `api/app.py` [done]
Currently runs with `debug=True` and no explicit host, defaulting to `127.0.0.1`. On a VM, the API must be reachable from other machines (dashboard, Vassago if ever split). Change to:

```python
app.run(host="0.0.0.0", port=5000, debug=False)
```

### 5. Add systemd unit files [done]
Both processes must survive reboots and run in the background without a terminal session. Create two unit files inside the repo under `deploy/`:

- `deploy/naberius-honeypot.service` — runs `server.py` (port 2222)
- `deploy/naberius-api.service` — runs `api/app.py` (port 5000)

The provisioning script will copy these to `/etc/systemd/system/` and enable them.

**Assumptions baked in:**
- `User=naberius` — dedicated system user. Change to `vagrant`, `debian`, or whatever user the VM runs as if different.
- `WorkingDirectory=/opt/naberius` — assumed install path. Update if deploying elsewhere.
- The API unit has `After=naberius-honeypot.service` (soft dependency) — it starts after the honeypot but won't fail if the honeypot is down.

---

## Vassago (`vassago-analyzer`)

### 1. Add `.gitkeep` to `data/` and `reports/` [done]
Both directories are expected to exist at runtime but are not present in the repo. Add `.gitkeep` to each:

```
data/.gitkeep
reports/.gitkeep
```

### 2. Add a cron-ready entrypoint script [done]
Create a small shell wrapper `run.sh` at the repo root so the provisioning script can install it as a cron job without hardcoding paths:

```bash
#!/bin/bash
cd /opt/vassago
uv run python main.py --db data/naberius.db --alerts data/alerts.db >> /var/log/vassago.log 2>&1
```

### 3. Document the expected `naberius.db` path [done]
Add a note to the README clarifying that `data/naberius.db` must exist before running — either copied, symlinked, or pointed to via `--db`. This makes the dependency on Naberius explicit for anyone using Vassago standalone.

---

## Shared decision (both repos)

### Database path between Naberius and Vassago
Since both will run on the same Debian VM, the simplest approach is a symlink:

```bash
ln -s /opt/naberius/data/naberius.db /opt/vassago/data/naberius.db
```

This should be done in the provisioning script (`debian.sh`), not in either repo.

---

## Order of execution

1. Fix Naberius (branch rename + Python pin + data dir + Flask host + systemd units)
2. Fix Vassago (data/reports dirs + run.sh + README note)
3. Write `debian.sh` provisioning script
4. Write `kali.sh` provisioning script
5. Write `Vagrantfile`
6. Test end-to-end with `vagrant up`
