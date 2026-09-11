#!/bin/bash

#############################################################################
# Jito-Solana Validator — Complete Setup Script
# Run as: sudo bash jito-full-setup.sh [JITO_TAG] [NETWORK]
#
# Examples:
#   sudo bash jito-full-setup.sh v3.1.9-jito mainnet
#   sudo bash jito-full-setup.sh v3.1.9-jito testnet
#
# Env overrides:
#   JITO_USER          — system user to create (default: ubuntu)
#   JITO_REPO          — git repo to clone (default: official jito-foundation)
#   BAM_REGION         — Jito BAM region: frankfurt|amsterdam|ny|dallas|london|singapore|tokyo|slc|dublin
#   ENABLE_LTO         — set to "true" for LTO build (slower, ~5-10% faster binary)
#   TELEGRAM_BOT_TOKEN — optional Telegram bot token for sync alerts
#   TELEGRAM_CHAT_ID   — optional Telegram chat ID for sync alerts
#
# Requires: Ubuntu 22.04+ or Debian 11+, root/sudo
#############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

#############################################################################
# CONFIGURATION — edit or override via env before running
#############################################################################

NEW_USER="${JITO_USER:-ubuntu}"
JITO_TAG="${1:?Usage: sudo bash jito-full-setup.sh <version> <network>  e.g. v3.1.9-jito mainnet}"
NETWORK="${2:-mainnet}"

# Official Jito-Foundation repo (override with JITO_REPO env var if needed)
JITO_REPO="${JITO_REPO:-https://github.com/jito-foundation/jito-solana.git}"
JITO_REPO_DIR="jito-solana"

# LTO build: slower (~30 min) but ~5-10% faster binary
ENABLE_LTO="${ENABLE_LTO:-false}"

if [[ "$NETWORK" != "testnet" && "$NETWORK" != "mainnet" ]]; then
    log_error "NETWORK must be 'testnet' or 'mainnet', got: $NETWORK"
    exit 1
fi

log_info "Jito-Solana tag : $JITO_TAG"
log_info "Repo            : $JITO_REPO"
log_info "Network         : $NETWORK"
log_info "User            : $NEW_USER"

# --- SSH public keys ---
# Add your own SSH public key(s) here before running.
# Example: "ssh-ed25519 AAAA... user@host"
SSH_PUBLIC_KEYS=(
    # "ssh-ed25519 AAAA... your-key-here"
)

# Solana keypairs — paste your JSON key content to skip throwaway generation
# Example: STAKED_IDENTITY_KEY='[1,2,3,...,64]'
STAKED_IDENTITY_KEY="${STAKED_IDENTITY_KEY:-}"
SECONDARY_IDENTITY_KEY="${SECONDARY_IDENTITY_KEY:-}"
VOTE_ACCOUNT_KEY="${VOTE_ACCOUNT_KEY:-}"

# Optional SSH private key. The script derives and authorizes its public key,
# then shreds the private key by default.
SSH_PRIVATE_KEY="${SSH_PRIVATE_KEY:-}"
SSH_PRIVATE_KEY_SHRED_AFTER_INSTALL="${SSH_PRIVATE_KEY_SHRED_AFTER_INSTALL:-true}"

# --- Telegram alerts (optional) ---
# Set via env: export TELEGRAM_BOT_TOKEN=... TELEGRAM_CHAT_ID=...
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

send_telegram() {
    local message="$1"
    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d chat_id="${TELEGRAM_CHAT_ID}" \
            -d text="${message}" \
            -d parse_mode="HTML" > /dev/null 2>&1
    fi
}

# --- Network-specific config ---
if [ "$NETWORK" = "testnet" ]; then
    ENTRYPOINTS=(
        "entrypoint.testnet.solana.com:8001"
        "entrypoint2.testnet.solana.com:8001"
        "entrypoint3.testnet.solana.com:8001"
    )
    KNOWN_VALIDATORS=(
        "5D1fNXzvv5NjV1ysLjirC4WY92RNsVH18vjmcszZd8on"
        "dDzy5SR3AXdYWVqbDEkVFdvSPCtS9ihF5kJkHCtXoFs"
        "Ft5fbkqNa76vnsjYNwjDZUXoTWpP7VYm3mtsaQckQADN"
        "eoKpUABi59aT4rR9HGS3LcMecfut9x7zJyodWWP43YQ"
        "9QxCLckBiJc783jnMvXZubK4wH86Eqqvashtrwvcsgkv"
    )
    GENESIS_HASH="4uhcVJyU9pJkvQyS88uRDiswHXSCkY3zQawwpjk2NsNY"
    METRICS_DB="tds"
    METRICS_USER="testnet_write"
    METRICS_PASS="c4fa841aa918bf8274e3e2a44d77568d9861b3ea"
    BAM_REGION="${BAM_REGION:-dallas}"
    BAM_URL="http://${BAM_REGION}.testnet.bam.jito.wtf"
    BLOCK_ENGINE_URL="https://${BAM_REGION}.testnet.block-engine.jito.wtf"
    TIP_PAYMENT_PUBKEY="GJHtFqM9agxPmkeKjHny6qiRKrXZALvvFGiKf11QE7hy"
    TIP_DISTRIBUTION_PUBKEY="DzvGET57TAgEDxvm3ERUM4GNcsAJdqjDLCne9sdfY4wf"
    MERKLE_ROOT_AUTHORITY="7T4inmPmtNBX3MhLwJ9hFsSMnGJYYkKioVABSNTWVRuS"
    declare -A NTP_SERVERS=(
        ["dallas"]="ntp.dallas.jito.wtf"
        ["ny"]="ntp.dallas.jito.wtf"
        ["slc"]="ntp.slc.jito.wtf"
    )
    NTP_SERVER="${NTP_SERVERS[$BAM_REGION]:-ntp.dallas.jito.wtf}"
    declare -A SHRED_RECEIVERS=(
        ["dallas"]="141.98.218.12:1002"
        ["ny"]="64.130.35.224:1002"
        ["slc"]="64.130.53.8:1002"
    )
    SHRED_RECEIVER="${SHRED_RECEIVERS[$BAM_REGION]}"
    COMMISSION_BPS="0"
