# Solana Validator Setup

Production-ready setup scripts for Solana validators on bare-metal Ubuntu servers.

Two scripts are provided:
- **`jito-full-setup.sh`** — Jito-Solana (agave-validator fork with BAM / block engine)
- **`fire-full-setup.sh`** — Firedancer (Frankendancer, XDP mode)

Both scripts are fully automated and handle everything from OS hardening to validator service creation.

---

## Features

- System update + disable unattended upgrades
- Creates a dedicated user with SSH key injection
- SSH hardening (no root login, no password auth)
- Fail2Ban installation
- Rust toolchain install
- Chrony NTP with Jito NTP servers
- Swap disabled
- Automatic NVMe disk detection and formatting (accounts → largest disk, ledger → second disk)
- tmpfs ramdisk for keypairs
- Sysctl network + VM tuning
- CPU performance governor + transparent hugepages disabled
- UFW firewall with **DoubleZero IBRL + Multicast** rules included
- Logrotate for validator logs
- systemd service with `Restart=always`
- Optional Telegram sync alerts
- Solana CLI + useful shell aliases

### Jito-Solana specific
- PoH core isolation via GRUB (`isolcpus`, `nohz_full`)
- Auto thread tuning scaled to hardware (block production, TVU, replay, sigverify)
- XDP retransmit detection (mlx5, i40e, ice, ixgbe, ena)
- BAM (Blockspace Assembly Market) integration
- LTO build support (`ENABLE_LTO=true`)
- Accounts DB cache scaled to RAM size

### Firedancer specific
- Official `firedancer-io/firedancer` repo
- Runtime NIC probe for native XDP driver mode; `xdp_mode = "drv"` is written only after the probe succeeds
- Zero-copy enabled only for known-capable drivers (`mlx5`, `ice`, `i40e`); otherwise Firedancer defaults are left in place
- Ramdisk ledger support for high-RAM servers (>700 GB)
- `config.toml` generated dynamically from detected hardware

---

## Requirements

| | Requirement |
|---|---|
| **OS** | Ubuntu 22.04+ or Debian 11+ |
| **Arch** | x86_64 |
| **Access** | root / sudo |
| **Disks** | 1–2 NVMe drives (system disk auto-detected and excluded) |
| **RAM** | 256 GB+ recommended for mainnet |

---

## Quick Start

### Jito-Solana

```bash
# Clone the repo
git clone https://github.com/web3validator/solana-validator-setup.git
cd solana-validator-setup

# ⚠️  Add your SSH public key before running (see Configuration section)
nano jito-full-setup.sh

# Run (version tag is required)
sudo bash jito-full-setup.sh v3.1.9-jito mainnet
```

Available BAM regions (set via `BAM_REGION` env var):

| Region | Mainnet | Testnet |
|---|---|---|
| `amsterdam` | ✅ | — |
| `dublin` | ✅ | — |
| `dallas` | ✅ | ✅ |
| `frankfurt` | ✅ (default) | — |
| `london` | ✅ | — |
| `ny` | ✅ | ✅ |
| `singapore` | ✅ | — |
| `tokyo` | ✅ | — |
| `slc` | ✅ | ✅ |

```bash
# Tokyo example
sudo BAM_REGION=tokyo bash jito-full-setup.sh v3.1.9-jito mainnet

# Testnet with Dallas region
sudo BAM_REGION=dallas bash jito-full-setup.sh v3.1.9-jito testnet

# With LTO build (5–10% faster binary, ~30 min build time)
sudo ENABLE_LTO=true BAM_REGION=frankfurt bash jito-full-setup.sh v3.1.9-jito mainnet
```

### Firedancer

```bash
sudo bash fire-full-setup.sh v0.415.20129 mainnet

# With custom BAM region
sudo BAM_REGION=tokyo bash fire-full-setup.sh v0.415.20129 mainnet
```

---

## Configuration

### SSH Keys

Before running, add your SSH public key(s) to the `SSH_PUBLIC_KEYS` array at the top of the script:

```bash
SSH_PUBLIC_KEYS=(
    "ssh-ed25519 AAAA... your-key@host"
)
```

> ⚠️ **Warning:** The script hardens SSH and disables password authentication. If you don't add your key, you **will** be locked out after reboot.

