# proxmox-iac-lab 
Nederlandse versie: README.nl.md
Proxmox lab as code: OpenTofu, Ansible, Gitea CI — root-cause analysis
# Proxmox IaC Test Lab — Root-Cause Analysis

Incidents from building a Proxmox lab entirely as code: VMs from templates with OpenTofu, configuration with Ansible, CI in Gitea Actions, monitoring with Zabbix and Prometheus/Grafana. Every incident follows the same format: symptom → root cause → fix → lesson.

---

## 1. Locale error (`nl_NL.UTF-8`/`en_US.UTF-8`) — recurring on every new VM

**Symptom:** `perl: warning: Setting locale failed` on almost every new machine (`pve`, `ans01-tl`, `db01`, `mon-lab02`, etc.).

**Root cause:** the SSH client on the admin workstation forwards `LC_*` environment variables (including `nl_NL.UTF-8`) to every server it logs in to. That locale was never generated in the VMs, because the fix was never built into the base templates (9000/9100) — every fix was a one-off, per-VM change.

**Impact:** cosmetic noise in most cases, but in Zabbix it caused an actual blocking error in the web installation wizard (`Locale for language "en_US" is not found`).

**Fix (temporary):** generated `en_US.UTF-8` and `nl_NL.UTF-8` per VM (`dpkg-reconfigure locales`).

**Fix (structural, planned):** generate both locales in templates 9000/9100, so every clone has them from the start.

**Lesson:** a fix you apply by hand on more than one VM belongs in the template or in an Ansible role. Otherwise the error returns on every new machine.

---

## 2. SSH key selection confusion between multiple `Host` aliases

**Symptom:** repeated `Permission denied (publickey)` errors when connecting to `git01`, `mon-lab01` and `runner01`, despite a correctly loaded ssh-agent.

**Root cause, two variants:**
1. A `Host <gitea-ip>` config block, originally meant for Gitea's own SSH server (port 2222, user `git`), also matched normal system SSH connections to the same IP (port 22, the admin user) — SSH matches on the literal address, not on intent. As a result, every system SSH attempt used the wrong port and user.
2. The ssh-agent on `ans01-tl` repeatedly ran empty for no clear reason, despite a configured `.bashrc` autostart.

**Fix:**
1. The conflicting `Host` block was turned into a separate alias (`Host gitea-ssh`) that no longer matches the bare IP address — the Git remote URL was changed accordingly.
2. No structural cause was found for the agent running empty; the recurring pattern is recorded as an open item.

**Lesson:** give every SSH service its own alias instead of a block on an IP address. `ssh -G <host>` shows which settings actually apply to a connection.

---

## 3. Gitea `app.ini` template overwrote runtime-generated secrets (config drift)

**Symptom:** after adding an `[actions]` section to the Ansible template and re-running the playbook, the Gitea installation wizard unexpectedly reappeared — a sign that Gitea believed it had never been installed.

**Root cause:** the original Ansible template for `app.ini` only contained the settings that the Ansible role set *explicitly*. Sections that Gitea itself had generated during the first-run wizard (`INTERNAL_TOKEN`, `JWT_SECRET`, `INSTALL_LOCK`, `WORK_PATH`, `[mailer]`, `[service]`, `[openid]`, etc.) were not in the template. Because `ansible.builtin.template` overwrites the target file **completely**, all configuration added by Gitea itself disappeared on every playbook run.

**Why this was dangerous:** `INSTALL_LOCK` disappeared too, so Gitea thought it had to be installed again — one wrong click on "Install Gitea" could have damaged the existing database.

**Fix (structural):**
- The current runtime-generated values of `INTERNAL_TOKEN` and `JWT_SECRET` were taken from `/etc/gitea/app.ini` and stored in `ansible-vault` (not regenerated — the existing, working values were kept).
- The template was extended with all sections Gitea needs, with the secrets as explicit, vault-driven variables.
- `INSTALL_LOCK = true` was added to the template as a fixed value.

**Lesson:** an Ansible template for an application that also generates or changes its own configuration must contain **all** fields the application expects — not only the fields the administrator set deliberately. Secrets the application generates itself should be "adopted" into the vault as soon as possible, instead of letting the application invent them again on every run.

---

## 4. PostgreSQL/Zabbix/act_runner: `become_user` fails with a chmod error on Debian 13

**Symptom:** the same error repeatedly (three times, in three different roles): `chmod: invalid mode: 'A+user:<user>:rx:allow'`, on every Ansible task that used `become_user` to run as an unprivileged user (`postgres`, `zabbix`, `act_runner`).

**First analysis (incorrect):** "the filesystem does not support ACLs".

**Root cause (corrected, not yet tested in the lab):** when Ansible runs a task as another, unprivileged user, that user must be able to read the temporary module files. Ansible first tries `setfacl` for this. That tool is in the `acl` package, which is not part of the Debian 13 cloud image. Ansible then falls back to other methods, the last one being a `chmod A+…` syntax that GNU `chmod` does not know. So the error message is about the missing package, not about the filesystem.

**Fix:**
- Temporary (applied three times): `become: true` (root) with an explicit `sudo -u <user>` inside the shell command itself.
- Structural (next step): install the `acl` package in the base role or template, and test whether `become_user` then works without the workaround.

**Lesson:** look up an error message in the documentation before assuming a cause. The first analysis was an assumption, and the workaround hid that three times.

---

## 5. PostgreSQL: `listen_addresses` change not active before later tasks

**Symptom:** `tofu init` with the PostgreSQL backend returned `connection refused`, even though the Ansible playbook had reported that `listen_addresses = '*'` was set.

