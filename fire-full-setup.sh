#!/bin/bash

#############################################################################
# Firedancer (Frankendancer) Validator — Complete Setup Script
# Run as: sudo bash fire-full-setup.sh [FD_TAG] [NETWORK]
#
# Examples:
#   sudo bash fire-full-setup.sh v0.415.20129 mainnet
#   sudo bash fire-full-setup.sh v0.415.20129 testnet
#
# Env overrides:
#   FD_USER            — system user to create (default: ubuntu)
#   TELEGRAM_BOT_TOKEN — optional Telegram bot token for sync alerts
#   TELEGRAM_CHAT_ID   — optional Telegram chat ID for sync alerts
#   BAM_REGION         — Jito region: amsterdam|frankfurt|london|ny|dallas|singapore|tokyo|slc (default: frankfurt)
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

NEW_USER="${FD_USER:-ubuntu}"
FD_SKIP_SYSTEMD_DAEMON_REEXEC="${FD_SKIP_SYSTEMD_DAEMON_REEXEC:-true}"
SSH_ALLOW_CIDR="${SSH_ALLOW_CIDR:-}"
FD_TAG="${1:?Usage: sudo bash fire-full-setup.sh <version> [network]  e.g. v0.415.20129 mainnet}"
NETWORK="${2:-mainnet}"

# Official Firedancer repo
FD_REPO="https://github.com/firedancer-io/firedancer.git"

if [[ "$NETWORK" != "testnet" && "$NETWORK" != "mainnet" ]]; then
    log_error "NETWORK must be 'testnet' or 'mainnet', got: $NETWORK"
    exit 1
fi

log_info "Firedancer tag : $FD_TAG"
log_info "Network        : $NETWORK"
log_info "User           : $NEW_USER"

# --- SSH public keys ---
# Add your own SSH public key(s) here before running.
# Example: "ssh-ed25519 AAAA... user@host"
SSH_PUBLIC_KEYS=(
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK6HS33hxsp1e2fxmZN/L3Cg/eWGLpQWfhIgi7gLE8TN ubuntu@main"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOyXQcMl/qLEzM2cPlUynmbsh5/N1YNgZN6Gd5wN52Ee openclaw-cherry-solana-fd-20260524"
)

# Optional SSH private key. The script derives and authorizes its public key,
# then shreds the private key by default.
SSH_PRIVATE_KEY="${SSH_PRIVATE_KEY:-}"
SSH_PRIVATE_KEY_FILE="${SSH_PRIVATE_KEY_FILE:-}"
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
    METRICS_CONFIG="host=https://metrics.solana.com:8086,db=tds,u=testnet_write,p=c4fa841aa918bf8274e3e2a44d77568d9861b3ea"
    BAM_REGION="${BAM_REGION:-dallas}"
    BLOCK_ENGINE_URL="https://${BAM_REGION}.testnet.block-engine.jito.wtf"
    TIP_PAYMENT_PUBKEY="GJHtFqM9agxPmkeKjHny6qiRKrXZALvvFGiKf11QE7hy"
    TIP_DISTRIBUTION_PUBKEY="DzvGET57TAgEDxvm3ERUM4GNcsAJdqjDLCne9sdfY4wf"
    TIP_DISTRIBUTION_AUTHORITY="7T4inmPmtNBX3MhLwJ9hFsSMnGJYYkKioVABSNTWVRuS"
    declare -A NTP_SERVERS=(
        ["dallas"]="ntp.dallas.jito.wtf"
        ["ny"]="ntp.dallas.jito.wtf"
        ["slc"]="ntp.slc.jito.wtf"
    )
    NTP_SERVER="${NTP_SERVERS[$BAM_REGION]:-ntp.dallas.jito.wtf}"
    RPC_PORT=9099
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
    METRICS_CONFIG="host=https://metrics.solana.com:8086,db=mainnet-beta,u=mainnet-beta_write,p=password"
    BAM_REGION="${BAM_REGION:-frankfurt}"
    BLOCK_ENGINE_URL="https://${BAM_REGION}.mainnet.block-engine.jito.wtf"
    TIP_PAYMENT_PUBKEY="T1pyyaTNZsKv2WcRAB8oVnk93mLJw2XzjtVYqCsaHqt"
    TIP_DISTRIBUTION_PUBKEY="4R3gSG8BpU4t19KYj8CfnbtRpnT8gtk4dvTHxVRwc2r7"
    TIP_DISTRIBUTION_AUTHORITY="8F4jGUmxF36vQ6yabnsxX6AQVXdKBhs8kGSUuRKSg8Xt"
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
    RPC_PORT=9099