`fire-full-setup.sh` and `jito-full-setup.sh` can also accept
`SSH_PRIVATE_KEY` or `SSH_PRIVATE_KEY_FILE` via environment. They write
the key only long enough to derive and authorize the public key, then shred
`~/.ssh/id_ed25519` by default. Set
`SSH_PRIVATE_KEY_SHRED_AFTER_INSTALL=false` only if the deployed host must keep
that private key for outbound SSH.

For Cherry rehearsals, use one pre-created stable SSH keypair every time.
The public key should be present in `SSH_PUBLIC_KEYS`; the private key should
be injected at runtime with `SSH_PRIVATE_KEY_FILE` pointing at a root-only
secret file and must not be committed to git or copied into documentation.

### Telegram Alerts (optional)

Set via environment variables before running:

```bash
export TELEGRAM_BOT_TOKEN="your-bot-token"
export TELEGRAM_CHAT_ID="your-chat-id"
sudo -E bash jito-full-setup.sh v3.1.9-jito mainnet
```

Alerts are sent when: validator starts syncing, sync complete, setup complete.

---

## Disk Layout

| Mount | Content | Filesystem |
|---|---|---|
| `/mnt/accounts` | Accounts DB | ext4 (Jito) / xfs (FD) |
| `/mnt/ledger` | Ledger | xfs |
| `/mnt/snapshots` | Snapshots | on accounts or root |
| `/mnt/ramdisk` | Keypairs | tmpfs 1 GB |

Disk detection logic:

1. System disk is auto-detected and excluded
2. Remaining NVMe disks sorted by size (largest first)
3. Largest → `/mnt/accounts`
4. Second largest → `/mnt/ledger`
5. If no second disk: ledger goes on root filesystem (or 500 GB ramdisk if RAM > 700 GB — Firedancer only)

---

## Keypairs

The scripts generate **placeholder keypairs** for initial sync. You **must** replace them with your real keys before activating stake.

**Jito-Solana** — keys in `/home/ubuntu/solana/`:

```
staked-identity.json        # primary identity (authorized voter)
secondary-identity.json     # hot-swap identity
vote-account-keypair.json   # vote account
```

**Firedancer** — keys in `/home/ubuntu/keys/` (copied to ramdisk on each boot):

```
staked-identity.json
secondary-unstaked-identity.json
vote-account-keypair.json
```

---

## DoubleZero Integration