else
    ENTRYPOINTS=(
        "entrypoint.mainnet-beta.solana.com:8001"
        "entrypoint2.mainnet-beta.solana.com:8001"
        "entrypoint3.mainnet-beta.solana.com:8001"
        "entrypoint4.mainnet-beta.solana.com:8001"
        "entrypoint5.mainnet-beta.solana.com:8001"
    )
    KNOWN_VALIDATORS=(
        "7Np41oeYqPefeNQEHSv1UDhYrehxin3NStELsSKCT4K2"
        "GdnSyH3YtwcxFvQrVVJMm1JhTS4QVX7MFsX56uJLUfiZ"
        "DE1bawNcRJB9rVm3buyMVfr8mBEoyyu73NBovf2oXJsJ"
        "CakcnaRDHka2gXyfbEd2d3xsvkJkqsLw2akB3zsN1D2S"
    )
    GENESIS_HASH="5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d"
    METRICS_DB="mainnet-beta"
    METRICS_USER="mainnet-beta_write"
    METRICS_PASS="password"
    BAM_REGION="${BAM_REGION:-frankfurt}"
    BAM_URL="http://${BAM_REGION}.mainnet.bam.jito.wtf"
    BLOCK_ENGINE_URL="https://${BAM_REGION}.mainnet.block-engine.jito.wtf"
    TIP_PAYMENT_PUBKEY="T1pyyaTNZsKv2WcRAB8oVnk93mLJw2XzjtVYqCsaHqt"
    TIP_DISTRIBUTION_PUBKEY="4R3gSG8BpU4t19KYj8CfnbtRpnT8gtk4dvTHxVRwc2r7"
    MERKLE_ROOT_AUTHORITY="8F4jGUmxF36vQ6yabnsxX6AQVXdKBhs8kGSUuRKSg8Xt"
    declare -A NTP_SERVERS=(
        ["amsterdam"]="ntp.amsterdam.jito.wtf"
        ["dublin"]="ntp.dublin.jito.wtf"
        ["dallas"]="ntp.dallas.jito.wtf"
        ["frankfurt"]="ntp.frankfurt.jito.wtf"
        ["london"]="ntp.london.jito.wtf"
        ["ny"]="ntp.dallas.jito.wtf"
        ["slc"]="ntp.slc.jito.wtf"
        ["singapore"]="ntp.singapore.jito.wtf"
        ["tokyo"]="ntp.tokyo.jito.wtf"
    )
    NTP_SERVER="${NTP_SERVERS[$BAM_REGION]:-ntp.frankfurt.jito.wtf}"
    declare -A SHRED_RECEIVERS=(
        ["amsterdam"]="74.118.140.240:1002"
        ["dublin"]="64.130.61.8:1002"
        ["dallas"]="141.98.218.12:1002"
        ["frankfurt"]="64.130.50.14:1002"
        ["london"]="64.130.46.153:1002"
        ["ny"]="141.98.216.96:1002"
        ["slc"]="64.130.53.8:1002"
        ["singapore"]="202.8.11.224:1002"
        ["tokyo"]="202.8.9.160:1002"
    )
    SHRED_RECEIVER="${SHRED_RECEIVERS[$BAM_REGION]}"
    COMMISSION_BPS="0"
fi

if [ -z "$SHRED_RECEIVER" ]; then
    log_error "Unknown BAM_REGION: $BAM_REGION"
    log_info "Valid regions: amsterdam, dublin, dallas, frankfurt, london, ny, slc, singapore, tokyo"
    exit 1
fi

HOME_DIR="/home/$NEW_USER"
SOLANA_DIR="$HOME_DIR/solana"
JITO_DIR="$HOME_DIR/$JITO_REPO_DIR"
BIN_DIR="$JITO_DIR/bin"

#############################################################################
# STEP 1: System Update + Disable apt auto-updates
#############################################################################

log_section "STEP 1: System Update"

export DEBIAN_FRONTEND=noninteractive
apt update && apt upgrade -y

systemctl disable --now apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
systemctl disable --now apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
systemctl mask apt-daily.service apt-daily.timer apt-daily-upgrade.service apt-daily-upgrade.timer 2>/dev/null || true
systemctl disable --now unattended-upgrades 2>/dev/null || true
systemctl mask unattended-upgrades 2>/dev/null || true

if [ -f /etc/apt/apt.conf.d/20auto-upgrades ]; then
    sed -i 's/^APT::Periodic::Update-Package-Lists.*/APT::Periodic::Update-Package-Lists "0";/' /etc/apt/apt.conf.d/20auto-upgrades
    sed -i 's/^APT::Periodic::Unattended-Upgrade.*/APT::Periodic::Unattended-Upgrade "0";/' /etc/apt/apt.conf.d/20auto-upgrades
fi

log_info "apt auto-updates disabled"

#############################################################################
# STEP 2: Create User with SSH Access
#############################################################################

log_section "STEP 2: Creating User '$NEW_USER'"

if id "$NEW_USER" &>/dev/null; then
    log_info "User $NEW_USER already exists"
else
    adduser "$NEW_USER" --disabled-password --gecos "" -q
fi

mkdir -p "$HOME_DIR/.ssh"

for key in "${SSH_PUBLIC_KEYS[@]}"; do
    if ! grep -qF "$key" "$HOME_DIR/.ssh/authorized_keys" 2>/dev/null; then
        echo "$key" >> "$HOME_DIR/.ssh/authorized_keys"
    fi
done

printf '%s\n' \
    "Host *" \
    "  ControlMaster auto" \
    "  ControlPath ~/.ssh/cm_socket_%r@%h:%p" \
    "  ControlPersist 10m" \
    > "$HOME_DIR/.ssh/config"

chmod 600 "$HOME_DIR/.ssh/config"
chown -R "$NEW_USER:$NEW_USER" "$HOME_DIR/.ssh"
chmod 700 "$HOME_DIR/.ssh"
chmod 600 "$HOME_DIR/.ssh/authorized_keys"

if [ -n "$SSH_PRIVATE_KEY" ]; then
    log_info "Writing provided SSH private key"
    printf '%s\n' "$SSH_PRIVATE_KEY" > "$HOME_DIR/.ssh/id_ed25519"
    chmod 600 "$HOME_DIR/.ssh/id_ed25519"
    ssh-keygen -y -f "$HOME_DIR/.ssh/id_ed25519" > "$HOME_DIR/.ssh/id_ed25519.pub"
    chmod 644 "$HOME_DIR/.ssh/id_ed25519.pub"
    PUB_KEY=$(cat "$HOME_DIR/.ssh/id_ed25519.pub")
    if ! grep -qF "$PUB_KEY" "$HOME_DIR/.ssh/authorized_keys" 2>/dev/null; then
        echo "$PUB_KEY" >> "$HOME_DIR/.ssh/authorized_keys"
    fi
    chown "$NEW_USER:$NEW_USER" "$HOME_DIR/.ssh/id_ed25519" "$HOME_DIR/.ssh/id_ed25519.pub"
    log_info "SSH public key derived and authorized"

    if [ "$SSH_PRIVATE_KEY_SHRED_AFTER_INSTALL" = "true" ]; then
        log_info "Shredding SSH private key after deriving public key"
        if command -v shred >/dev/null 2>&1; then
            shred -u "$HOME_DIR/.ssh/id_ed25519"
        else
            rm -f "$HOME_DIR/.ssh/id_ed25519"
            log_warn "shred command not found; removed SSH private key without secure overwrite"
        fi
    else
        log_warn "SSH private key left on disk because SSH_PRIVATE_KEY_SHRED_AFTER_INSTALL=false"
    fi
