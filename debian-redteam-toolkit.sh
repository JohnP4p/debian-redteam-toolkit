#!/bin/bash
# =============================================================================
# Curated Red-Team Toolkit Installer — Hardened Debian 13 Minimal
# =============================================================================
#
# WHAT THIS IS
#   A curated, checksum-verified, reasonably hardened tool installer for a
#   minimal Debian 13 box (built with a Qubes template in mind, but works on
#   any fresh Debian 13 minimal install). The goal is to remove decision
#   paralysis around "which distro / which tools / how much hardening" for
#   people who already know what they're doing.
#
# WHAT THIS IS NOT
#   This does not make anyone "nation-state level," and it is not trying to
#   imitate a specific APT group. Tool selection below is informed by public
#   threat-intel reporting (MITRE ATT&CK software pages, CISA/FBI/NSA joint
#   advisories) rather than a generic OSCP/bug-bounty tool list — e.g.
#   Impacket and AD-focused tooling are included because they show up
#   repeatedly in real, documented intrusions (CISA advisory AA22-277A
#   describes Impacket used against a US Defense Industrial Base
#   organization; MITRE ATT&CK S0357 documents its credential-dumping and
#   lateral-movement use). But tooling is scaffolding, not tradecraft — OPSEC
#   discipline, target-specific judgment, and practice are still entirely on
#   the operator.
#
# DESIGN NOTES
#   - Deliberately fewer tools than Kali, on purpose. Loud/broad tools
#     (masscan, aircrack-ng, bettercap, gobuster) are OPTIONAL and OFF by
#     default — real operators avoid broad noisy scanning specifically
#     because it gets detected. Set INSTALL_OPTIONAL_LOUD_TOOLS=1 to include
#     them anyway (e.g. for WiFi/physical engagements).
#   - `set -e` is NOT used globally. Foundational steps (system update, base
#     dependencies) fail fast and hard, on purpose. Individual tool installs
#     fail SOFT — recorded, reported in the final summary, script keeps
#     going — so one changed upstream filename or one GitHub rate-limit hit
#     doesn't kill an otherwise-fine run. Check the summary at the end.
#   - Every GitHub-release binary is checksum-verified when the upstream
#     project publishes a checksums file (most goreleaser-based Go tools do).
#     Sliver's own installer already GPG-verifies its binaries against a
#     BishopFox key, so it isn't wrapped further here.
#   - No NOPASSWD sudo. The operator account gets sudo group membership and a
#     random generated password (saved once, root-only, to
#     /root/.hacklab_redteam_password), with a forced password change on
#     first login.
#
# WHAT WAS NOT VERIFIED END-TO-END
#   This was written and reviewed carefully, including checking current
#   GitHub org/repo paths and official install commands against live
#   documentation. It was NOT run start-to-finish against a live Debian 13
#   box (no network access in the environment this was written in). Upstream
#   projects occasionally rename release assets between versions — if a
#   GitHub-based install fails, the summary at the end names the tool and
#   points you at its releases page so you can fix a one-line regex rather
#   than guess. Run this on a disposable VM/snapshot first, not your only
#   copy of anything, and before you publish it.
#
# AUTHORIZATION
#   Only point any of this at systems/networks you have explicit, documented
#   permission to test.
#
# CONFIG — export these before running to override the defaults:
#   INSTALL_OPTIONAL_LOUD_TOOLS=0   # 1 = also install masscan/aircrack-ng/bettercap/gobuster/amass
#   INSTALL_BLOODHOUND=1            # 0 = skip BloodHound CE (needs Docker + 8GB+ RAM)
#   ENABLE_SSH=0                    # 1 = open + harden sshd (leave at 0 if you drive this box via Qubes dom0 / console — you likely don't need sshd at all)
#   GITHUB_TOKEN=""                 # optional PAT, raises GitHub API rate limit from 60/hr to 5000/hr
#   HARDEN_DISABLE_SWAP=1           # 0 = leave swap alone (set to 0 if this VM is memory-constrained)
#   UPDATE_TOOLS=0                  # 1 = check every already-installed GitHub-release tool against its latest tag and upgrade in place (the "sudo apt upgrade" equivalent for the non-apt tools)
#   DRY_RUN=0                       # 1 = print exactly what the current configuration would do, change nothing, exit
#
# Run as root on a fresh Debian 13 minimal install.
# =============================================================================

set -uo pipefail