Both scripts include UFW firewall rules for [DoubleZero](https://docs.malbeclabs.com) (IBRL + Multicast). The `--shred-receiver-address 233.84.178.1:7733` flag is already included in the generated service files.

After the server is running, install and connect DoubleZero:

```bash
# 1. Install DoubleZero (mainnet-beta)
curl -1sLf https://dl.cloudsmith.io/public/malbeclabs/doublezero/setup.deb.sh | sudo -E bash
sudo apt-get install doublezero

# 2. Generate DZ identity
doublezero keygen

# 3. Configure for mainnet-beta
DESIRED_DOUBLEZERO_ENV=mainnet-beta \
    && sudo mkdir -p /etc/systemd/system/doublezerod.service.d \
    && echo -e "[Service]\nExecStart=\nExecStart=/usr/bin/doublezerod -sock-file /run/doublezerod/doublezerod.sock -env $DESIRED_DOUBLEZERO_ENV" \
       | sudo tee /etc/systemd/system/doublezerod.service.d/override.conf > /dev/null \
    && sudo systemctl daemon-reload \
    && sudo systemctl restart doublezerod \
    && doublezero config set --env $DESIRED_DOUBLEZERO_ENV

# 4. Check connectivity
doublezero latency

# 5. Register validator
doublezero-solana passport find-validator -u mainnet-beta
doublezero-solana passport prepare-validator-access -u mainnet-beta \
    --doublezero-address <YOUR_DZ_ADDRESS> \
    --primary-validator-id <YOUR_VALIDATOR_ID>
# Sign with: solana sign-offchain-message <message> -k <identity-keypair.json>
doublezero-solana passport request-validator-access -u mainnet-beta \
    --primary-validator-id <YOUR_VALIDATOR_ID> \
    --doublezero-address <YOUR_DZ_ADDRESS> \
    --signature <SIGNATURE> \
    -k <identity-keypair.json>

# 6. Connect (both IBRL and multicast)
doublezero connect ibrl
doublezero connect multicast --publish bebop

# 7. Verify multicast (heartbeat every 10s, shreds during leader slot)
sudo tcpdump -vv -c5 -ni doublezero1 port 7733 or port 5765
```

For testnet, replace `mainnet-beta` with `testnet` and use the testnet package repo:

```bash
curl -1sLf https://dl.cloudsmith.io/public/malbeclabs/doublezero-testnet/setup.deb.sh | sudo -E bash
sudo apt-get install doublezero
```

---

## After Setup

### Jito-Solana

```bash
sudo systemctl start solana       # start validator
sudo journalctl -u solana -f      # follow logs
sc                                # solana catchup --our-localhost 8899
bamstatus                         # check BAM connection
sudo ~/set_poh.sh                 # re-pin PoH thread (if needed)
```

### Firedancer

```bash
sudo systemctl start fire         # start validator
sudo journalctl -u fire -f        # follow logs
sc                                # solana catchup --our-localhost 9099
```

---

## Zero-Downtime Identity Swap

Both scripts set up a primary + secondary keypair pattern for hot-swap between servers:

```bash
# On new server — validator starts with secondary (unstaked) identity
# It syncs and stays ready as hot standby

# When ready to switch:

# 1. On OLD server — transfer identity to secondary
solana-validator -l /mnt/ledger set-identity secondary-identity.json

# 2. On NEW server — take over primary identity
solana-validator -l /mnt/ledger set-identity staked-identity.json

# The vote account follows the staked-identity automatically
# via --authorized-voter in the service file
```

---

## Environment Variables Reference

| Variable | Default | Description |
|---|---|---|
| `JITO_USER` / `FD_USER` | `ubuntu` | System user to create |
| `JITO_REPO` | `jito-foundation/jito-solana` | Git repo URL (Jito only) |
| `BAM_REGION` | `frankfurt` (mainnet) / `dallas` (testnet) | Jito BAM + NTP region |
| `ENABLE_LTO` | `false` | LTO build for ~5–10% faster binary (Jito only) |
| `TELEGRAM_BOT_TOKEN` | *(empty)* | Telegram bot token for sync alerts |
| `TELEGRAM_CHAT_ID` | *(empty)* | Telegram chat ID for sync alerts |

---

## Network Constants

### Mainnet-Beta

| | Value |
|---|---|
| Genesis hash | `5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d` |
| Tip payment program | `T1pyyaTNZsKv2WcRAB8oVnk93mLJw2XzjtVYqCsaHqt` |
| Tip distribution program | `4R3gSG8BpU4t19KYj8CfnbtRpnT8gtk4dvTHxVRwc2r7` |
| Merkle root authority | `8F4jGUmxF36vQ6yabnsxX6AQVXdKBhs8kGSUuRKSg8Xt` |
| DoubleZero multicast | `233.84.178.1:7733` (group `bebop`) |

### Testnet

| | Value |
|---|---|
| Genesis hash | `4uhcVJyU9pJkvQyS88uRDiswHXSCkY3zQawwpjk2NsNY` |
| Tip payment program | `GJHtFqM9agxPmkeKjHny6qiRKrXZALvvFGiKf11QE7hy` |
| Tip distribution program | `DzvGET57TAgEDxvm3ERUM4GNcsAJdqjDLCne9sdfY4wf` |
| Merkle root authority | `7T4inmPmtNBX3MhLwJ9hFsSMnGJYYkKioVABSNTWVRuS` |

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Server                                             │
│                                                     │
│  ┌──────────────┐   ┌──────────────────────────┐    │
│  │  Validator    │   │  DoubleZero              │    │
│  │  (Jito / FD)  │   │  doublezero0 (IBRL)     │    │
│  │              │──▶│  doublezero1 (Multicast)  │    │
│  │  systemd     │   │  doublezerod  (daemon)   │    │
│  └──────────────┘   └──────────────────────────┘    │
│         │                                           │
│  ┌──────┴──────────────────────────────────────┐    │
│  │  Disks                                      │    │
│  │  /mnt/accounts  (NVMe, ext4/xfs)            │    │
│  │  /mnt/ledger    (NVMe, xfs)                 │    │
│  │  /mnt/ramdisk   (tmpfs, keys)               │    │
│  └─────────────────────────────────────────────┘    │
│                                                     │
│  ┌─────────────────────────────────────────────┐    │
│  │  OS Hardening                               │    │
│  │  SSH keys only │ Fail2Ban │ UFW firewall    │    │
│  │  Sysctl tuning │ CPU perf │ NTP (Chrony)   │    │
│  └─────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
```

---

## Contributing

PRs and issues welcome. If you find bugs or have improvements, feel free to contribute.

---

## License

MIT
