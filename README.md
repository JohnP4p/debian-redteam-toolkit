# debian-redteam-toolkit

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![Status](https://img.shields.io/badge/status-experimental-orange)
![Platform](https://img.shields.io/badge/platform-Debian%2013-A81D33)

A curated, checksum-verified, reasonably hardened tool installer for a minimal Debian 13 box — built with a Qubes template in mind, but works on any fresh Debian 13 minimal install.

## Table of contents

- [Why this exists](#why-this-exists)
- [What this is (and isn't)](#what-this-is-and-isnt)
- [Responsible use](#responsible-use)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [What gets installed](#what-gets-installed)
- [Hardening applied](#hardening-applied)
- [Troubleshooting](#troubleshooting)
- [On tool selection and ATT&CK tactics](#on-tool-selection-and-attck-tactics)
- [On the checksum bug](#on-the-checksum-bug)
- [On "enterprise-grade"](#on-enterprise-grade)
- [Known limitations](#known-limitations)
- [Contributing](#contributing)
- [License](#license)

## Why this exists

Most people looking for a leaner alternative to Kali either burn hours writing their own install script, or spend that time bikeshedding "which distro, which tools, how much hardening" instead of practicing. This exists to remove that decision paralysis: a curated, checksum-verified baseline instead of hundreds of tools with a fingerprint every SOC has already seen.

## What this is (and isn't)

Tool selection is informed by public threat-intel reporting — MITRE ATT&CK software pages and CISA/FBI/NSA joint advisories — rather than a generic OSCP/bug-bounty tool list. For example:

- **CISA Advisory AA22-277A** documents Impacket used by APT actors against a US Defense Industrial Base organization.
- **MITRE ATT&CK S0357** documents Impacket's credential-dumping and lateral-movement (`wmiexec`) capabilities, with citations to real, named intrusions.

That said: this does not make anyone "nation-state level," and it isn't trying to imitate a specific APT group. Tooling is scaffolding, not tradecraft. OPSEC discipline, target-specific judgment, and practice are still entirely on the operator — no script provides those.

It's also deliberately smaller than Kali. Loud, broad tools (masscan, aircrack-ng, bettercap, gobuster) are optional and off by default, because sophisticated operators generally avoid broad noisy scanning — it gets detected.

## Responsible use

This project exists to help skilled, authorized people test security — not to help anyone break the law.

- Only use these tools against systems and networks you **own**, or have **explicit, documented authorization** to test (a signed scope of work, a bug bounty program's published rules, or your own lab).
- Unauthorized access to computer systems is illegal in most jurisdictions, regardless of intent. Get authorization *in writing* before you touch anything — not after.
- The author does not support, endorse, or take responsibility for misuse of this software. If it's used to harm someone or access something without permission, that responsibility sits with the person who did it, not with this project.
- If you're new to this: get your scope in writing, keep it, and follow it exactly. Scope creep — "just checking one more thing" outside what was agreed — is how a legal engagement turns into a crime. When in doubt, stop and ask the client, don't assume.
- Several of the tools listed below (BloodHound in particular) are routinely flagged as malware by antivirus/EDR software because of their dual-use nature. That's expected, not a bug — but it's also a reason to run this on a dedicated, isolated machine and never on infrastructure you don't fully control.

By using this software, you agree to use it only for lawful, authorized purposes.

## Prerequisites

- A fresh Debian 13 minimal install (VM, Qubes template, bare metal — your call)
- Root access
- **General outbound internet access during setup** (GitHub, PyPI, Docker Hub, sliver.sh) — not just apt access

**If you're building this on a Qubes TemplateVM:** templates have no general network access by default, even with a NetVM attached — only a narrow proxy for `apt`. The script detects this early and tells you what to do, but the short version is Qubes' own documented fix — route standard tools through the same update proxy instead of opening the template up:
```bash
export HTTP_PROXY=http://127.0.0.1:8082 HTTPS_PROXY=http://127.0.0.1:8082
export http_proxy=$HTTP_PROXY https_proxy=$HTTPS_PROXY
```
then run the script in that same shell.

## Installation

```bash
git clone https://github.com/JohnP4p/debian-redteam-toolkit.git
cd debian-redteam-toolkit
chmod +x debian-redteam-toolkit.sh
sudo ./debian-redteam-toolkit.sh
```

The script will ask for explicit confirmation before installing anything. When it finishes, **open a brand-new terminal session** (or `su - redteam`, with the dash) before testing the installed tools — see [Troubleshooting](#troubleshooting) if commands still aren't found.

## Configuration

Set these as environment variables before running (all optional — sensible defaults are used otherwise):

| Variable | Default | Meaning |
|---|---|---|
| `INSTALL_OPTIONAL_LOUD_TOOLS` | `0` | `1` = also install masscan, aircrack-ng, bettercap, gobuster, amass (WiFi/physical engagements) |
| `INSTALL_BLOODHOUND` | `1` | `0` = skip BloodHound CE (needs Docker + 8GB+ RAM) |
| `ENABLE_SSH` | `0` | `1` = open and harden sshd. Leave at `0` if you drive this box via Qubes dom0/console — you likely don't need sshd at all |
| `GITHUB_TOKEN` | unset | Optional personal access token, raises the GitHub API rate limit from 60/hr to 5000/hr |
| `HARDEN_DISABLE_SWAP` | `1` | `0` = leave swap alone, if this VM is memory-constrained |
| `UPDATE_TOOLS` | `0` | `1` = check every already-installed GitHub-release tool against its latest tag and upgrade in place — the `apt upgrade` equivalent for the non-apt tools |
| `DRY_RUN` | `0` | `1` = print exactly what the current configuration would do, change nothing, exit |

Preview before touching anything:
```bash
sudo DRY_RUN=1 ./debian-redteam-toolkit.sh
```

Example:
```bash
sudo INSTALL_OPTIONAL_LOUD_TOOLS=1 ENABLE_SSH=1 ./debian-redteam-toolkit.sh
```

## Updating

The apt-based tools update the normal way (`apt upgrade`). The GitHub-release tools (naabu, subfinder, ffuf, rustscan, chisel, ligolo-ng, etc.) don't auto-update on their own — by default, re-running the script just fills in anything missing and leaves existing installs alone. To check all of them against their latest upstream release and upgrade in place:

```bash
sudo UPDATE_TOOLS=1 ./debian-redteam-toolkit.sh
```

Each tool's installed release tag is tracked in a small `.version` file next to its binary in `/opt/hacklab/bin/`, so this only re-downloads what's actually changed. Sliver and BloodHound CE aren't covered by this flag — update Sliver by re-running its own installer, and update BloodHound by re-pulling the compose file's images (`docker compose -f bloodhound-docker-compose.yml pull`).

## What gets installed

**Recon / web:** naabu, subfinder, httpx, katana, nuclei (ProjectDiscovery), ffuf, nmap

**Privilege escalation enumeration:** linpeas.sh (PEASS-ng)

**Credential access / AD:** Impacket (via pipx), NetExec (via pipx — the actively maintained CrackMapExec successor), BloodHound CE (via Docker Compose, staged but not auto-started)

**Tunneling / pivoting:** Chisel, ligolo-ng

**C2:** Sliver (BishopFox)

**Password / web auth testing:** hydra, John the Ripper, sqlmap

**Packing:** upx-ucl

**Optional, off by default:** masscan, aircrack-ng, bettercap, gobuster, amass — set `INSTALL_OPTIONAL_LOUD_TOOLS=1`

## Hardening applied

UFW (deny all inbound by default), sysctl hardening (`ptrace_scope`, `dmesg_restrict`, `kptr_restrict`, disabled core dumps, reverse-path filtering), swap disabled by default (credential material these tools handle lives in RAM — swap is a path for it to persist to disk), security-only unattended-upgrades (no silent full-upgrade, no auto-reboot), a non-root operator account with real sudo (no `NOPASSWD`), and optional sshd hardening (key-only auth, no root login — only applied once a key is confirmed present, so you can't lock yourself out).

**Deliberately left out, on purpose:**
- **MAC address randomization** — doesn't do anything meaningful inside a Qubes AppVM/template, since it gets a virtual interface from its NetVM rather than talking to physical hardware directly. It belongs at the `sys-net` layer in Qubes (or in NetworkManager config, if you're not on Qubes), not here.
- **Full-disk encryption** — a partition-time decision, not something a post-install script can safely retrofit. If you used Qubes' installer with its default LUKS encryption, this is already covered at the dom0/storage layer for every template and VM on the system.

Both are real hardening measures — they just don't belong in *this* script, and bolting them on anyway would be checkbox-hardening that doesn't actually help.

## Qubes template/AppVM persistence — read this if you're on Qubes

Qubes' template model is not "just another Linux box," and it caused two real bugs that were found and fixed by actually researching the architecture rather than assuming:

**Every AppVM built from a template gets an independent `/home`.** Per Qubes' own docs, exactly three paths persist per-AppVM and are *not* inherited from the template: `/home`, `/usr/local`, `/rw/config`. Everything else — including `/opt`, `/etc`, and the rest of the root filesystem — comes from the template as a shared, read-only snapshot. This script installs almost everything under `/opt/hacklab`, so it survives that boundary correctly. **Impacket and NetExec did not** — pipx's default install location is `$HOME/.local`, so installing them for the `redteam` user while customizing the template meant they'd silently disappear in every AppVM built from it. Fixed: both now install via `PIPX_HOME`/`PIPX_BIN_DIR` pointed at `/opt/hacklab`, same as everything else.

**Docker has the identical problem.** `/var/lib/docker`, `/var/lib/containerd`, and `/etc/docker` aren't in the three persistent paths either, so any BloodHound CE images/containers/volumes built while customizing the template would vanish the same way. Fixed: on a detected Qubes template, the script now declares these paths via Qubes' own `qubes-bind-dirs` mechanism (`/usr/lib/qubes-bind-dirs.d/`) before enabling Docker, so they're bind-mounted from the private volume in every derived AppVM instead of living on the ephemeral template snapshot. This is a no-op (skipped entirely) on non-Qubes Debian, where `/var/lib/docker` already persists normally.

**SSH keys have the same caveat, if you use `ENABLE_SSH=1`:** `/home/redteam/.ssh/authorized_keys` doesn't carry over either. Add a key from inside the actual AppVM you intend to use it in, not while customizing the template.

**General rule for anyone extending this script on Qubes:** if you add something that writes outside `/opt`, `/etc`, or one of the three persistent paths, it will work fine while you're customizing the template and then quietly not exist in any AppVM based on it. That mismatch — works during setup, missing at actual use — is a very easy trap, and is almost certainly what caused earlier bug reports on this project. If something installs somewhere unfamiliar, check where it landed against this list before assuming it's broken in some other way.

## Troubleshooting

**Installed tools give no output, or "command not found"**

This is almost always a shell PATH issue, not a failed install. `/etc/profile.d/` (where the PATH update lives) is only read by *login* shells — a plain terminal window, or `su redteam` without the dash, never sources it, so tools that installed correctly still seem to "not exist." The script also writes the same PATH line to `/etc/bash.bashrc`, which every interactive shell reads regardless of login status — but to confirm what's actually going on:

```bash
ls -la /opt/hacklab/bin/                          # binaries installed via apt/GitHub
sudo -u redteam ls -la /home/redteam/.local/bin/  # impacket / netexec, installed via pipx
grep -E "FAIL|ERROR" /var/log/hacklab-setup.log   # anything that actually failed to install
/opt/hacklab/bin/sliver-server -h                 # bypass PATH entirely to test directly
sudo -u redteam /home/redteam/.local/bin/nxc --help
```

If the direct-path calls work, it's a PATH/shell issue — a genuinely new login session (`su - redteam`, with the dash, or a reboot) resolves it. If a binary isn't there at all, check the log for the real failure and re-run the script — it's idempotent, so it only retries what's missing.

**Most or all non-apt tools fail to download; script warns it can't reach api.github.com or pypi.org**

This is a connectivity problem, not a script bug — apt-based tools install through a package-manager-specific path, but GitHub/pip-pipx-uv/Sliver/BloodHound all need genuine outbound HTTPS, and GitHub and PyPI reachability are checked (and can fail) independently — a proxy or allowlist that permits one doesn't necessarily permit the other. On Qubes TemplateVMs this is expected by design (see [Prerequisites](#prerequisites)); on anything else, check your NetVM/firewall/DNS the normal way. Impacket and NetExec specifically need pypi.org and files.pythonhosted.org reachable, not just github.com.

**NetExec install fails with "can't find Rust compiler" / "failed to build wheel"**

Confirmed real cause, not a guess: one of NetExec's dependencies (commonly `cryptography`) needs to compile a Rust extension when no prebuilt wheel matches your platform/Python combination, and no Rust compiler was present to do it. Fixed by installing `rustc`/`cargo` via apt right before the NetExec step. If you're running an older copy of this script, `sudo apt-get install rustc cargo` before re-running gets you the same fix.

**sliver-server (or anything else that opens a listener) only works as root, not as redteam**

Almost certainly privileged ports, not a script bug: binding a listener below port 1024 — 443 or 80, the natural choice for an HTTPS-mimicking C2 profile — needs root on Linux by default. The script now grants `sliver-server` the `CAP_NET_BIND_SERVICE` capability specifically (`setcap cap_net_bind_service=+ep`), so it can bind those ports as `redteam` without needing full root for the whole process. If you're on an older copy: `sudo setcap 'cap_net_bind_service=+ep' /opt/hacklab/bin/sliver-server`. Ports 1024 and above already worked as `redteam` either way — this only affects the low ones.

**A GitHub-based tool install fails with "no release asset matched pattern"**

Upstream projects occasionally rename release assets between versions. Matching is case-insensitive (a real report of `Linux` vs. `linux` prompted that), so this is a genuine naming change, not a casing mismatch. The error names the tool and the repo — check its `/releases/latest` page, compare the actual asset filename to the regex in `install_github_release_tool` for that tool, and adjust. This is expected maintenance for a script that tracks 10+ independently-versioned upstream projects, not a sign that something is fundamentally broken.

## On tool selection and ATT&CK tactics

If you map the tool list against MITRE ATT&CK tactics, most are covered: reconnaissance, execution, credential access, discovery, lateral movement, C2. Two are deliberately not, for different reasons:

- **Persistence** has no dedicated tool because persistence is mostly technique, not tooling — registry run keys, scheduled tasks, service creation, C2-implant-level persistence (which Sliver already supports). Bolting on a separate "persistence tool" just to fill the category would be checkbox-completeness, not a real capability gain.
- **Impact** (data destruction, DoS, ransomware-style encryption) has no tool on purpose. That's not a gap — actually causing destructive impact is outside standard authorized-engagement scope unless it's an explicit, narrow, written part of the ROE, and this project isn't going to make that easier by default.

**Privilege escalation enumeration** *was* a real gap, raised directly — fixed by adding linpeas.sh (PEASS-ng), the standard actively-maintained FOSS choice for that specific tactic.

**Dropped: RustScan.** It kept failing to install, and the cause turned out to be more fundamental than a regex — RustScan's own README now recommends Docker or a package manager over the raw releases-page binary, and a maintainer comment on a recent release ("this should auto-build and distribute — if it doesn't, let me know!") suggests the automated pipeline that attaches those binaries isn't fully reliable release-to-release. naabu already covers the same fast-async-port-scan niche through a project with a consistently reliable release process, so this isn't a loss — it's removing the single most fragile dependency in the list instead of keeps re-patching a regex against a moving, admittedly-inconsistent target. If you specifically want RustScan, `cargo install rustscan` is the method its own maintainers actually recommend.

## On the checksum bug

An earlier version of this script claimed to checksum-verify every download but never actually did — it compared checksums against the *local temp filename* it chose for convenience (`naabu.dl`) instead of the real upstream release filename (`naabu_3.3.0_linux_amd64.zip`), so the lookup could never match and it silently fell back to "unverified" on every single tool, every run. Calling that "checked" was overclaiming, and it was flagged as such. Fixed now: verification prefers GitHub's own native per-asset SHA256 digest when a repo has one, falls back to matching the *exact* upstream filename in a published checksums file otherwise, and both paths were tested against synthetic data proving the old lookup failed and the new one succeeds before this was called done.

## On "enterprise-grade"

Handed a full production-readiness checklist for this project (functionality, reliability, security, code quality, testing, observability, config/deployment, data handling) — most of it is written for a different class of software: long-running services, data pipelines, things with databases and queues and concurrent callers. A chunk of it doesn't map onto a one-shot root setup script no matter how carefully it's built — there's no database to transaction against, no queue to dead-letter into, no concurrent callers to distributed-lock against, no meaningful load-test for a script that runs once per box.

What *does* transfer, and is either already here or added this round: idempotency, dry-run mode, no hardcoded secrets, checksum verification that actually verifies, graceful per-tool failure instead of one hard crash, clear final success/failure summary, retry-worthy vs. fatal errors handled differently (rate limits and per-tool 404s don't kill the run; a broken apt source does). What's reasonably still missing and would be worth real effort: automated tests that don't require a live Debian box (hard, for a script whose entire job is making real system changes), and a CI pipeline actually running shellcheck/lint on every change instead of manual review.

The honest path from here is the one already in motion: real runs on real Qubes templates, real output pasted back, real fixes — not a checklist chased in the abstract.

## Known limitations

This was researched and written carefully — GitHub org/repo paths and official install commands were checked against live upstream documentation — but no single script can guarantee it stays correct forever against independently-versioned upstream projects. If something breaks, the script is designed to fail per-tool with a clear message rather than silently or catastrophically, and the summary at the end tells you exactly what to fix.

**Run this on a disposable VM/snapshot, not your only copy of anything, before you rely on it for real work.**

## Contributing

Issues and pull requests are welcome — especially reports of broken asset-matching patterns, hardening suggestions, or testing on setups other than Qubes-hosted Debian 13. If you're not comfortable reading bash, testing the script end-to-end and reporting what did or didn't work is just as valuable as a code contribution.

## License

MIT — see [LICENSE](LICENSE).

---

**A note on how this was built:** the code and documentation in this repository were written with AI assistance (Claude, Anthropic) and reviewed by a human maintainer before publishing. This is an experimental project — tested, but not exhaustively, and not across every possible environment. Read the code before you run it with root on anything that matters, and please open an issue if something breaks.