INSTALL_OPTIONAL_LOUD_TOOLS="${INSTALL_OPTIONAL_LOUD_TOOLS:-0}"
INSTALL_BLOODHOUND="${INSTALL_BLOODHOUND:-1}"
ENABLE_SSH="${ENABLE_SSH:-0}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
HARDEN_DISABLE_SWAP="${HARDEN_DISABLE_SWAP:-1}"
UPDATE_TOOLS="${UPDATE_TOOLS:-0}"
DRY_RUN="${DRY_RUN:-0}"

HACKLAB_DIR="/opt/hacklab"
BIN_DIR="${HACKLAB_DIR}/bin"
LOG="/var/log/hacklab-setup.log"
PASSWORD_FILE="/root/.hacklab_redteam_password"

FAILED_TOOLS=()
INSTALLED_TOOLS=()
SKIPPED_TOOLS=()

export DEBIAN_FRONTEND=noninteractive

mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

log() {
    local level="$1"; shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*"
}

is_qubes_template() {
    # True when this is being customized as a Qubes TemplateVM (not a plain
    # Debian box). Used to apply Qubes-specific persistence fixes that would
    # be meaningless — harmless, but pointless — anywhere else.
    command -v qubesdb-read >/dev/null 2>&1 || [[ -d /usr/lib/qubes-bind-dirs.d ]]
}

# ----------------------------- PRE-CHECKS -----------------------------
if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: run as root (sudo)." >&2
    exit 1
fi

echo "=================================================================="
echo "This installs and configures tools capable of significant network"
echo "and system impact: scanners, credential-access tooling, a C2"
echo "framework, and tunneling utilities."
echo ""
echo "Use ONLY on systems and networks you are explicitly, contractually"
echo "authorized to test."
echo "=================================================================="
read -r -p "Type 'YES' to continue: " CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
    echo "Aborted."
    exit 1
fi

if [[ "$DRY_RUN" == "1" ]]; then
    cat << SUMMARY

DRY RUN — nothing has been changed. With the current configuration this would:

  System:    update + full-upgrade, install base dependencies
  User:      create 'redteam' (sudo group, random password, forced change on first login)
             $([[ "$ENABLE_SSH" == "1" ]] && echo "sshd: enabled, rate-limited, hardened once a key is present" || echo "sshd: left alone (no inbound ports opened)")
  Hardening: UFW deny-all-inbound, sysctl (ptrace_scope/dmesg_restrict/kptr_restrict/core dumps off),
             security-only unattended-upgrades
             $([[ "$HARDEN_DISABLE_SWAP" == "1" ]] && echo "swap: disabled" || echo "swap: left alone (HARDEN_DISABLE_SWAP=0)")

  Recon/web:      naabu, subfinder, httpx, katana, nuclei, ffuf, nmap
  Priv-esc:       linpeas.sh (PEASS-ng)
  Credential/AD:  impacket, netexec$([[ "$INSTALL_BLOODHOUND" == "1" ]] && echo ", bloodhound-ce (staged via Docker)" || echo " (bloodhound-ce SKIPPED — INSTALL_BLOODHOUND=0)")
  Tunneling:      chisel, ligolo-ng
  C2:             sliver
  Password/web:   hydra, john, sqlmap
  Optional:       $([[ "$INSTALL_OPTIONAL_LOUD_TOOLS" == "1" ]] && echo "masscan, aircrack-ng, bettercap, gobuster, amass (INSTALL_OPTIONAL_LOUD_TOOLS=1)" || echo "SKIPPED (set INSTALL_OPTIONAL_LOUD_TOOLS=1 to include)")

  Every downloaded binary is checksum-verified when upstream publishes one
  (GitHub asset digest preferred, checksums.txt as fallback) — installs that
  fail verification are refused, not installed anyway.

  UPDATE_TOOLS=$UPDATE_TOOLS — $([[ "$UPDATE_TOOLS" == "1" ]] && echo "already-installed tools will be checked against their latest release and upgraded" || echo "already-installed tools are left as-is")

Re-run without DRY_RUN=1 to actually apply this.
SUMMARY
    exit 0
fi

mkdir -p "$BIN_DIR"
chmod 755 "$HACKLAB_DIR"

log INFO "=== HACKLAB SETUP STARTED ==="

# ----------------------------- BASE SYSTEM (fail fast — nothing else works without this) -----------------------------
log INFO "Updating base system..."
if ! apt-get update -qq; then
    echo "ERROR: apt-get update failed — check network/apt sources." >&2
    exit 1