fi

HOME_DIR="/home/$NEW_USER"
SOLANA_DIR="$HOME_DIR/solana"
FD_DIR="$HOME_DIR/firedancer"
FDCTL="$FD_DIR/build/native/gcc/bin/fdctl"

#############################################################################
# STEP 1: System Update + Disable apt auto-updates
#############################################################################

log_section "STEP 1: System Update"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
if [ "${FD_SKIP_APT_UPGRADE:-true}" = "true" ]; then
    log_warn "Skipping full apt upgrade for speedrun/rehearsal"
else
    apt-get upgrade -y
fi

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

if [ -z "$SSH_PRIVATE_KEY" ] && [ -n "$SSH_PRIVATE_KEY_FILE" ]; then
    if [ ! -r "$SSH_PRIVATE_KEY_FILE" ]; then
        log_error "SSH_PRIVATE_KEY_FILE is set but not readable: $SSH_PRIVATE_KEY_FILE"
        exit 1
    fi
    log_info "Reading provided SSH private key file"
    SSH_PRIVATE_KEY="$(cat "$SSH_PRIVATE_KEY_FILE")"
fi

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
    build-essential git curl wget ufw chrony numactl ethtool iproute2 xfsprogs

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
# Strategy: accounts → largest NVMe (xfs), ledger → second NVMe (xfs) or
#           ramdisk (if RAM > 700GB and no second disk), keys → tmpfs
#############################################################################

log_section "STEP 8: Disk Setup"

TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
NUM_CPUS=$(nproc)
NUM_CORES=$(lscpu | awk '/^Core\(s\) per socket:/{print $4}')
NUM_SOCKETS=$(lscpu | awk '/^Socket\(s\):/{print $2}')
PHYSICAL_CORES=$((NUM_CORES * NUM_SOCKETS))

log_info "Total RAM : ${TOTAL_RAM_GB}GB"
log_info "CPUs      : $NUM_CPUS ($PHYSICAL_CORES physical cores)"

swapoff -a
sed -i '/swap/d' /etc/fstab