fi

if ! grep -q "^$NEW_USER ALL=(ALL) NOPASSWD:ALL" /etc/sudoers; then
    echo "$NEW_USER ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
fi

#############################################################################
# STEP 3: SSH Hardening
#############################################################################

log_section "STEP 3: SSH Hardening"

sed -i 's|^PermitRootLogin.*|PermitRootLogin no|'                                   /etc/ssh/sshd_config
sed -i 's|^ChallengeResponseAuthentication.*|ChallengeResponseAuthentication no|'   /etc/ssh/sshd_config
sed -i 's|^#\?PasswordAuthentication.*|PasswordAuthentication no|'                  /etc/ssh/sshd_config
sed -i 's|^#\?PermitEmptyPasswords.*|PermitEmptyPasswords no|'                      /etc/ssh/sshd_config
sed -i 's|^#\?PubkeyAuthentication.*|PubkeyAuthentication yes|'                     /etc/ssh/sshd_config

rm -f /etc/ssh/sshd_config.d/*
systemctl restart ssh

#############################################################################
# STEP 4: Install Fail2Ban
#############################################################################

log_section "STEP 4: Installing Fail2Ban"

apt install -y fail2ban
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
systemctl start fail2ban
systemctl enable fail2ban

#############################################################################
# STEP 5: Install System Dependencies
#############################################################################

log_section "STEP 5: Installing System Dependencies"

apt-get install -y \
    libssl-dev libudev-dev pkg-config zlib1g-dev llvm clang cmake make \
    libprotobuf-dev protobuf-compiler lld libclang-dev llvm-dev \
    build-essential git curl wget ufw chrony numactl ethtool

#############################################################################
# STEP 6: Install Rust
#############################################################################

log_section "STEP 6: Installing Rust"

sudo -u "$NEW_USER" bash -c '
if [ ! -d "$HOME/.cargo" ]; then
    curl https://sh.rustup.rs -sSf | sh -s -- -y
fi
source "$HOME/.cargo/env"
rustup update
rustup default stable
rustup component add rustfmt
'

#############################################################################
# STEP 7: Setup NTP with Chrony
#############################################################################

log_section "STEP 7: Configuring Chrony NTP"

systemctl stop ntp 2>/dev/null || true
systemctl disable ntp 2>/dev/null || true
apt remove -y ntp 2>/dev/null || true

printf '%s\n' \
    "server ${NTP_SERVER} iburst" \
    "confdir /etc/chrony/conf.d" \
    "sourcedir /etc/chrony/sources.d" \
    "keyfile /etc/chrony/chrony.keys" \
    "driftfile /var/lib/chrony/chrony.drift" \
    "ntsdumpdir /var/lib/chrony" \
    "logdir /var/log/chrony" \
    "maxupdateskew 100.0" \
    "rtcsync" \
    "makestep 1 3" \
    "leapsectz right/UTC" \
    > /etc/chrony/chrony.conf

systemctl daemon-reload
systemctl enable chrony
systemctl restart chrony

#############################################################################
# STEP 8: Detect Hardware & Setup Disks
# Strategy: accounts → largest NVMe (ext4), ledger → second NVMe (xfs),
#           keys → tmpfs ramdisk
#############################################################################

log_section "STEP 8: Disk Setup"

TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
NUM_CPUS=$(nproc)
NUM_CORES=$(lscpu | awk '/^Core\(s\) per socket:/{print $4}')
NUM_SOCKETS=$(lscpu | awk '/^Socket\(s\):/{print $2}')
PHYSICAL_CORES=$((NUM_CORES * NUM_SOCKETS))
NUM_NUMA=$(lscpu | awk '/^NUMA node\(s\):/{print $2}' | tr -cd '0-9')
if [ -z "$NUM_NUMA" ] || [ "$NUM_NUMA" -eq 0 ] 2>/dev/null; then
    NUM_NUMA=$(numactl --hardware 2>/dev/null | awk '/^available:/{print $2}' | tr -cd '0-9')
fi
NUM_NUMA="${NUM_NUMA:-1}"

log_info "Total RAM: ${TOTAL_RAM_GB}GB"
log_info "CPUs: $NUM_CPUS (${PHYSICAL_CORES} physical cores, ${NUM_SOCKETS} socket(s), ${NUM_NUMA} NUMA node(s))"

swapoff -a
sed -i '/swap/d' /etc/fstab

SYSTEM_DISK=$(df / | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//' | sed 's/p$//')
log_info "System disk: $SYSTEM_DISK"

umount /mnt/accounts 2>/dev/null || true
umount /mnt/ledger   2>/dev/null || true
umount /mnt/ramdisk  2>/dev/null || true

# Find all non-system NVMe disks, sorted by size (largest first)
NVME_DISKS=()
NVME_SIZES=()
for disk in /dev/nvme*n1; do
    [ -b "$disk" ] || continue
    if [[ "$SYSTEM_DISK" == *"$(basename "$disk")"* ]] || [[ "$disk" == *"$SYSTEM_DISK"* ]]; then
        continue
    fi
    SIZE=$(lsblk -bno SIZE "$disk" 2>/dev/null | head -1)
    [ -z "$SIZE" ] && continue
    NVME_DISKS+=("$disk")
    NVME_SIZES+=("$SIZE")
done

# Bubble-sort by size descending
for ((i=0; i<${#NVME_DISKS[@]}; i++)); do
    for ((j=i+1; j<${#NVME_DISKS[@]}; j++)); do
        if [ "${NVME_SIZES[$j]}" -gt "${NVME_SIZES[$i]}" ]; then
            tmp="${NVME_DISKS[$i]}"; NVME_DISKS[$i]="${NVME_DISKS[$j]}"; NVME_DISKS[$j]="$tmp"
            tmp="${NVME_SIZES[$i]}"; NVME_SIZES[$i]="${NVME_SIZES[$j]}"; NVME_SIZES[$j]="$tmp"
        fi
    done
done

log_info "Found ${#NVME_DISKS[@]} non-system NVMe disk(s)"
for ((i=0; i<${#NVME_DISKS[@]}; i++)); do
    log_info "  ${NVME_DISKS[$i]} — $(numfmt --to=iec "${NVME_SIZES[$i]}")"
done

mkdir -p /mnt/accounts /mnt/ledger /mnt/snapshots /mnt/ramdisk

ACCOUNTS_DISK="${NVME_DISKS[0]:-}"
LEDGER_DISK="${NVME_DISKS[1]:-}"

format_and_mount() {
    local disk="$1" mount="$2" fstype="$3"
    umount "$disk" 2>/dev/null || true
    CURRENT_FS=$(blkid -o value -s TYPE "$disk" 2>/dev/null || echo "")
    if [ "$fstype" = "ext4" ]; then
        if [ "$CURRENT_FS" != "ext4" ]; then
            log_info "Formatting $disk as ext4 → $mount"
            mkfs.ext4 -F -E lazy_itable_init=0,lazy_journal_init=0 "$disk"
            sleep 2
        else
            log_info "$disk already ext4, skipping format"
        fi
        mount -o noatime,nodiratime,data=writeback "$disk" "$mount"
    else
        if [ "$CURRENT_FS" != "xfs" ]; then
            log_info "Formatting $disk as XFS → $mount"
            mkfs.xfs -f "$disk"
            sleep 2
        else
            log_info "$disk already XFS, skipping format"
        fi
        mount -o noatime,nodiratime "$disk" "$mount"
    fi
    chown -R "$NEW_USER:$NEW_USER" "$mount"
}

ACCOUNTS_UUID=""
LEDGER_UUID=""

if [ -n "$ACCOUNTS_DISK" ]; then
    log_info "Accounts disk: $ACCOUNTS_DISK → /mnt/accounts"
    format_and_mount "$ACCOUNTS_DISK" /mnt/accounts ext4
    ACCOUNTS_UUID=$(blkid -s UUID -o value "$ACCOUNTS_DISK")
else
    log_error "No NVMe disk found for accounts!"
    lsblk -f
    exit 1
fi

if [ -n "$LEDGER_DISK" ]; then
    log_info "Ledger disk: $LEDGER_DISK → /mnt/ledger"
    format_and_mount "$LEDGER_DISK" /mnt/ledger xfs
    LEDGER_UUID=$(blkid -s UUID -o value "$LEDGER_DISK")
else
    log_warn "No second NVMe for ledger — using root filesystem"
fi

chown -R "$NEW_USER:$NEW_USER" /mnt/snapshots

# Small ramdisk for keys only
mount -t tmpfs -o size=1G tmpfs /mnt/ramdisk
chown -R "$NEW_USER:$NEW_USER" /mnt/ramdisk

# Update fstab
cp /etc/fstab "/etc/fstab.backup.$(date +%s)"
sed -i '/# Jito-Solana Validator Disks/,/^$/d' /etc/fstab

printf '\n# Jito-Solana Validator Disks\n' >> /etc/fstab
printf 'UUID=%s  /mnt/accounts  ext4  noatime,nodiratime,data=writeback  0  2\n' "$ACCOUNTS_UUID" >> /etc/fstab
if [ -n "$LEDGER_UUID" ]; then
    printf 'UUID=%s  /mnt/ledger  xfs  noatime,nodiratime  0  2\n' "$LEDGER_UUID" >> /etc/fstab
fi
printf 'tmpfs  /mnt/ramdisk  tmpfs  nodev,nosuid,noexec,nodiratime,size=1G  0  0\n' >> /etc/fstab

log_info "Disk setup complete"

#############################################################################
# STEP 9: PoH Core Isolation (GRUB)
# Jito does NOT auto-tune — isolate core 2 for PoH
#############################################################################

log_section "STEP 9: PoH Core Isolation"

POH_CORE=2

HT_SIBLINGS_FILE="/sys/devices/system/cpu/cpu${POH_CORE}/topology/thread_siblings_list"
if [ -f "$HT_SIBLINGS_FILE" ]; then
    HT_SIBLINGS=$(cat "$HT_SIBLINGS_FILE")
    IFS="," read -ra THREADS <<< "$HT_SIBLINGS"
    MAIN_CORE="${THREADS[0]}"
    HT_CORE="${THREADS[1]:-}"

    if [ -n "$HT_CORE" ] && [ "$HT_CORE" != "$MAIN_CORE" ]; then
        ISOLATE_CORES="${MAIN_CORE},${HT_CORE}"
        LAST_CPU=$((NUM_CPUS - 1))
        IRQ_RANGES=""
        if [ "$MAIN_CORE" -gt 0 ]; then
            IRQ_RANGES="0-$((MAIN_CORE - 1))"
        fi
        NEXT_AFTER_MAIN=$((MAIN_CORE + 1))
        if [ "$NEXT_AFTER_MAIN" -lt "$HT_CORE" ]; then
            [ -n "$IRQ_RANGES" ] && IRQ_RANGES="${IRQ_RANGES},"
            IRQ_RANGES="${IRQ_RANGES}${NEXT_AFTER_MAIN}-$((HT_CORE - 1))"
        fi
        NEXT_AFTER_HT=$((HT_CORE + 1))
        if [ "$NEXT_AFTER_HT" -le "$LAST_CPU" ]; then
            [ -n "$IRQ_RANGES" ] && IRQ_RANGES="${IRQ_RANGES},"
            IRQ_RANGES="${IRQ_RANGES}${NEXT_AFTER_HT}-${LAST_CPU}"
        fi
        GRUB_LINE="quiet amd_pstate=passive nvme_core.default_ps_max_latency_us=0 nohz_full=${ISOLATE_CORES} isolcpus=domain,managed_irq,${ISOLATE_CORES} irqaffinity=${IRQ_RANGES}"
        log_info "Isolating PoH core $MAIN_CORE (HT sibling $HT_CORE)"
    else
        ISOLATE_CORES="${MAIN_CORE}"
        GRUB_LINE="quiet amd_pstate=passive nvme_core.default_ps_max_latency_us=0 nohz_full=${MAIN_CORE} isolcpus=domain,managed_irq,${MAIN_CORE}"
        log_info "Isolating PoH core $MAIN_CORE (no HT)"
    fi

    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${GRUB_LINE}\"|" /etc/default/grub
    update-grub
    log_info "GRUB updated — takes effect after reboot"
else
    log_warn "Could not detect CPU topology for core $POH_CORE, skipping GRUB isolation"
fi

# PoH thread pin script (run 30s after validator starts — workaround for core_affinity bug)
cat > "$HOME_DIR/set_poh.sh" << 'POHSCRIPT'
#!/bin/bash
LOG_TAG="set_poh_affinity"
echo "[$LOG_TAG] === Starting ==="
agave_pid=$(pgrep -f "agave-validator")
if [ -z "$agave_pid" ]; then
    echo "[$LOG_TAG] ERROR: agave-validator not found"
    exit 1
fi
echo "[$LOG_TAG] PID: $agave_pid"
thread_pid=$(ps -T -p "$agave_pid" -o spid,comm | grep 'solPohTickProd' | awk '{print $1}')
if [ -z "$thread_pid" ]; then
    echo "[$LOG_TAG] ERROR: solPohTickProd thread not found"
    exit 1
fi
POHSCRIPT
echo "echo \"[\$LOG_TAG] Pinning thread \$thread_pid to CPU ${POH_CORE}\"" >> "$HOME_DIR/set_poh.sh"
echo "taskset -cp ${POH_CORE} \"\$thread_pid\"" >> "$HOME_DIR/set_poh.sh"
echo 'echo "[$LOG_TAG] Done"' >> "$HOME_DIR/set_poh.sh"
chmod +x "$HOME_DIR/set_poh.sh"
chown "$NEW_USER:$NEW_USER" "$HOME_DIR/set_poh.sh"

#############################################################################
# STEP 10: System Tuning (sysctl, limits, CPU governor)
#############################################################################

log_section "STEP 10: System Tuning"

cat > /etc/systemd/system/validator-tuning.service << 'TUNINGSVC'
[Unit]
Description=Validator Linux tuning
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c '\
echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null || true; \
echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true; \
echo 0 > /sys/kernel/mm/ksm/run 2>/dev/null || true; \
echo 0 > /proc/sys/kernel/numa_balancing 2>/dev/null || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
TUNINGSVC

systemctl daemon-reload
systemctl enable validator-tuning.service
systemctl start validator-tuning.service

cat > /etc/sysctl.d/21-solana-validator.conf << 'SYSCTL'
# TCP buffers
net.ipv4.tcp_rmem=10240 87380 12582912
net.ipv4.tcp_wmem=10240 87380 12582912

# UDP buffers
net.core.rmem_default=134217728
net.core.rmem_max=134217728
net.core.wmem_default=134217728
net.core.wmem_max=134217728

# TCP optimization
net.ipv4.tcp_congestion_control=westwood
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_timestamps=0
net.ipv4.tcp_sack=1
net.ipv4.tcp_low_latency=1
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_moderate_rcvbuf=1
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_window_scaling=1
net.core.netdev_max_backlog=250000
net.core.default_qdisc=fq

# Kernel
kernel.timer_migration=0
kernel.hung_task_timeout_secs=30
kernel.pid_max=49152

# Virtual memory
vm.swappiness=0
vm.max_map_count=2000000
vm.stat_interval=10
vm.dirty_ratio=40
vm.dirty_background_ratio=10
vm.min_free_kbytes=3000000
vm.dirty_expire_centisecs=36000
vm.dirty_writeback_centisecs=3000
vm.dirtytime_expire_seconds=43200

# File descriptors
fs.nr_open=2000000
SYSCTL

sysctl -p /etc/sysctl.d/21-solana-validator.conf

grep -q "DefaultLimitNOFILE=2000000" /etc/systemd/system.conf || \
    echo "DefaultLimitNOFILE=2000000" >> /etc/systemd/system.conf
systemctl daemon-reexec

cat > /etc/security/limits.d/90-solana-nofiles.conf << 'LIMITS'
* - nofile 2000000
LIMITS

log_info "System tuning applied"

#############################################################################
# STEP 11: Configure Firewall (UFW)
# Includes DoubleZero IBRL + Multicast rules
#############################################################################

log_section "STEP 11: Configuring UFW Firewall"

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

ufw limit 22/tcp                                                         comment 'SSH'
ufw allow 8000:8050/tcp                                                  comment 'Validator TCP'
ufw allow 8000:8050/udp                                                  comment 'Validator UDP'
ufw allow 8001                                                           comment 'Gossip'
ufw allow 8003/udp                                                       comment 'QUIC TPU'

# DoubleZero IBRL (GRE tunnel + BGP) + Multicast
ufw allow proto gre from any to any                                      comment 'GRE in (DoubleZero)'
ufw allow out on any to any proto gre                                    comment 'GRE out (DoubleZero)'
ufw allow in  on doublezero0 from 169.254.0.0/16 to 169.254.0.0/16 port 179 proto tcp comment 'BGP in DZ'
ufw allow out on doublezero0 from 169.254.0.0/16 to 169.254.0.0/16 port 179 proto tcp comment 'BGP out DZ'
ufw allow in  on doublezero0 to any port 44880 proto udp                 comment 'DZ routing in'
ufw allow out on doublezero0 to any port 44880 proto udp                 comment 'DZ routing out'

ufw --force enable

#############################################################################
# STEP 12: Configure Logrotate
#############################################################################

log_section "STEP 12: Configuring Logrotate"

mkdir -p "$SOLANA_DIR"
chown -R "$NEW_USER:$NEW_USER" "$SOLANA_DIR"

printf '%s\n' \
    "${SOLANA_DIR}/solana.log {" \
    "  rotate 7" \
    "  daily" \
    "  missingok" \
    "  notifempty" \
    "  copytruncate" \
    "  create 0644 ${NEW_USER} ${NEW_USER}" \
    "}" \
    > /etc/logrotate.d/solana.logrotate

#############################################################################
# STEP 13: Setup Keypairs
# Placeholder keys are generated for initial sync only.
# Replace with your actual keypairs before activating stake!
#############################################################################

log_section "STEP 13: Setting up Keypairs"

mkdir -p "$HOME_DIR/keys" "$SOLANA_DIR"

if [ -n "$STAKED_IDENTITY_KEY" ] && [ -n "$SECONDARY_IDENTITY_KEY" ] && [ -n "$VOTE_ACCOUNT_KEY" ]; then
    log_info "Writing provided keypairs to $SOLANA_DIR/"
    printf '%s' "$STAKED_IDENTITY_KEY" > "$SOLANA_DIR/staked-identity.json"
    printf '%s' "$SECONDARY_IDENTITY_KEY" > "$SOLANA_DIR/secondary-unstaked-identity.json"
    printf '%s' "$VOTE_ACCOUNT_KEY" > "$SOLANA_DIR/vote-account-keypair.json"
elif [ -f "$SOLANA_DIR/secondary-unstaked-identity.json" ]; then
    log_info "Keypairs already exist in $SOLANA_DIR, skipping generation"
else
    log_warn "Generating placeholder keypairs — replace with your real keys before activating!"

    sudo -u "$NEW_USER" bash -c '
        export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
        if command -v solana-keygen &>/dev/null; then
            solana-keygen new --no-bip39-passphrase -s -o '"${SOLANA_DIR}"'/staked-identity.json
            solana-keygen new --no-bip39-passphrase -s -o '"${SOLANA_DIR}"'/secondary-unstaked-identity.json
            solana-keygen new --no-bip39-passphrase -s -o '"${SOLANA_DIR}"'/vote-account-keypair.json
        fi
    '
fi

ln -sf "$SOLANA_DIR/secondary-unstaked-identity.json" "$SOLANA_DIR/secondary-identity.json"

chmod 600 "$SOLANA_DIR"/*.json 2>/dev/null || true
chown -R "$NEW_USER:$NEW_USER" "$HOME_DIR/keys" "$SOLANA_DIR"

#############################################################################
# STEP 14: Build Jito-Solana
#############################################################################

log_section "STEP 14: Building Jito-Solana ($JITO_TAG, LTO=$ENABLE_LTO)"

if [ "$ENABLE_LTO" = "true" ]; then
    log_info "LTO build enabled — this will take 20-30 minutes"
    LTO_SETUP='
if ! grep -q "profile.release-with-lto" Cargo.toml; then
    printf "\n[profile.release-with-lto]\ninherits = \"release\"\nlto = \"fat\"\ncodegen-units = 1\n" >> Cargo.toml
fi
if ! grep -q "release-with-lto" scripts/cargo-install-all.sh; then
    sed -i "/--release)/a\\    elif [[ \$1 = --release-with-lto ]]; then\n      buildProfileArg=\x27--profile release-with-lto\x27\n      buildProfile=\x27release-with-lto\x27\n      shift" scripts/cargo-install-all.sh
fi
'
    LTO_FLAGS='export RUSTFLAGS="-Clink-arg=-fuse-ld=lld -Ctarget-cpu=native"'
    LTO_ARG="--release-with-lto"
else
    LTO_SETUP=""
    LTO_FLAGS=""
    LTO_ARG=""
fi

sudo -u "$NEW_USER" bash -c "
set -e
source \"\$HOME/.cargo/env\"
cd ~

if [ -d ${JITO_REPO_DIR} ]; then
    cd ${JITO_REPO_DIR}
    git fetch --all --tags
else
    git clone ${JITO_REPO} ${JITO_REPO_DIR}
    cd ${JITO_REPO_DIR}
fi

git checkout ${JITO_TAG}
git submodule update --init --recursive

${LTO_SETUP}
${LTO_FLAGS}

CI_COMMIT=${JITO_TAG} scripts/cargo-install-all.sh ${LTO_ARG} --validator-only \"\$HOME/${JITO_REPO_DIR}\"
"

if [ ! -f "$BIN_DIR/agave-validator" ]; then
    log_error "Build failed: $BIN_DIR/agave-validator not found"
    exit 1
fi

log_info "Build successful:"
ls -lh "$BIN_DIR/agave-validator"
"$BIN_DIR/agave-validator" --version

#############################################################################
# STEP 15: Compute Thread Counts + Detect XDP Capability
#############################################################################

log_section "STEP 15: Computing optimal thread configuration"

if [ "$PHYSICAL_CORES" -ge 24 ]; then
    BLOCK_PRODUCTION_WORKERS=6
    UNIFIED_SCHEDULER_THREADS=12
    REPLAY_TX_THREADS=16
    TVU_RECEIVE_THREADS=4
    TVU_SIGVERIFY_THREADS=16
    TPU_VOTE_RECEIVE_THREADS=4
    ACCOUNTS_DB_CACHE_MB=4096
elif [ "$PHYSICAL_CORES" -ge 16 ]; then
    BLOCK_PRODUCTION_WORKERS=4
    UNIFIED_SCHEDULER_THREADS=8
    REPLAY_TX_THREADS=12
    TVU_RECEIVE_THREADS=3
    TVU_SIGVERIFY_THREADS=10
    TPU_VOTE_RECEIVE_THREADS=3
    ACCOUNTS_DB_CACHE_MB=2048
elif [ "$PHYSICAL_CORES" -ge 8 ]; then
    BLOCK_PRODUCTION_WORKERS=4
    UNIFIED_SCHEDULER_THREADS=4
    REPLAY_TX_THREADS=8
    TVU_RECEIVE_THREADS=2
    TVU_SIGVERIFY_THREADS=6
    TPU_VOTE_RECEIVE_THREADS=2
    ACCOUNTS_DB_CACHE_MB=1024
else
    BLOCK_PRODUCTION_WORKERS=4
    UNIFIED_SCHEDULER_THREADS=4
    REPLAY_TX_THREADS=4
    TVU_RECEIVE_THREADS=2
    TVU_SIGVERIFY_THREADS=3
    TPU_VOTE_RECEIVE_THREADS=1
    ACCOUNTS_DB_CACHE_MB=512
fi

TOTAL_RAM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
if   [ "$TOTAL_RAM_MB" -ge 393216 ]; then ACCOUNTS_DB_CACHE_MB=32768
elif [ "$TOTAL_RAM_MB" -ge 262144 ]; then ACCOUNTS_DB_CACHE_MB=16384
elif [ "$TOTAL_RAM_MB" -ge 131072 ]; then ACCOUNTS_DB_CACHE_MB=8192
fi

log_info "Block production workers  : $BLOCK_PRODUCTION_WORKERS"
log_info "Unified scheduler threads : $UNIFIED_SCHEDULER_THREADS"
log_info "Replay TX threads         : $REPLAY_TX_THREADS"
log_info "TVU sigverify threads     : $TVU_SIGVERIFY_THREADS"
log_info "Accounts DB cache         : ${ACCOUNTS_DB_CACHE_MB}MB"

# --- XDP retransmit detection ---
XDP_FLAGS=""
DEFAULT_IFACE=$(ip route show default | awk '/default/ {print $5}' | head -1)
XDP_SUPPORTED_DRIVERS="mlx5_core|mlx5|i40e|ice|ixgbe|ena"

if [ -n "$DEFAULT_IFACE" ]; then
    NIC_DRIVER=$(ethtool -i "$DEFAULT_IFACE" 2>/dev/null | awk '/^driver:/{print $2}')
    NIC_NUMA=$(cat "/sys/class/net/${DEFAULT_IFACE}/device/numa_node" 2>/dev/null || echo "-1")
    log_info "NIC: $DEFAULT_IFACE  driver: $NIC_DRIVER  NUMA: $NIC_NUMA"

    if echo "$NIC_DRIVER" | grep -qE "$XDP_SUPPORTED_DRIVERS"; then
        if [ "$PHYSICAL_CORES" -ge 16 ] && [ "$NIC_NUMA" != "-1" ]; then
            NUMA_CPUS=$(lscpu -p=cpu,node 2>/dev/null | grep -v '^#' | awk -F, -v node="$NIC_NUMA" '$2==node {print $1}')
            XDP_CORES=()
            for c in $NUMA_CPUS; do
                [ "$c" -eq "$POH_CORE" ] && continue
                [ "$c" -le 1 ] && continue
                [ "${#XDP_CORES[@]}" -ge 4 ] && break
                XDP_CORES+=("$c")
            done
            if [ "${#XDP_CORES[@]}" -ge 2 ]; then
                XDP_CORE_LIST=$(IFS=,; echo "${XDP_CORES[*]}")
                XDP_FLAGS="  --experimental-retransmit-xdp-cpu-cores ${XDP_CORE_LIST} \\
  --experimental-retransmit-xdp-interface ${DEFAULT_IFACE}"
                if echo "$NIC_DRIVER" | grep -qE "mlx5|ice|i40e"; then
                    XDP_FLAGS="${XDP_FLAGS} \\
  --experimental-retransmit-xdp-zero-copy"
                fi
                log_info "XDP retransmit enabled on cores: $XDP_CORE_LIST"
                setcap 'cap_bpf,cap_net_admin,cap_net_raw,cap_perfmon+p' "$BIN_DIR/agave-validator" 2>/dev/null || \
                    log_warn "Could not set XDP capabilities (may need manual setcap)"
                CURRENT_HP=$(cat /proc/sys/vm/nr_hugepages)
                if [ "$CURRENT_HP" -lt 64 ]; then
                    echo 64 > /proc/sys/vm/nr_hugepages
                fi
            else
                log_warn "Not enough NUMA-local cores for XDP, skipping"
            fi
        else
            log_warn "Not enough cores or no NUMA info for XDP, skipping"
        fi
    else
        log_info "NIC driver $NIC_DRIVER does not support XDP retransmit"
    fi
fi

#############################################################################
# STEP 16: Create Jito-Solana systemd Service
#############################################################################

log_section "STEP 16: Creating Jito-Solana Service"

KV_LINES=""
for v in "${KNOWN_VALIDATORS[@]}"; do
    KV_LINES="${KV_LINES}  --known-validator ${v} \\
"
done

EP_LINES=""
for e in "${ENTRYPOINTS[@]}"; do
    EP_LINES="${EP_LINES}  --entrypoint ${e} \\
"
done

NUMA_PREFIX=""
if [ "$NUM_NUMA" -gt 1 ] && command -v numactl &>/dev/null; then
    NUMA_PREFIX="/usr/bin/numactl --membind=0 "
fi

cat > /etc/systemd/system/solana.service << SVCEOF
[Unit]
Description=Jito-Solana Validator ${JITO_TAG} (${NETWORK})
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=${NEW_USER}
LimitMEMLOCK=infinity
LimitNOFILE=2048000

Environment="SOLANA_METRICS_CONFIG=host=https://metrics.solana.com:8086,db=${METRICS_DB},u=${METRICS_USER},p=${METRICS_PASS}"

ExecStart=${NUMA_PREFIX}${BIN_DIR}/agave-validator \\
  --identity ${SOLANA_DIR}/secondary-identity.json \\
  --vote-account ${SOLANA_DIR}/vote-account-keypair.json \\
  --authorized-voter ${SOLANA_DIR}/staked-identity.json \\
  --expected-genesis-hash ${GENESIS_HASH} \\
${EP_LINES}${KV_LINES}  --log ${SOLANA_DIR}/solana.log \\
  --ledger /mnt/ledger \\
  --accounts /mnt/accounts \\
  --snapshots /mnt/snapshots \\
  --dynamic-port-range 8000-8050 \\
  --gossip-port 8001 \\
  --rpc-port 8899 \\
  --private-rpc \\
  --full-rpc-api \\
  --rpc-bind-address 127.0.0.1 \\
  --limit-ledger-size 50000000 \\
  --wal-recovery-mode skip_any_corrupted_record \\
  --full-snapshot-interval-slots 50000 \\
  --incremental-snapshot-interval-slots 5000 \\
  --maximum-full-snapshots-to-retain 2 \\
  --maximum-incremental-snapshots-to-retain 2 \\
  --minimal-snapshot-download-speed 31457280 \\
  --no-poh-speed-test \\
  --no-os-network-stats-reporting \\
  --no-os-memory-stats-reporting \\
  --no-os-cpu-stats-reporting \\
  --no-os-disk-stats-reporting \\
  --experimental-poh-pinned-cpu-core ${POH_CORE} \\
  --block-production-num-workers ${BLOCK_PRODUCTION_WORKERS} \\
  --replay-transactions-threads ${REPLAY_TX_THREADS} \\
  --tvu-receive-threads ${TVU_RECEIVE_THREADS} \\
  --tvu-shred-sigverify-threads ${TVU_SIGVERIFY_THREADS} \\
  --tpu-vote-transaction-receive-threads ${TPU_VOTE_RECEIVE_THREADS} \\
  --accounts-db-cache-limit-mb ${ACCOUNTS_DB_CACHE_MB} \\
  --trust-block-engine-packets \\
  --bam-url ${BAM_URL} \\
  --block-engine-url ${BLOCK_ENGINE_URL} \\
  --shred-receiver-address ${SHRED_RECEIVER} \\
  --shred-receiver-address 233.84.178.1:7733 \\
  --tip-payment-program-pubkey ${TIP_PAYMENT_PUBKEY} \\
  --tip-distribution-program-pubkey ${TIP_DISTRIBUTION_PUBKEY} \\
  --merkle-root-upload-authority ${MERKLE_ROOT_AUTHORITY} \\
  --commission-bps ${COMMISSION_BPS}$(if [ -n "$XDP_FLAGS" ]; then printf ' \\\n%s' "$XDP_FLAGS"; fi)

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
log_info "Service file created: /etc/systemd/system/solana.service"

# PoH pin timer (30s after validator starts)
cat > /etc/systemd/system/set-poh.service << POHSVC
[Unit]
Description=Pin PoH thread to isolated core
After=solana.service
Requires=solana.service

[Service]
Type=oneshot
ExecStart=${HOME_DIR}/set_poh.sh
User=root
POHSVC

cat > /etc/systemd/system/set-poh.timer << POHTMR
[Unit]
Description=Run set_poh 30s after solana starts

[Timer]
OnActiveSec=30
Unit=set-poh.service

[Install]
WantedBy=solana.service
POHTMR

systemctl daemon-reload
systemctl enable set-poh.timer

#############################################################################
# STEP 17: Install Solana CLI + Aliases
#############################################################################

log_section "STEP 17: Setting up CLI and Aliases"

sudo -u "$NEW_USER" bash -c '
sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)" 2>/dev/null || true
'

BASHRC="$HOME_DIR/.bashrc"
grep -q "alias sc="       "$BASHRC" 2>/dev/null || echo "alias sc='solana catchup --our-localhost 8899'"        >> "$BASHRC"
grep -q "alias logs="     "$BASHRC" 2>/dev/null || echo "alias logs='tail -f ${SOLANA_DIR}/solana.log'"          >> "$BASHRC"
grep -q "alias bamstatus=" "$BASHRC" 2>/dev/null || echo "alias bamstatus='journalctl -u solana -f | grep -i bam'" >> "$BASHRC"
grep -q 'export ledger='  "$BASHRC" 2>/dev/null || echo 'export ledger="/mnt/ledger"'                            >> "$BASHRC"
grep -q 'export snapshots=' "$BASHRC" 2>/dev/null || echo 'export snapshots="/mnt/snapshots"'                    >> "$BASHRC"
grep -q "${JITO_REPO_DIR}/bin" "$BASHRC" 2>/dev/null || \
    echo "export PATH=\"\$HOME/.local/share/solana/install/active_release/bin:${BIN_DIR}:\$PATH\""               >> "$BASHRC"

chown "$NEW_USER:$NEW_USER" "$BASHRC"

#############################################################################
# STEP 18: Create Sync Monitor Service
#############################################################################

log_section "STEP 18: Creating Sync Monitor"

cat > "$HOME_DIR/check-sync.sh" << 'SYNCEOF'
#!/bin/bash

SOLANA_CLI="$HOME/.local/share/solana/install/active_release/bin/solana"
RPC_PORT=8899

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

send_telegram() {
    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d chat_id="${TELEGRAM_CHAT_ID}" \
            -d text="$1" \
            -d parse_mode="HTML" > /dev/null 2>&1
    fi
}

HOSTNAME=$(hostname)
send_telegram "🚀 <b>$HOSTNAME</b>: Jito-Solana started, waiting for sync..."

while true; do
    sleep 60
    RESULT=$($SOLANA_CLI catchup --our-localhost $RPC_PORT 2>&1)

    if echo "$RESULT" | grep -q "has caught up"; then
        send_telegram "✅ <b>$HOSTNAME</b>: Node synced!

$RESULT"
        exit 0
    fi

    MINUTE=$(date +%M)
    if [ "$((MINUTE % 10))" -eq 0 ]; then
        SLOTS=$(echo "$RESULT" | grep -oP '\d+ slots? behind' | head -1)
        if [ -n "$SLOTS" ]; then
            send_telegram "⏳ <b>$HOSTNAME</b>: $SLOTS"
        fi
    fi
done
SYNCEOF

chmod +x "$HOME_DIR/check-sync.sh"
chown "$NEW_USER:$NEW_USER" "$HOME_DIR/check-sync.sh"

# Telegram env file (populated if tokens were provided)
printf 'TELEGRAM_BOT_TOKEN=%s\nTELEGRAM_CHAT_ID=%s\n' \
    "$TELEGRAM_BOT_TOKEN" "$TELEGRAM_CHAT_ID" \
    > "$HOME_DIR/.sync-monitor.env"
chmod 600 "$HOME_DIR/.sync-monitor.env"
chown "$NEW_USER:$NEW_USER" "$HOME_DIR/.sync-monitor.env"

cat > /etc/systemd/system/sync-monitor.service << MONEOF
[Unit]
Description=Jito-Solana Sync Monitor
After=solana.service
Requires=solana.service

[Service]
Type=simple
User=${NEW_USER}
EnvironmentFile=${HOME_DIR}/.sync-monitor.env
ExecStart=${HOME_DIR}/check-sync.sh
Restart=no
Environment="PATH=${HOME_DIR}/.local/share/solana/install/active_release/bin:${BIN_DIR}:/usr/bin"

[Install]
WantedBy=multi-user.target
MONEOF

systemctl daemon-reload

#############################################################################
# COMPLETION
#############################################################################

log_section "SETUP COMPLETE!"

echo ""
log_info "Configuration summary:"
echo "  User          : $NEW_USER"
echo "  Network       : $NETWORK"
echo "  Jito version  : $JITO_TAG"
echo "  BAM region    : $BAM_REGION  →  $BAM_URL"
echo "  Block engine  : $BLOCK_ENGINE_URL"
echo "  Shred recv    : $SHRED_RECEIVER  +  233.84.178.1:7733 (DoubleZero)"
echo "  RAM           : ${TOTAL_RAM_GB}GB"
echo "  CPU cores     : $PHYSICAL_CORES physical / $NUM_CPUS threads"
echo "  PoH core      : $POH_CORE (isolated)"
echo "  NUMA nodes    : $NUM_NUMA"
echo ""
log_info "Thread tuning:"
echo "  Block production workers  : $BLOCK_PRODUCTION_WORKERS"
echo "  Replay TX threads         : $REPLAY_TX_THREADS"
echo "  TVU receive threads       : $TVU_RECEIVE_THREADS"
echo "  TVU sigverify threads     : $TVU_SIGVERIFY_THREADS"
echo "  Accounts DB cache         : ${ACCOUNTS_DB_CACHE_MB}MB"
if [ -n "$XDP_FLAGS" ]; then
    echo "  XDP retransmit            : ENABLED ($XDP_CORE_LIST)"
else
    echo "  XDP retransmit            : disabled"
fi
echo ""
log_info "Binary:"
ls -lh "$BIN_DIR/agave-validator"
echo ""
log_info "Keypairs in: $SOLANA_DIR/"
for f in staked-identity.json secondary-identity.json vote-account-keypair.json; do
    if [ -f "$SOLANA_DIR/$f" ]; then echo "  ✅ $f"
    else echo "  ❌ $f — MISSING"; fi
done
echo ""
log_warn "Replace placeholder keypairs with your real ones before activating stake!"
echo ""
log_info "Useful commands after boot:"
echo "  sudo systemctl start solana    # start validator"
echo "  sudo journalctl -u solana -f   # follow logs"
echo "  sc                             # check catchup"
echo "  bamstatus                      # check BAM connection"
echo "  sudo ~/set_poh.sh              # re-pin PoH thread"
echo ""

systemctl enable solana
systemctl enable sync-monitor

send_telegram "🔧 <b>$(hostname)</b>: Jito-Solana ${JITO_TAG} setup complete (${NETWORK}, BAM: ${BAM_REGION})"

log_warn "IMPORTANT: Test SSH login as '$NEW_USER' before reboot!"
log_info "Rebooting in 30 seconds to apply GRUB PoH isolation..."
log_info "Press Ctrl+C to cancel reboot."
sleep 30
/sbin/reboot -f