fi
if ! apt-get full-upgrade -y -qq; then
    echo "ERROR: apt-get full-upgrade failed." >&2
    exit 1
fi

log INFO "Installing base dependencies..."
if ! apt-get install -y -qq --no-install-recommends \
    curl wget unzip tar git ca-certificates gnupg lsb-release \
    build-essential jq pipx python3-venv ufw unattended-upgrades \
    docker.io openssl; then
    echo "ERROR: base dependency install failed — check network/apt sources." >&2
    exit 1
fi
# Package name/availability for the compose v2 plugin varies by Debian point
# release, so this one is handled softly rather than failing the whole run.
if ! apt-get install -y -qq --no-install-recommends docker-compose-v2 2>/dev/null; then
    log WARN "docker-compose-v2 not found in apt — 'docker compose' may be unavailable. See https://docs.docker.com/compose/install/linux/ if BloodHound CE fails to start later."
fi

# ----------------------------- CONNECTIVITY PRE-FLIGHT CHECK -----------------------------
# apt-based installs above succeed even with NO general network access, because
# they go through a package-manager-specific proxy (this is the Qubes default
# for TemplateVMs in particular: apt works, but plain HTTPS to arbitrary hosts
# does not, even with a NetVM attached). Everything below this point — GitHub
# releases, pipx, Sliver, BloodHound — needs real outbound HTTPS and will fail
# silently, tool by tool, if that's missing. Catch it once, clearly, here.
if ! curl -fsS --max-time 6 https://api.github.com >/dev/null 2>&1; then
    echo ""
    echo "=================================================================="
    echo "WARNING: can't reach api.github.com."
    echo ""
    echo "apt-based tools already installed fine — they don't need this."
    echo "Everything below (GitHub-release tools, pipx, Sliver, BloodHound)"
    echo "needs general outbound HTTPS and WILL FAIL from here on."
    echo ""
    echo "If this is a Qubes TEMPLATE: templates have no general network"
    echo "access by default, even with a NetVM attached — only a narrow"
    echo "proxy for apt. Qubes' own documented fix is to point standard"
    echo "tools at that same proxy instead of opening the template up:"
    echo ""
    echo "   export HTTP_PROXY=http://127.0.0.1:8082"
    echo "   export HTTPS_PROXY=http://127.0.0.1:8082"
    echo "   export http_proxy=\$HTTP_PROXY https_proxy=\$HTTPS_PROXY"
    echo ""
    echo "...then re-run this script. (Giving the template full direct"
    echo "network access instead also works, but Qubes' own docs call that"
    echo "riskier for a trusted template — the proxy is the safer default.)"
    echo "=================================================================="
    read -r -p "Continue anyway? Only apt-based tools will succeed. (y/N): " NETCONFIRM
    if [[ ! "$NETCONFIRM" =~ ^[Yy]$ ]]; then
        echo "Aborted — fix connectivity and re-run."
        exit 1
    fi
fi

# Independent from the GitHub check above: some proxy/allowlist setups permit
# one and not the other. Impacket and NetExec both come through pip/pipx/uv,
# which talk to PyPI, not GitHub's API — a working GitHub check doesn't
# guarantee this one also passes.
if ! curl -fsS --max-time 6 https://pypi.org >/dev/null 2>&1; then
    echo ""
    echo "WARNING: can't reach pypi.org — Impacket and NetExec (both pip/pipx/uv-based)"
    echo "will fail even if GitHub-based tools above succeeded. Same fix applies if"
    echo "this is a Qubes template: route through the update proxy (see above), or"
    echo "confirm whatever proxy is in use actually allows pypi.org and"
    echo "files.pythonhosted.org, not just github.com."
fi

cat > /etc/profile.d/hacklab.sh << EOF
export PATH="\$PATH:${BIN_DIR}:\$HOME/.local/bin"
EOF
chmod 644 /etc/profile.d/hacklab.sh

# /etc/profile.d/ is only read by LOGIN shells (a real login, or `su -` with
# the dash). Most terminal emulators — and `su redteam` without the dash —
# open a plain interactive shell instead, which never reads it: the tools
# install fine but silently "aren't found" in the terminal someone actually
# opens. /etc/bash.bashrc is read by every interactive bash shell, login or
# not, so this covers that case too.
if ! grep -qF "${BIN_DIR}" /etc/bash.bashrc 2>/dev/null; then
    {
        echo ""
        echo "# hacklab: make installed tools reachable in any interactive shell"
        cat /etc/profile.d/hacklab.sh
    } >> /etc/bash.bashrc