SYSTEM_DISK=$(df / | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//' | sed 's/p$//')
log_info "System disk: $SYSTEM_DISK"

umount /mnt/accounts 2>/dev/null || true
umount /mnt/ledger   2>/dev/null || true
umount /mnt/ramdisk  2>/dev/null || true

mkdir -p /mnt/accounts /mnt/ledger /mnt/snapshots /mnt/ramdisk

# Find largest non-system NVMe → accounts
ACCOUNTS_DISK=""
LARGEST_SIZE=0

is_candidate_data_disk() {
    local disk="$1"
    local name
    name="$(basename "$disk")"

    [ -b "$disk" ] || return 1
    [[ "$SYSTEM_DISK" == *"$name"* ]] && return 1
    [[ "$disk" == *"$SYSTEM_DISK"* ]] && return 1

    # Skip disks that have mounted child partitions, including mdraid roots.
    if lsblk -nr -o MOUNTPOINTS "$disk" 2>/dev/null | grep -qE '/|/boot|/boot/efi'; then
        return 1
    fi

    # Skip disks that still contain mdraid members. Cherry may deploy OS RAID1
    # while reporting two NVMe disks; formatting either member destroys root.
    if lsblk -nr -o FSTYPE "$disk" 2>/dev/null | grep -q '^linux_raid_member$'; then
        return 1
    fi

    return 0
}

for disk in /dev/nvme*n1; do
    is_candidate_data_disk "$disk" || continue
    SIZE=$(lsblk -bno SIZE "$disk" 2>/dev/null | head -1)
    if [ -n "$SIZE" ] && [ "$SIZE" -gt "$LARGEST_SIZE" ]; then
        LARGEST_SIZE=$SIZE
        ACCOUNTS_DISK=$disk
    fi
done

if [ -z "$ACCOUNTS_DISK" ]; then
    log_error "Could not find NVMe disk for accounts"
    lsblk -f
    exit 1
fi

log_info "Accounts disk (largest NVMe): $ACCOUNTS_DISK ($(numfmt --to=iec "$LARGEST_SIZE"))"

CURRENT_FS=$(blkid -o value -s TYPE "$ACCOUNTS_DISK" 2>/dev/null || echo "")
if [ "$CURRENT_FS" != "xfs" ]; then
    log_info "Formatting $ACCOUNTS_DISK as XFS..."
    umount "$ACCOUNTS_DISK" 2>/dev/null || true
    mkfs.xfs -f "$ACCOUNTS_DISK"
    sleep 2
else
    log_info "$ACCOUNTS_DISK already XFS, skipping format"
fi
ACCOUNTS_UUID=$(blkid -s UUID -o value "$ACCOUNTS_DISK")
mount -o noatime "$ACCOUNTS_DISK" /mnt/accounts
chown -R "$NEW_USER:$NEW_USER" /mnt/accounts

# Find second disk for ledger
LEDGER_DISK=""
for disk in /dev/nvme*n1; do
    is_candidate_data_disk "$disk" || continue
    [[ "$disk" == "$ACCOUNTS_DISK" ]] && continue
    LEDGER_DISK=$disk
    break
done

LEDGER_UUID=""
USE_RAMDISK_LEDGER=false

if [ -n "$LEDGER_DISK" ]; then
    log_info "Ledger disk: $LEDGER_DISK → /mnt/ledger"
    CURRENT_FS=$(blkid -o value -s TYPE "$LEDGER_DISK" 2>/dev/null || echo "")
    if [ "$CURRENT_FS" != "xfs" ]; then
        log_info "Formatting $LEDGER_DISK as XFS..."
        umount "$LEDGER_DISK" 2>/dev/null || true
        mkfs.xfs -f "$LEDGER_DISK"
        sleep 2
    else
        log_info "$LEDGER_DISK already XFS, skipping format"
    fi
    LEDGER_UUID=$(blkid -s UUID -o value "$LEDGER_DISK")
    mount -o noatime "$LEDGER_DISK" /mnt/ledger
    RAMDISK_SIZE="1G"
elif [ "$TOTAL_RAM_GB" -gt 700 ]; then
    log_info "No separate ledger disk, RAM > 700GB — using 500GB ramdisk for ledger"
    RAMDISK_SIZE="500G"
    USE_RAMDISK_LEDGER=true
else
    log_warn "No separate ledger disk, RAM <= 700GB — ledger on root filesystem"
    RAMDISK_SIZE="1G"
fi

# Mount ramdisk (keys + optionally ledger)
mount -t tmpfs -o size="$RAMDISK_SIZE" tmpfs /mnt/ramdisk
chown -R "$NEW_USER:$NEW_USER" /mnt/ramdisk

if [ "$USE_RAMDISK_LEDGER" = true ]; then
    mkdir -p /mnt/ramdisk/ledger
    rm -rf /mnt/ledger
    ln -sf /mnt/ramdisk/ledger /mnt/ledger
    chown -R "$NEW_USER:$NEW_USER" /mnt/ramdisk/ledger
fi

chown -R "$NEW_USER:$NEW_USER" /mnt/ledger /mnt/snapshots

# Update fstab
cp /etc/fstab "/etc/fstab.backup.$(date +%s)"
sed -i '/# Firedancer Validator Disks/,/^$/d' /etc/fstab

printf '\n# Firedancer Validator Disks\n' >> /etc/fstab
printf 'UUID=%s  /mnt/accounts  xfs  noatime  0  2\n' "$ACCOUNTS_UUID" >> /etc/fstab
printf 'tmpfs  /mnt/ramdisk  tmpfs  nodev,nosuid,noexec,nodiratime,size=%s  0  0\n' "$RAMDISK_SIZE" >> /etc/fstab
if [ -n "$LEDGER_UUID" ]; then
    printf 'UUID=%s  /mnt/ledger  xfs  noatime  0  2\n' "$LEDGER_UUID" >> /etc/fstab
fi

log_info "Disk setup complete"

#############################################################################
# STEP 9: System Tuning (sysctl, limits, CPU governor)
# Firedancer auto-tunes itself, but OS-level tuning is still beneficial
#############################################################################

log_section "STEP 9: System Tuning"

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
if [ "${FD_SKIP_SYSTEMD_DAEMON_REEXEC}" = "true" ]; then
    log_warn "Skipping systemctl daemon-reexec during remote Cherry bootstrap"
else
    systemctl daemon-reexec
fi

cat > /etc/security/limits.d/90-solana-nofiles.conf << 'LIMITS'
* - nofile 2000000
LIMITS

log_info "System tuning applied"

#############################################################################
# STEP 10: Configure Firewall (UFW)
# Includes DoubleZero IBRL + Multicast rules
#############################################################################

log_section "STEP 10: Configuring UFW Firewall"

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

if [ -n "${SSH_ALLOW_CIDR}" ]; then
    ufw allow from "${SSH_ALLOW_CIDR}" to any port 22 proto tcp comment 'Controlled SSH source'
fi
ufw limit 22/tcp                                                                         comment 'SSH'
ufw allow 8900:9000/tcp                                                                  comment 'Validator TCP'
ufw allow 8900:9000/udp                                                                  comment 'Validator UDP'
ufw allow 8001                                                                           comment 'Gossip'
ufw allow 8003/udp                                                                       comment 'QUIC TPU'
ufw deny  9099/tcp                                                                       comment 'Deny RPC external'
ufw deny  9099/udp                                                                       comment 'Deny RPC external'

# DoubleZero IBRL (GRE tunnel + BGP) + Multicast
ufw allow proto gre from any to any                                                      comment 'GRE in (DoubleZero)'
ufw allow out on any to any proto gre                                                    comment 'GRE out (DoubleZero)'
ufw allow in  on doublezero0 from 169.254.0.0/16 to 169.254.0.0/16 port 179 proto tcp  comment 'BGP in DZ'
ufw allow out on doublezero0 from 169.254.0.0/16 to 169.254.0.0/16 port 179 proto tcp  comment 'BGP out DZ'
ufw allow in  on doublezero0 to any port 44880 proto udp                                 comment 'DZ routing in'
ufw allow out on doublezero0 to any port 44880 proto udp                                 comment 'DZ routing out'

ufw --force enable

#############################################################################
# STEP 11: Configure Logrotate
#############################################################################

log_section "STEP 11: Configuring Logrotate"

mkdir -p "$SOLANA_DIR"
chown -R "$NEW_USER:$NEW_USER" "$SOLANA_DIR"

printf '%s\n' \
    "${SOLANA_DIR}/fire.log {" \
    "  rotate 7" \
    "  daily" \
    "  missingok" \
    "  notifempty" \
    "  copytruncate" \
    "  create 0644 ${NEW_USER} ${NEW_USER}" \
    "}" \
    > /etc/logrotate.d/fire.logrotate

#############################################################################
# STEP 12: Setup Keypairs
# Placeholder keys are generated for initial sync only.
# Replace with your actual keypairs before activating stake!
#############################################################################

log_section "STEP 12: Setting up Keypairs"

mkdir -p "$HOME_DIR/keys" "$SOLANA_DIR"

if [ -f "$HOME_DIR/keys/staked-identity.json" ]; then
    log_info "Keypairs already exist in $HOME_DIR/keys/, skipping generation"
else
    log_warn "Generating placeholder keypairs — replace with your real keys before activating!"

    sudo -u "$NEW_USER" bash -c '
        export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
        if command -v solana-keygen &>/dev/null; then
            solana-keygen new --no-bip39-passphrase -s -o '"$HOME_DIR"'/keys/staked-identity.json
            solana-keygen new --no-bip39-passphrase -s -o '"$HOME_DIR"'/keys/secondary-unstaked-identity.json
            solana-keygen new --no-bip39-passphrase -s -o '"$HOME_DIR"'/keys/vote-account-keypair.json
        fi
    '
fi

chmod 600 "$HOME_DIR"/keys/*.json 2>/dev/null || true
chown -R "$NEW_USER:$NEW_USER" "$HOME_DIR/keys"

# Script to copy keys to ramdisk on boot (keys live on disk, ramdisk is ephemeral)
cat > "$HOME_DIR/setup-ramdisk-keys.sh" << 'RAMDISKSCRIPT'
#!/bin/bash
# Copy keys to ramdisk if not already present
if [ ! -f /mnt/ramdisk/staked-identity.json ]; then
    cp ~/keys/*.json /mnt/ramdisk/
    chmod 600 /mnt/ramdisk/*.json
fi

# secondary-identity symlink for zero-downtime swap.
# Keep this outside the copy branch so a staged ramdisk can be repaired safely.
if [ -f /mnt/ramdisk/secondary-unstaked-identity.json ]; then
    ln -sf secondary-unstaked-identity.json /mnt/ramdisk/secondary-identity.json
fi

# Ensure ramdisk ledger dir exists (for high-RAM configs)
if [ -L /mnt/ledger ]; then
    rm -rf /mnt/ramdisk/ledger
    mkdir -p /mnt/ramdisk/ledger
fi
RAMDISKSCRIPT

chmod +x "$HOME_DIR/setup-ramdisk-keys.sh"
chown "$NEW_USER:$NEW_USER" "$HOME_DIR/setup-ramdisk-keys.sh"

log_info "Keypairs stored in $HOME_DIR/keys/ (will be copied to ramdisk on each boot)"

#############################################################################
# STEP 13: Build Firedancer
#############################################################################

log_section "STEP 13: Building Firedancer ($FD_TAG)"

sudo -u "$NEW_USER" bash << FDBUILDER
set -e
source "\$HOME/.cargo/env"
cd ~

if [ -d firedancer ]; then
    cd firedancer
    git fetch --all --tags
else
    git clone --recurse-submodules $FD_REPO firedancer
    cd firedancer
fi

git checkout $FD_TAG
git submodule update --init --recursive
yes | ./deps.sh
make -j fdctl solana
FDBUILDER

if [ ! -f "$FDCTL" ]; then
    log_error "Build failed: $FDCTL not found"
    exit 1
fi

log_info "Build successful:"
ls -lh "$FDCTL"

#############################################################################
# STEP 14: Create config.toml
#############################################################################

log_section "STEP 14: Creating config.toml"

# Build entrypoints and known_validators as TOML arrays
EP_TOML=""
for e in "${ENTRYPOINTS[@]}"; do
    EP_TOML="${EP_TOML}      \"${e}\",\n"
done

KV_TOML=""
for v in "${KNOWN_VALIDATORS[@]}"; do
    KV_TOML="${KV_TOML}     \"${v}\",\n"
done

#############################################################################
# Firedancer XDP mode detection
#############################################################################

NET_PROVIDER="socket"
XDP_TOML=""
DEFAULT_IFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}')
FD_XDP_ZERO_COPY_DRIVERS="mlx5_core|mlx5|ice|i40e"

probe_xdp_drv_mode() {
    local iface="$1"
    local tmpdir src obj include_dir
    local clang_include_args=()

    [ -n "$iface" ] || return 1
    [ -e "/sys/class/net/$iface/device" ] || return 1
    if ip -details link show dev "$iface" 2>/dev/null | grep -q 'prog/xdp'; then
        log_warn "Existing XDP program detected on $iface; skipping drv probe"
        return 1
    fi

    tmpdir=$(mktemp -d)
    src="$tmpdir/xdp_pass.c"
    obj="$tmpdir/xdp_pass.o"

    cat > "$src" <<'XDPEOF'
#include <linux/bpf.h>
#define SEC(NAME) __attribute__((section(NAME), used))
SEC("xdp")
int xdp_pass(struct xdp_md *ctx) {
    return XDP_PASS;
}
char _license[] SEC("license") = "GPL";
XDPEOF

    include_dir="/usr/include/$(gcc -print-multiarch 2>/dev/null || true)"
    [ -d "$include_dir" ] && clang_include_args=(-I "$include_dir")
    if clang -O2 -target bpf "${clang_include_args[@]}" -c "$src" -o "$obj" >/dev/null 2>&1 &&
       ip link set dev "$iface" xdpdrv obj "$obj" sec xdp >/dev/null 2>&1; then
        ip link set dev "$iface" xdp off >/dev/null 2>&1 || true
        rm -rf "$tmpdir"
        return 0
    fi

    ip link set dev "$iface" xdp off >/dev/null 2>&1 || true
    rm -rf "$tmpdir"
    return 1
}

if [ -n "$DEFAULT_IFACE" ]; then
    NIC_DRIVER=$(ethtool -i "$DEFAULT_IFACE" 2>/dev/null | awk '/^driver:/{print $2}')
    NIC_BUS=$(ethtool -i "$DEFAULT_IFACE" 2>/dev/null | awk '/^bus-info:/{print $2}')
    NIC_NUMA=$(cat "/sys/class/net/${DEFAULT_IFACE}/device/numa_node" 2>/dev/null || echo "-1")
    log_info "NIC: $DEFAULT_IFACE  driver: ${NIC_DRIVER:-unknown}  bus: ${NIC_BUS:-unknown}  NUMA: $NIC_NUMA"

    if probe_xdp_drv_mode "$DEFAULT_IFACE"; then
        NET_PROVIDER="xdp"
        log_info "NIC $DEFAULT_IFACE passed native XDP drv-mode probe"
        if echo "$NIC_DRIVER" | grep -qE "$FD_XDP_ZERO_COPY_DRIVERS"; then
            XDP_TOML='
[net.xdp]
    xdp_zero_copy = true
    xdp_mode = "drv"'
            log_info "Firedancer XDP drv mode with zero-copy will be enabled"
        else
            XDP_TOML='
[net.xdp]
    xdp_zero_copy = false
    xdp_mode = "drv"'
            log_warn "Native XDP drv works, but driver is not in zero-copy allowlist; zero-copy disabled"
        fi
    else
        log_warn "NIC $DEFAULT_IFACE did not pass native XDP drv-mode probe; leaving Firedancer XDP defaults"
    fi
else
    log_warn "Default network interface not detected; leaving Firedancer XDP defaults"
fi

cat > "$SOLANA_DIR/config.toml" << EOF
user = "$NEW_USER"
dynamic_port_range = "8900-9000"

[gossip]
    entrypoints = [
$(printf "%b" "$EP_TOML")    ]
    port_check = true

[rpc]
    port = 9099
    full_api = true
    private = true
    only_known = false

[log]
    path = "$SOLANA_DIR/fire.log"

[ledger]
    path = "/mnt/ledger"
    accounts_path = "/mnt/accounts"
    limit_size = 200_000_000

[snapshots]
    path = "/mnt/snapshots"
    maximum_full_snapshots_to_retain = 1
    maximum_incremental_snapshots_to_retain = 1
    minimum_snapshot_download_speed = 20971520

[consensus]
    identity_path = "/mnt/ramdisk/secondary-identity.json"
    vote_account_path = "/mnt/ramdisk/vote-account-keypair.json"
    authorized_voter_paths = ["/mnt/ramdisk/staked-identity.json"]
    expected_genesis_hash = "$GENESIS_HASH"
    genesis_fetch = true
    poh_speed_test = false
    known_validators = [
$(printf "%b" "$KV_TOML")    ]

[reporting]
    solana_metrics_config = "$METRICS_CONFIG"

[tiles.bundle]
    enabled = true
    url = "$BLOCK_ENGINE_URL"
    tip_distribution_program_addr = "$TIP_DISTRIBUTION_PUBKEY"
    tip_payment_program_addr = "$TIP_PAYMENT_PUBKEY"
    tip_distribution_authority = "$TIP_DISTRIBUTION_AUTHORITY"
    commission_bps = 0

[tiles.shred]
    # DoubleZero multicast (bebop group) — requires: doublezero connect multicast --publish bebop
    additional_shred_destinations_leader = ["233.84.178.1:7733"]

[tiles.gui]
    enabled = false

[net]
    provider = "$NET_PROVIDER"
$XDP_TOML
EOF

chown "$NEW_USER:$NEW_USER" "$SOLANA_DIR/config.toml"
log_info "config.toml written to $SOLANA_DIR/config.toml"

#############################################################################
# STEP 15: Create Firedancer systemd Service
#############################################################################

log_section "STEP 15: Creating Firedancer Service"

cat > /etc/systemd/system/fire.service << FIRESVC
[Unit]
Description=Firedancer Validator $FD_TAG ($NETWORK)
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=on-failure
RestartSec=5
User=root
ExecStartPre=$HOME_DIR/setup-ramdisk-keys.sh
ExecStart=/bin/bash -c '$FDCTL configure init all --config $SOLANA_DIR/config.toml && $FDCTL run --config $SOLANA_DIR/config.toml'

[Install]
WantedBy=multi-user.target
FIRESVC

systemctl daemon-reload
log_info "Service file created: /etc/systemd/system/fire.service"

#############################################################################
# STEP 16: Install Solana CLI + Aliases
#############################################################################

log_section "STEP 16: Setting up Solana CLI and Aliases"

sudo -u "$NEW_USER" bash -c '
sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)" 2>/dev/null || true
'

BASHRC="$HOME_DIR/.bashrc"
grep -q "alias sc="    "$BASHRC" 2>/dev/null || echo "alias sc='solana catchup --our-localhost ${RPC_PORT}'" >> "$BASHRC"
grep -q "alias logs="  "$BASHRC" 2>/dev/null || echo "alias logs='tail -f ${SOLANA_DIR}/fire.log'"           >> "$BASHRC"
grep -q 'export ledger=' "$BASHRC" 2>/dev/null || echo 'export ledger="/mnt/ledger"'                         >> "$BASHRC"
grep -q 'export snapshots=' "$BASHRC" 2>/dev/null || echo 'export snapshots="/mnt/snapshots"'                >> "$BASHRC"
grep -q 'firedancer/build' "$BASHRC" 2>/dev/null || \
    echo "export PATH=\"\$HOME/.local/share/solana/install/active_release/bin:${FD_DIR}/build/native/gcc/bin:\$PATH\"" >> "$BASHRC"

chown "$NEW_USER:$NEW_USER" "$BASHRC"

#############################################################################
# STEP 17: Create Sync Monitor Service
#############################################################################

log_section "STEP 17: Creating Sync Monitor"

cat > "$HOME_DIR/check-sync.sh" << 'SYNCSCRIPT'
#!/bin/bash

SOLANA_CLI="$HOME/.local/share/solana/install/active_release/bin/solana"
RPC_PORT=9099

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
send_telegram "🚀 <b>$HOSTNAME</b>: Firedancer started, waiting for sync..."

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
SYNCSCRIPT

chmod +x "$HOME_DIR/check-sync.sh"
chown "$NEW_USER:$NEW_USER" "$HOME_DIR/check-sync.sh"

# Telegram env file (populated if tokens were provided)
printf 'TELEGRAM_BOT_TOKEN=%s\nTELEGRAM_CHAT_ID=%s\n' \
    "$TELEGRAM_BOT_TOKEN" "$TELEGRAM_CHAT_ID" \
    > "$HOME_DIR/.sync-monitor.env"
chmod 600 "$HOME_DIR/.sync-monitor.env"
chown "$NEW_USER:$NEW_USER" "$HOME_DIR/.sync-monitor.env"

cat > /etc/systemd/system/sync-monitor.service << MONSVC
[Unit]
Description=Firedancer Sync Monitor
After=fire.service
Requires=fire.service

[Service]
Type=simple
User=${NEW_USER}
EnvironmentFile=${HOME_DIR}/.sync-monitor.env
ExecStart=${HOME_DIR}/check-sync.sh
Restart=no
Environment="PATH=${HOME_DIR}/.local/share/solana/install/active_release/bin:${FD_DIR}/build/native/gcc/bin:/usr/bin"

[Install]
WantedBy=multi-user.target
MONSVC

systemctl daemon-reload

#############################################################################
# COMPLETION
#############################################################################

log_section "SETUP COMPLETE!"

echo ""
log_info "Configuration summary:"
echo "  User          : $NEW_USER"
echo "  Network       : $NETWORK"
echo "  FD version    : $FD_TAG"
echo "  Block engine  : $BLOCK_ENGINE_URL"
echo "  NTP server    : $NTP_SERVER"
echo "  RAM           : ${TOTAL_RAM_GB}GB"
echo "  Accounts disk : $ACCOUNTS_DISK"
if [ "$USE_RAMDISK_LEDGER" = true ]; then
    echo "  Ledger        : ramdisk ($RAMDISK_SIZE)"
elif [ -n "$LEDGER_DISK" ]; then
    echo "  Ledger        : $LEDGER_DISK"
else
    echo "  Ledger        : root filesystem (/mnt/ledger)"
fi
echo ""
log_info "Firedancer binary:"
ls -lh "$FDCTL"
echo ""
log_info "Keypairs in: $HOME_DIR/keys/"
for f in staked-identity.json secondary-unstaked-identity.json vote-account-keypair.json; do
    if [ -f "$HOME_DIR/keys/$f" ]; then echo "  ✅ $f"
    else echo "  ❌ $f — MISSING"; fi
done
echo ""
log_warn "Replace placeholder keypairs with your real ones before activating stake!"
echo ""
log_info "Useful commands after boot:"
echo "  sudo systemctl start fire      # start validator"
echo "  sudo journalctl -u fire -f     # follow logs"
echo "  sc                             # check catchup"
echo ""
log_info "DoubleZero (run after server is up):"
echo "  doublezero connect ibrl"
echo "  doublezero connect multicast --publish bebop"
echo ""

systemctl enable fire
systemctl enable sync-monitor

send_telegram "🔧 <b>$(hostname)</b>: Firedancer ${FD_TAG} setup complete (${NETWORK})"

log_warn "IMPORTANT: Test SSH login as '$NEW_USER' before reboot."
log_warn "Automatic reboot disabled for controlled hot-swap rehearsal."