**Root cause:** the service restart (via the `notify` handler) by default only happens at the **end** of an Ansible playbook, not right after the task that made the change. Later tasks in the same playbook (creating the database and user) therefore still connected to the old, not-yet-restarted PostgreSQL instance — and when the state migration was attempted from another host (`ans01-tl`), the service was still listening only on `localhost`.

**Fix:** added an `ansible.builtin.meta: flush_handlers` task directly after the service start task, which forces the pending handler restart before later tasks continue.

**Lesson:** "changed" means the config file was modified, not that the service is using the new setting. If later tasks depend on a restart, use `flush_handlers`. Then check with `ss -tlnp` that the service is actually listening on the right address.

---

## 6. Zabbix-specific installation problems (several, cumulative)

A series of separate, individually small problems during the Zabbix installation:

1. **Wrong PHP version assumption**: the role referred to `php8.2-fpm`, but Debian 13 ships with **PHP 8.4** by default. → Hardcoded to the correct version.
2. **Schema import failed silently**: `zcat ... | psql ...` in a `shell` task reported success even though the source file did not exist (wrong path: `/usr/share/zabbix/sql-scripts/` instead of the actual `/usr/share/zabbix-sql-scripts/`). Cause: in a pipe, bash by default only checks the exit code of the *last* command (`psql`), not of `zcat`. → Path corrected, and `set -o pipefail` added so that a failure anywhere in the pipe fails the whole task.
3. **PostgreSQL option missing in the setup wizard**: the `php8.4-pgsql` extension was not installed. → Added to the package list.
4. **`public` schema permission error** (`permission denied for schema public`): since PostgreSQL 15, ordinary users no longer get automatic CREATE rights on the `public` schema. → Added an explicit `GRANT ALL ON SCHEMA public` task.
5. **Password mismatch at first vault integration**: the `CREATE ROLE ... IF NOT EXISTS` task does not change the password if the role already existed with an older (placeholder) password. → Added a separate, always-run `ALTER ROLE ... PASSWORD` task, so the password matches the vault on every run.

**Common lesson:** recently upgraded software (Zabbix 7.0, PostgreSQL 15+) often brings changed paths and behaviour compared to older, widely used installation guides — verify explicitly instead of relying on familiar patterns from earlier versions.

---

## 7. `act_runner` download: outdated/moved release URL

**Symptom:** `HTTP Error 404: Not Found` when downloading the `act_runner` binary from `gitea.com/gitea/act_runner/releases/...`.

**Root cause:** the project was partly renamed (from `act_runner` to `runner`, from version 2.x), with an unconfirmed new URL structure. The older, stable 0.2.x series turned out to be reliably available via another domain: `dl.gitea.com/act_runner/`.

**Fix:** switched back to the known, confirmed-working version (0.2.13) via the correct domain, instead of guessing the newest, uncertain URL structure.

**Lesson:** for third-party release assets, verify the actual releases page and download structure instead of extrapolating a download pattern from another, outdated source.

---

## 8. CI containers: PEP 668 blocks system-wide `pip install`

**Symptom:** `error: externally-managed-environment` on `pip install ansible-lint` inside a Gitea Actions workflow.

**Root cause:** modern Debian/Ubuntu-based container images apply PEP 668, a Python-wide protection against accidentally overwriting system Python packages.

**Fix:** added `--break-system-packages` to all `pip install` commands in the CI workflow — the same pattern already used on the VMs themselves.

**Lesson:** in a throwaway container, `--break-system-packages` is an acceptable quick fix, but it is still a workaround. Cleaner is a venv or a custom CI image with the tools already installed. That is a next step.

---

## 9. Slow `tofu destroy` for temporary test VMs (7+ minutes)

**Symptom:** the "destroy" step of the first ephemeral-test CI run hung for **more than 7 minutes**, compared to a few seconds in an earlier manual test.

**Root cause:** by default, OpenTofu's Proxmox provider requests a **graceful ACPI shutdown** via the guest agent on destroy and waits patiently for the VM to shut itself down (`stop_on_destroy = false`, the default). When the guest agent responds slowly (for example right after an Ansible run that installed packages), that graceful shutdown takes much longer than expected.

**Fix:** added `stop_on_destroy = true` to the resource definition of the temporary test VMs — this forces a fast, hard stop. Throwaway VMs do not need a graceful shutdown; speed matters more.

**Side incident:** while debugging this slow destroy, the workflow run was mistakenly taken as "finished" while it was still running, which left an orphaned VM (`ci-test-255`) that had to be cleaned up by hand on the Proxmox host. Lesson: with a long-running, unclear CI step, first verify the actual state (e.g. `sudo qm list` on the hypervisor) before starting a new run.

---

## Recurring patterns — summary

Some types of errors came back several times, which makes them worth remembering as general lessons:

1. **`become_user` without the `acl` package** → install `acl` in the base role; look up error messages first instead of assuming a cause.
2. **Templates that overwrite application-generated configuration** → always inventory the complete, current configuration of a fresh installation before writing an Ansible template, not only the fields you set yourself.
3. **Outdated download URLs and version numbers** → for every new service, check the current, official releases page first instead of relying on familiar patterns.
4. **SSH key and `Host` config conflicts** → use specific, non-overlapping `Host` aliases instead of generic IP-based blocks when a host offers several SSH services or ports.
5. **Silent failures in shell pipes** → `set -o pipefail` as a standard habit in every `ansible.builtin.shell` command with a pipe.
6. **Manual fixes per VM** → whatever is done by hand more than once belongs in the template or in a role.