fi

export PATH="${PATH}:${BIN_DIR}:/root/.local/bin"

# ----------------------------- OPERATOR USER (no NOPASSWD) -----------------------------
create_operator_user() {
    if id "redteam" &>/dev/null; then
        log SKIP "user 'redteam' already exists — leaving password/sudo config untouched"
        return 0
    fi
    useradd -m -s /bin/bash redteam
    usermod -aG sudo redteam
    local pass
    pass="$(openssl rand -base64 18)"
    echo "redteam:${pass}" | chpasswd
    chage -d 0 redteam
    ( umask 077; echo "$pass" > "$PASSWORD_FILE" )
    chmod 600 "$PASSWORD_FILE"
    log OK "user 'redteam' created — sudo requires a password (saved to ${PASSWORD_FILE}), forced password change on first login"
}
create_operator_user

# ----------------------------- FIREWALL -----------------------------
configure_firewall() {
    ufw default deny incoming >/dev/null
    ufw default allow outgoing >/dev/null
    if [[ "$ENABLE_SSH" == "1" ]]; then
        if systemctl list-unit-files 2>/dev/null | grep -q '^ssh\.service'; then
            ufw limit ssh >/dev/null
            log OK "SSH allowed and rate-limited"
        else
            log WARN "ENABLE_SSH=1 but openssh-server isn't installed — no firewall rule added. Install it (apt-get install openssh-server) and re-run, or just manage this box via 'qvm-run'/console instead."
        fi
    else
        log INFO "No inbound ports opened (default). If this box is a Qubes AppVM/template you drive from dom0, that's normal and preferred — you likely don't need sshd at all."
    fi
    ufw --force enable >/dev/null
    log OK "UFW enabled: deny all inbound by default"
}
configure_firewall

harden_sshd() {
    [[ "$ENABLE_SSH" == "1" ]] || return 0
    [[ -f /etc/ssh/sshd_config ]] || return 0
    # Note for Qubes templates: /home/redteam/.ssh/authorized_keys, like the
    # rest of /home, won't carry over into AppVMs built from this template
    # (see the pipx comment above) — add the key from inside the actual
    # AppVM you intend to use, not while customizing the template.
    if [[ -s /home/redteam/.ssh/authorized_keys ]]; then
        sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
        sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
        systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
        log OK "sshd hardened: key-only auth, root login disabled"
    else
        log WARN "ENABLE_SSH=1 but no key in /home/redteam/.ssh/authorized_keys — leaving password auth ON so you don't lock yourself out. Add a key, then re-run to harden."
    fi
}
harden_sshd

# ----------------------------- SWAP -----------------------------
# Credential material handled by tools like Impacket/Sliver lives in RAM; if
# it gets paged to swap it can persist on disk well after the process exits.
# Disabling swap removes that leak path entirely. Set HARDEN_DISABLE_SWAP=0
# if this VM is memory-constrained and genuinely needs swap.
harden_swap() {
    if [[ "$HARDEN_DISABLE_SWAP" != "1" ]]; then
        log INFO "swap left as-is (HARDEN_DISABLE_SWAP=0)"
        return 0
    fi
    if swapon --show 2>/dev/null | grep -q .; then
        swapoff -a 2>/dev/null || true
        sed -i '/\sswap\s/s/^/#/' /etc/fstab
        log OK "swap disabled (was active — now off and commented out of /etc/fstab)"
    else
        log INFO "no active swap found — nothing to disable"
    fi
}
harden_swap

# ----------------------------- KERNEL / CORE-DUMP HARDENING -----------------------------
# None of these touch raw-socket or ptrace-based tool behavior in normal use.
cat > /etc/sysctl.d/99-hacklab-hardening.conf << 'EOF'
kernel.yama.ptrace_scope = 1
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
fs.suid_dumpable = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
EOF
sysctl --system >/dev/null 2>&1 || true

cat > /etc/security/limits.d/99-hacklab-nocore.conf << 'EOF'
*               hard    core            0
EOF
log OK "sysctl + core-dump hardening applied"

# ----------------------------- SECURITY-ONLY AUTO UPDATES -----------------------------
# Deliberately NOT a full unattended-upgrade — that can silently break pinned
# tool dependencies. Security-origin patches only, no automatic reboot.
cat > /etc/apt/apt.conf.d/51hacklab-unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
EOF
log OK "unattended-upgrades configured for security patches only"

apt-get clean
apt-get autoremove -y -qq

# ----------------------------- GENERIC GITHUB RELEASE INSTALLER -----------------------------
verify_checksum() {
    # verify_checksum <local_file> <checksums_file_url> <exact_upstream_asset_filename>
    #
    # BUG THIS FIXES: this used to grep the checksums file for the LOCAL temp
    # filename (e.g. naabu.dl) instead of the actual upstream release asset
    # name (e.g. naabu_3.3.0_linux_amd64.zip). Those never match, so this
    # silently fell back to "unverified" on every single tool, every run —
    # the verification was checking nothing while claiming to check something.
    local file="$1" checksums_url="$2" asset_name="$3"
    local expected actual
    # exact match on the filename field, not a substring grep, so a file
    # whose name happens to be a prefix of another one can't match the wrong line
    expected="$(curl -fsSL "$checksums_url" 2>/dev/null | awk -v f="$asset_name" '$2==f{print $1; exit} $NF==f{print $1; exit}')"
    if [[ -z "$expected" ]]; then
        log WARN "no checksum entry for ${asset_name} in ${checksums_url} — installing unverified"
        return 0
    fi
    actual="$(sha256sum "$file" | awk '{print $1}')"
    if [[ "$expected" != "$actual" ]]; then
        log FAIL "checksum MISMATCH for ${asset_name} — expected ${expected}, got ${actual}"
        return 1
    fi
    log OK "checksum verified for ${asset_name} (matched against upstream checksums file)"
    return 0
}

install_github_release_tool() {
    # install_github_release_tool <installed_name> <owner/repo> <asset_regex> <zip|targz|gz|raw> [inner_binary_name]
    local name="$1" repo="$2" pattern="$3" mode="$4" inner="${5:-$1}"
    local bin_path="${BIN_DIR}/${name}"
    local version_file="${bin_path}.version"

    if [[ -x "$bin_path" && "$UPDATE_TOOLS" != "1" ]]; then
        log SKIP "${name} already installed — set UPDATE_TOOLS=1 to check for updates"
        SKIPPED_TOOLS+=("$name")
        return 0
    fi

    local auth=()
    [[ -n "$GITHUB_TOKEN" ]] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")

    local json
    if ! json="$(curl -fsSL "${auth[@]}" -H "Accept: application/vnd.github+json" "https://api.github.com/repos/${repo}/releases/latest")"; then
        if [[ -x "$bin_path" ]]; then
            log WARN "${name} — couldn't check for updates (GitHub API request failed), keeping existing install"
            SKIPPED_TOOLS+=("$name")
            return 0
        fi
        log FAIL "${name} — GitHub API request failed (rate-limited without GITHUB_TOKEN? or network issue)"
        FAILED_TOOLS+=("$name")
        return 1
    fi

    local latest_tag current_tag=""
    latest_tag="$(echo "$json" | jq -r '.tag_name // empty')"
    [[ -f "$version_file" ]] && current_tag="$(cat "$version_file" 2>/dev/null)"

    if [[ -x "$bin_path" ]]; then
        if [[ -n "$latest_tag" && "$current_tag" == "$latest_tag" ]]; then
            log SKIP "${name} already at latest (${latest_tag})"
            SKIPPED_TOOLS+=("$name")
            return 0
        fi
        log INFO "${name} — updating ${current_tag:-unknown version} -> ${latest_tag:-latest}"
    fi

    local asset_url asset_name asset_digest checksum_url
    asset_url="$(echo "$json" | jq -r --arg p "$pattern" '[.assets[] | select(.name | test($p; "i"))][0].browser_download_url // empty')"
    asset_name="$(echo "$json" | jq -r --arg p "$pattern" '[.assets[] | select(.name | test($p; "i"))][0].name // empty')"
    # GitHub now attaches a native sha256 digest to release assets on many repos —
    # prefer that (no separate file to fetch or parse) and only fall back to a
    # published checksums.txt/.sha256 file if this repo doesn't have it.
    asset_digest="$(echo "$json" | jq -r --arg p "$pattern" '[.assets[] | select(.name | test($p; "i"))][0].digest // empty' | sed 's/^sha256://')"
    checksum_url="$(echo "$json" | jq -r '[.assets[] | select(.name | test("checksums\\.txt$|\\.sha256$|\\.sha256sum$"))][0].browser_download_url // empty')"

    if [[ -z "$asset_url" ]]; then
        log FAIL "${name} — no release asset matched pattern '${pattern}' in ${repo}. Upstream naming may have changed; check https://github.com/${repo}/releases/latest"
        FAILED_TOOLS+=("$name")
        return 1
    fi

    local tmp="/tmp/${name}.dl" extract_dir="/tmp/${name}_extract"
    rm -rf "$extract_dir"; mkdir -p "$extract_dir"

    if ! curl -fsSL -o "$tmp" "$asset_url"; then
        log FAIL "${name} — download failed from ${asset_url}"
        FAILED_TOOLS+=("$name")
        return 1
    fi

    if [[ -n "$asset_digest" ]]; then
        local actual_digest
        actual_digest="$(sha256sum "$tmp" | awk '{print $1}')"
        if [[ "$asset_digest" != "$actual_digest" ]]; then
            log FAIL "checksum MISMATCH for ${asset_name} — GitHub-reported digest ${asset_digest}, got ${actual_digest}"
            rm -f "$tmp"; rm -rf "$extract_dir"
            FAILED_TOOLS+=("$name")
            return 1
        fi
        log OK "checksum verified for ${asset_name} (GitHub asset digest)"
    elif [[ -n "$checksum_url" ]]; then
        if ! verify_checksum "$tmp" "$checksum_url" "$asset_name"; then
            rm -f "$tmp"; rm -rf "$extract_dir"
            FAILED_TOOLS+=("$name")
            return 1
        fi
    else
        log WARN "${name} — upstream published no digest or checksums file for this release, installing unverified"
    fi

    case "$mode" in
        zip)   unzip -oq "$tmp" -d "$extract_dir" ;;
        targz) tar -xzf "$tmp" -C "$extract_dir" ;;
        gz)    gunzip -c "$tmp" > "${extract_dir}/${inner}" ;;
        raw)   cp "$tmp" "${extract_dir}/${inner}" ;;
    esac

    local found
    found="$(find "$extract_dir" -type f -name "$inner" | head -1)"
    if [[ -z "$found" ]]; then
        log FAIL "${name} — expected binary '${inner}' not found inside downloaded archive (extraction layout may differ from what this script assumed)"
        rm -f "$tmp"; rm -rf "$extract_dir"
        FAILED_TOOLS+=("$name")
        return 1
    fi

    mv "$found" "$bin_path"
    chmod +x "$bin_path"
    [[ -n "$latest_tag" ]] && echo "$latest_tag" > "$version_file"
    rm -f "$tmp"; rm -rf "$extract_dir"
    log OK "${name} installed (${latest_tag:-unknown version})"
    INSTALLED_TOOLS+=("$name")
    return 0
}

# ----------------------------- RECON / WEB TOOLCHAIN -----------------------------
log INFO "Installing recon/web toolchain..."
install_github_release_tool "naabu"     "projectdiscovery/naabu"     "linux_amd64\.zip$"     zip
install_github_release_tool "subfinder" "projectdiscovery/subfinder" "linux_amd64\.zip$"     zip
install_github_release_tool "httpx"     "projectdiscovery/httpx"     "linux_amd64\.zip$"     zip
install_github_release_tool "katana"    "projectdiscovery/katana"    "linux_amd64\.zip$"     zip
install_github_release_tool "nuclei"    "projectdiscovery/nuclei"    "linux_amd64\.zip$"     zip
install_github_release_tool "ffuf"      "ffuf/ffuf"                  "linux_amd64\.tar\.gz$" targz
# RustScan intentionally NOT installed by default — see README ("Dropped tools").
# naabu already covers the same fast-async-port-scan niche reliably.

# ----------------------------- TUNNELING / PIVOTING -----------------------------
log INFO "Installing tunneling toolchain..."
install_github_release_tool "chisel"    "jpillora/chisel"     "linux_amd64\.gz$"              gz
install_github_release_tool "ligolo-ng" "nicocha30/ligolo-ng" "proxy_.*linux_amd64\.tar\.gz$" targz "proxy"

# ----------------------------- PRIVILEGE ESCALATION ENUMERATION -----------------------------
# The one ATT&CK tactic the original tool list had no real answer for. PEASS-ng
# (linpeas.sh) is the standard, actively-maintained, FOSS choice here — a single
# portable shell script, no compiled binary or archive involved.
log INFO "Installing linpeas.sh (PEASS-ng)..."
install_github_release_tool "linpeas.sh" "peass-ng/PEASS-ng" "^linpeas\.sh$" raw

# ----------------------------- CREDENTIAL / AD TOOLING -----------------------------
# Impacket and NetExec are Python-ecosystem tools, installed via pipx. IMPORTANT:
# installed to ${BIN_DIR}/../pipx rather than the redteam user's $HOME. On a
# Qubes TemplateVM, /home is one of exactly three paths (/home, /usr/local,
# /rw/config) that do NOT carry over from a template to VMs based on it — a
# per-user pipx install would work fine while customizing the template, then
# silently vanish in every AppVM built from it. /opt is not on that list, so
# this is both more correct for Qubes and simpler everywhere else (every user
# can reach these tools, not just redteam).
export PIPX_HOME="${HACKLAB_DIR}/pipx"
export PIPX_BIN_DIR="${BIN_DIR}"
mkdir -p "$PIPX_HOME"

log INFO "Installing Impacket + NetExec via pipx (into ${PIPX_HOME}, not \$HOME)..."
if pipx install impacket >/tmp/impacket.log 2>&1; then
    log OK "impacket installed"
    INSTALLED_TOOLS+=("impacket")
else
    log FAIL "impacket install failed — see /tmp/impacket.log"
    FAILED_TOOLS+=("impacket")
fi

log INFO "Installing NetExec (nxc)..."
# NetExec's dependency chain (commonly `cryptography`) needs to compile a Rust
# extension when no prebuilt wheel matches this platform/Python combination —
# without a compiler present this fails with exactly "can't find Rust compiler"
# / "failed to build wheel". This was the confirmed real cause of a prior
# NetExec install failure (not a network issue). Installed once, here.
if ! command -v rustc >/dev/null 2>&1; then
    apt-get install -y -qq --no-install-recommends rustc cargo \
        || log WARN "could not install rustc/cargo — NetExec's install may still fail below if it needs to compile a Rust extension"
fi
# The "default" pipx git-install is a documented, repeatedly-reported failure
# mode (Pennyw0rth/NetExec issues #165, #252): NetExec pins a specific dev
# commit of Impacket that regularly conflicts with other dependencies (bloodhound,
# dploot, lsassy) during pip's resolution. NetExec's own wiki documents uv as a
# more reliable build path — try that first, fall back to plain pipx only if uv
# itself can't be installed. Neither path is a silent lie: whichever one
# actually produces a working 'nxc' gets logged as such.
NETEXEC_INSTALLED=0
if pipx install uv >/tmp/uv-install.log 2>&1; then
    export UV_TOOL_BIN_DIR="${BIN_DIR}"
    rm -rf /tmp/netexec-src
    if git clone --quiet --depth 1 https://github.com/Pennyw0rth/NetExec /tmp/netexec-src >/tmp/netexec.log 2>&1 \
        && (cd /tmp/netexec-src && "${BIN_DIR}/uv" tool install . >>/tmp/netexec.log 2>&1); then
        log OK "netexec (nxc) installed via uv"
        NETEXEC_INSTALLED=1
    fi
    rm -rf /tmp/netexec-src
else
    log WARN "netexec — could not install uv, falling back to plain pipx (the less reliable path — see /tmp/uv-install.log)"
fi

if [[ "$NETEXEC_INSTALLED" != "1" ]]; then
    if pipx install "git+https://github.com/Pennyw0rth/NetExec" >>/tmp/netexec.log 2>&1; then
        log OK "netexec (nxc) installed via pipx"
        NETEXEC_INSTALLED=1
    fi
fi

if [[ "$NETEXEC_INSTALLED" == "1" ]]; then
    INSTALLED_TOOLS+=("netexec")
else
    log FAIL "netexec install failed via both uv and pipx — see /tmp/netexec.log and /tmp/uv-install.log"
    FAILED_TOOLS+=("netexec")
fi

if [[ "$INSTALL_BLOODHOUND" == "1" ]]; then
    log WARN "BloodHound's own components are commonly flagged as malware by AV/EDR due to their dual-use nature (this is SpecterOps' own documented guidance, not a bug). Run it on a dedicated box; if this box is ever on a corporate network, tell your SOC/CISO first."

    if is_qubes_template; then
        # Same issue as pipx above, for Docker: /var/lib/docker, /var/lib/containerd
        # and /etc/docker are not in the three persistent paths either, so any
        # images/containers/volumes created while customizing the template would
        # vanish in derived AppVMs. Qubes' own supported fix is bind-dirs: declare
        # these paths at the template level so they're bind-mounted from the
        # private volume in every AppVM built from it, same as /home already is.
        mkdir -p /usr/lib/qubes-bind-dirs.d
        cat > /usr/lib/qubes-bind-dirs.d/50-hacklab-docker.conf << 'EOF'
binds+=('/var/lib/docker')
binds+=('/var/lib/containerd')
binds+=('/etc/docker')
EOF
        log OK "Qubes bind-dirs configured for Docker — its data will now persist across AppVMs based on this template, not just this customization session"
    fi

    systemctl enable --now docker >/dev/null 2>&1 || true
    if curl -fsSL https://raw.githubusercontent.com/SpecterOps/bloodhound/main/examples/docker-compose/docker-compose.yml -o "${HACKLAB_DIR}/bloodhound-docker-compose.yml"; then
        log OK "BloodHound CE compose file staged at ${HACKLAB_DIR}/bloodhound-docker-compose.yml — start it with: docker compose -f ${HACKLAB_DIR}/bloodhound-docker-compose.yml up -d  (the generated admin password prints in the compose logs on first run)"
        INSTALLED_TOOLS+=("bloodhound-ce (staged, not auto-started)")
    else
        log FAIL "could not fetch the BloodHound CE compose file"
        FAILED_TOOLS+=("bloodhound-ce")
    fi
else
    log SKIP "BloodHound CE (INSTALL_BLOODHOUND=0)"
fi

# ----------------------------- C2 -----------------------------
log INFO "Installing Sliver C2 (BishopFox) — the official installer GPG-verifies its own binaries..."
if [[ ! -x "${BIN_DIR}/sliver-server" ]]; then
    if curl -fsSL https://sliver.sh/install | bash -s -- --no-client >/tmp/sliver-install.log 2>&1; then
        mv /usr/local/bin/sliver* "${BIN_DIR}/" 2>/dev/null || true
        chmod +x "${BIN_DIR}"/sliver* 2>/dev/null || true
        log OK "sliver installed"
        INSTALLED_TOOLS+=("sliver")
    else
        log FAIL "sliver install failed — see /tmp/sliver-install.log"
        FAILED_TOOLS+=("sliver")
    fi
else
    log SKIP "sliver already installed"
fi

# ----------------------------- BASELINE APT TOOLS -----------------------------
log INFO "Installing baseline apt tools..."
apt-get install -y -qq --no-install-recommends nmap sqlmap hydra john upx-ucl

# ----------------------------- OPTIONAL / LOUD TOOLS (off by default) -----------------------------
if [[ "$INSTALL_OPTIONAL_LOUD_TOOLS" == "1" ]]; then
    log INFO "INSTALL_OPTIONAL_LOUD_TOOLS=1 — installing masscan/aircrack-ng/bettercap/gobuster/amass..."
    apt-get install -y -qq --no-install-recommends masscan aircrack-ng bettercap gobuster
    install_github_release_tool "amass" "owasp-amass/amass" "linux_amd64\.zip$" zip
else
    log INFO "Optional loud/legacy tools skipped (masscan, aircrack-ng, bettercap, gobuster, amass). Set INSTALL_OPTIONAL_LOUD_TOOLS=1 to include them."
fi

apt-get clean
apt-get autoremove -y -qq

# ----------------------------- SUMMARY -----------------------------
echo ""
echo "=================================================================="
echo "SETUP COMPLETE"
echo "=================================================================="
echo "Installed:  ${INSTALLED_TOOLS[*]:-none}"
echo "Skipped (already present): ${SKIPPED_TOOLS[*]:-none}"
if [[ ${#FAILED_TOOLS[@]} -gt 0 ]]; then
    echo "FAILED (check ${LOG} and /tmp/*.log): ${FAILED_TOOLS[*]}"
else
    echo "Failures: none"
fi
echo ""
echo "Operator account: redteam (password required for sudo — no NOPASSWD)"
if [[ -f "$PASSWORD_FILE" ]]; then
    echo "  Initial password saved to ${PASSWORD_FILE} (root-only)."
    echo "  Read it, store it in a password manager, then delete the file."
    echo "  You will be forced to change it on first login."
fi
echo ""
echo "Tools confined to: ${HACKLAB_DIR}"
echo "Log: ${LOG}"
echo ""
echo "Next steps:"
echo "  su - redteam"
echo "  nuclei -update-templates"
echo "  impacket-secretsdump --help   # confirm the pipx install"
echo "  nxc --help                    # confirm the NetExec install"
echo "  sliver-server"
echo "=================================================================="
log INFO "=== HACKLAB SETUP FINISHED ==="
