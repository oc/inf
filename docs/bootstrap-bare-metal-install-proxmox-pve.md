# Bootstrap Proxmox VE on HPE ProLiant via iLO Virtual Media (Auto-Install)

Runbook for installing Proxmox VE 9.x unattended on HPE ProLiant Gen8/Gen9 servers
in the Digiplex colo, using iLO 4 virtual media + an auto-install ISO baked with
`proxmox-auto-install-assistant`.

Tested on:
- DL360 Gen9 (iLO 4) with Smart Array P440 in HBA mode + ZFS-RAID-Z3
- DL360p Gen8 (iLO 4) with Smart Array P420i in RAID mode + ext4 on hardware RAID

## Prerequisites

| Need | Why / value |
|---|---|
| Proxmox VE ISO at `~/VMs/proxmox-ve_9.1-1.iso` | Source ISO to bake answers into |
| `oc.int.lowercase.no` reachable (10.0.206.200 on the iLO subnet) | Hosts the ISO over HTTP for iLO virtual media. Same L3 subnet as the iLOs = fast |
| `Administrator` iLO credentials for each target server | See 1Password vault `Security` (`misc-10.74` for `#GY59inku`, `10.11.1.x` for `UpperCase2022#`) |
| Target IP / hostname / gateway / DNS plan | e.g. `pve1.lowercase.no` → `10.99.1.1/24`, gw/dns `10.99.1.254` (VRRP VIP on VyOS) |
| Root password planned for new install | Stored in 1Password vault `o19g`, item `pveX.lowercase.no - root (Proxmox)` |

## High-level flow

```
[your laptop] --scp--> oc.int:/tmp/proxmox-ve_9.1-1.iso
                          │
                          │ proxmox-auto-install-assistant prepare-iso --answer-file=...
                          ▼
                       /tmp/pve-autoinstall/<host>-auto.iso
                          │
                          │ nginx (docker) on 10.0.206.200:8080
                          ▼
[iLO Redfish] --InsertVirtualMedia URL--> http://10.0.206.200:8080/.../auto.iso
                          │
                          │ ONE_TIME_BOOT=CDROM (RIBCL) + ForceRestart
                          ▼
                  [target server boots auto-install]
                          │
                          │ unattended install (no EULA, no clicks)
                          ▼
                  Proxmox up at https://<host-ip>:8006
```

## Why these specific choices

These are not obvious — each was learned the hard way:

- **Stage on `oc.int`, not your laptop.** iLO virtual-media HTTP fetches need to reach the
  staging host. Laptop on VPN tunnel = iLO can't usually reach back. `oc.int` has
  `10.0.206.200/25` on the iLO management subnet → direct L2.
- **Serve via nginx, not `python3 -m http.server`.** Python's stdlib server is
  single-threaded and handles ranged requests poorly. iLO virtual media is *all*
  ranged requests. Symptom: "Attempting Boot From CD-ROM" times out instantly,
  BIOS falls through to whatever's next. nginx with `sendfile + tcp_nopush` solves it.
- **Switch BIOS to `LegacyBios` mode for the install.** iLO 4's URL-mounted virtual CD
  does **not** appear as a discrete UEFI boot variable — only as part of `Generic.USB.1.1`
  catch-all. UEFI `BootSourceOverrideTarget=Cd` therefore has no effect.
  In Legacy BIOS mode the iLO virtual CD presents as an ATAPI CD-ROM and the BIOS
  default order tries it ahead of USB. Re-enable UEFI later if you care
  (post-install reinstall required).
- **Disable `UsbBoot` and `InternalSDCardSlot` in BIOS settings post-install.** HPE
  servers often have a leftover SD card / internal USB stick with the previous OS
  (commonly ESXi). After Proxmox is installed on the SAS array, BIOS will still
  prefer the USB-stick boot path unless we disable it. Symptom: "Attempting Boot
  From USB DriveKey (C:)" → boots whatever was there before instead of the new Proxmox.
- **Eject the virtual CD after the auto-install finishes.** Otherwise the BIOS keeps
  picking the CD and the auto-installer re-runs each reboot — destructive infinite loop.
- **Disposable disks vs. existing arrays.** If existing logical drives are present and
  you want a clean ZFS-Z3 layout (Gen9 P440), delete LDs + flip controller to HBA mode
  via `ssacli` from the running OS *before* booting the Proxmox installer. The P440's
  failed Smart Storage Battery refuses online metadata transformation unless
  `nobatterywritecache=enable` is set first.

## Step 1 – stage the ISO on oc.int

```bash
scp ~/VMs/proxmox-ve_9.1-1.iso oc.int.lowercase.no:/tmp/

# verify
ssh oc.int.lowercase.no "ls -la /tmp/proxmox-ve_9.1-1.iso && md5sum /tmp/proxmox-ve_9.1-1.iso"
md5 -q ~/VMs/proxmox-ve_9.1-1.iso
```

## Step 2 – write the answer file

For **pve1** (Gen9, ZFS-RAID-Z3 on 8 SAS disks behind P440 in HBA mode):

```toml
# /tmp/pve-autoinstall/answer-pve1.toml
[global]
keyboard = "en-us"
country = "no"
fqdn = "pve1.lowercase.no"
mailto = "oc@rynning.no"
timezone = "Europe/Oslo"
root-password = "ebx0sB55!"

[network]
source = "from-answer"
cidr = "10.99.1.1/24"
dns = "10.99.1.254"
gateway = "10.99.1.254"
filter.INTERFACE = "en*"

[disk-setup]
filesystem = "zfs"
zfs.raid = "raidz3"
zfs.compress = "lz4"
zfs.ashift = 12
disk-list = ["sda", "sdb", "sdc", "sdd", "sde", "sdf", "sdg", "sdh"]
```

For **pve2** (Gen8, ext4 on hardware RAID-6 LD2 = `/dev/sdb` on P420i):

```toml
# /tmp/pve-autoinstall/answer-pve2.toml
[global]
keyboard = "en-us"
country = "no"
fqdn = "pve2.lowercase.no"
mailto = "oc@rynning.no"
timezone = "Europe/Oslo"
root-password = "ebx0sB55!"

[network]
source = "from-answer"
cidr = "10.99.1.2/24"
dns = "10.99.1.254"
gateway = "10.99.1.254"
filter.INTERFACE = "en*"

[disk-setup]
filesystem = "ext4"
disk-list = ["sdb"]
```

> **Disk-list gotcha:** verify which `/dev/sdX` is actually the target by booting the
> stock Proxmox installer once and reading off the disk sizes from the wizard — the
> mapping depends on controller LD ordering. On the Gen8 with two RAID6 LDs, LD1
> (20 GB) was `sda` and LD2 (4.4 TB) was `sdb`. Wrong choice = install on a 20 GB
> partition with no room for VMs.

## Step 3 – generate the auto-install ISO

`proxmox-auto-install-assistant` ships in the Proxmox repo. Easiest from a clean
Debian Trixie container:

```bash
ssh oc.int.lowercase.no "
  mkdir -p /tmp/pve-autoinstall
  # answer file already placed at /tmp/pve-autoinstall/answer-<host>.toml
  sudo docker run --rm -v /tmp:/host-tmp debian:trixie bash -c '
    set -e
    apt-get update -qq
    apt-get install -y -qq curl gnupg ca-certificates
    install -d -m 0755 /etc/apt/keyrings
    curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg \
      -o /etc/apt/keyrings/proxmox-release-trixie.gpg
    echo \"deb [signed-by=/etc/apt/keyrings/proxmox-release-trixie.gpg] http://download.proxmox.com/debian/pve trixie pve-no-subscription\" \
      > /etc/apt/sources.list.d/pve.list
    apt-get update -qq
    apt-get install -y -qq proxmox-auto-install-assistant xorriso

    proxmox-auto-install-assistant validate-answer /host-tmp/pve-autoinstall/answer-pve1.toml
    proxmox-auto-install-assistant prepare-iso \
      --fetch-from iso \
      --answer-file /host-tmp/pve-autoinstall/answer-pve1.toml \
      --output /host-tmp/pve-autoinstall/proxmox-ve_9.1-1-pve1-auto.iso \
      /host-tmp/proxmox-ve_9.1-1.iso

    # repeat for pve2
    proxmox-auto-install-assistant validate-answer /host-tmp/pve-autoinstall/answer-pve2.toml
    proxmox-auto-install-assistant prepare-iso \
      --fetch-from iso \
      --answer-file /host-tmp/pve-autoinstall/answer-pve2.toml \
      --output /host-tmp/pve-autoinstall/proxmox-ve_9.1-1-pve2-auto.iso \
      /host-tmp/proxmox-ve_9.1-1.iso
  '
  sudo chmod a+r /tmp/pve-autoinstall/*.iso
"
```

## Step 4 – serve the ISOs via nginx

```bash
ssh oc.int.lowercase.no "
  sudo docker rm -f pve-iso-server 2>/dev/null
  sudo docker run -d \
    --name pve-iso-server \
    --restart unless-stopped \
    -p 10.0.206.200:8080:80 \
    -v /tmp:/usr/share/nginx/html:ro \
    nginx:alpine

  curl -sI -o /dev/null -w 'HTTP %{http_code}\n' http://10.0.206.200:8080/pve-autoinstall/proxmox-ve_9.1-1-pve1-auto.iso
"
```

## Step 5 – flip target server BIOS to Legacy mode

Skip this if the box is already in Legacy mode. Only needs to be done once per host.

```bash
HOST=10.0.206.253        # iLO IP (pve1 = .253, pve2 = .251)
PWD='UpperCase2022#'     # iLO Administrator pwd (pve1's; pve2 uses #GY59inku)

cat > /tmp/setlegacy.xml <<EOF
<?xml version="1.0"?>
<RIBCL VERSION="2.0">
  <LOGIN USER_LOGIN="Administrator" PASSWORD="${PWD}">
    <SERVER_INFO MODE="write">
      <SET_PENDING_BOOT_MODE VALUE="LEGACY"/>
    </SERVER_INFO>
  </LOGIN>
</RIBCL>
EOF

curl -sk -u "Administrator:${PWD}" -X POST -H "Content-Type: application/xml" \
  --data @/tmp/setlegacy.xml "https://${HOST}/ribcl"
```

> The Redfish `BIOS/Settings` PATCH for `BootMode` works on Gen9 iLO 4 firmware but
> 404s on older Gen8. RIBCL `SET_PENDING_BOOT_MODE` works on both.

## Step 6 – mount the auto-install ISO + arm one-time CDROM boot + reset

```bash
HOST=10.0.206.253
PWD='UpperCase2022#'
ISO_URL='http://10.0.206.200:8080/pve-autoinstall/proxmox-ve_9.1-1-pve1-auto.iso'

# Eject any prior media
curl -sk -u "Administrator:${PWD}" -X POST -H "Content-Type: application/json" -d '{}' \
  "https://${HOST}/redfish/v1/Managers/1/VirtualMedia/2/Actions/Oem/Hp/HpiLOVirtualMedia.EjectVirtualMedia/"

# Insert auto-install ISO
curl -sk -u "Administrator:${PWD}" -X POST -H "Content-Type: application/json" \
  -d "{\"Image\":\"${ISO_URL}\"}" \
  "https://${HOST}/redfish/v1/Managers/1/VirtualMedia/2/Actions/Oem/Hp/HpiLOVirtualMedia.InsertVirtualMedia/"

# One-time CDROM boot via RIBCL (more reliable than Redfish BootSourceOverride on iLO 4)
cat > /tmp/onetimecd.xml <<EOF
<?xml version="1.0"?>
<RIBCL VERSION="2.0">
  <LOGIN USER_LOGIN="Administrator" PASSWORD="${PWD}">
    <SERVER_INFO MODE="write">
      <SET_ONE_TIME_BOOT VALUE="CDROM"/>
    </SERVER_INFO>
  </LOGIN>
</RIBCL>
EOF
curl -sk -u "Administrator:${PWD}" -X POST -H "Content-Type: application/xml" \
  --data @/tmp/onetimecd.xml "https://${HOST}/ribcl"

# Reset
curl -sk -u "Administrator:${PWD}" -X POST -H "Content-Type: application/json" \
  -d '{"ResetType":"ForceRestart"}' \
  "https://${HOST}/redfish/v1/Systems/1/Actions/ComputerSystem.Reset/"
```

Open the iLO HTML5 IRC at `https://${HOST}/irc.html` to watch progress (optional —
auto-install needs no input). Expect:

1. POST + Smart Storage Battery POST error 313 (transient on Gen9 with failed FBWC)
2. "Attempting Boot From CD-ROM" → succeeds with nginx
3. Proxmox auto-install banner: "Starting automatic installation"
4. ~5 min later: install complete, system reboots

## Step 7 – post-install cleanup (critical)

After the box reboots from the auto-install, **immediately** eject the CD and
disable USB/SD boot — otherwise the BIOS will pick the CD again on next boot
and the auto-install will re-run, wiping the just-installed system.

```bash
HOST=10.0.206.253
PWD='UpperCase2022#'

# Eject virtual CD
curl -sk -u "Administrator:${PWD}" -X POST -H "Content-Type: application/json" -d '{}' \
  "https://${HOST}/redfish/v1/Managers/1/VirtualMedia/2/Actions/Oem/Hp/HpiLOVirtualMedia.EjectVirtualMedia/"

# Disable USB boot + internal SD slot (Gen9 — both via Redfish; Gen8 needs RIBCL)
curl -sk -u "Administrator:${PWD}" -X PATCH -H "Content-Type: application/json" \
  -d '{"UsbBoot":"Disabled","InternalSDCardSlot":"Disabled"}' \
  "https://${HOST}/redfish/v1/Systems/1/BIOS/Settings/"

# Clear ONE_TIME_BOOT
cat > /tmp/normalboot.xml <<EOF
<?xml version="1.0"?>
<RIBCL VERSION="2.0">
  <LOGIN USER_LOGIN="Administrator" PASSWORD="${PWD}">
    <SERVER_INFO MODE="write">
      <SET_ONE_TIME_BOOT VALUE="NORMAL"/>
    </SERVER_INFO>
  </LOGIN>
</RIBCL>
EOF
curl -sk -u "Administrator:${PWD}" -X POST -H "Content-Type: application/xml" \
  --data @/tmp/normalboot.xml "https://${HOST}/ribcl"

# Reboot once more so pending BIOS settings flush to active
curl -sk -u "Administrator:${PWD}" -X POST -H "Content-Type: application/json" \
  -d '{"ResetType":"ForceRestart"}' \
  "https://${HOST}/redfish/v1/Systems/1/Actions/ComputerSystem.Reset/"
```

After this final reboot, BIOS skips Floppy → CD (empty) → USB DriveKey
(disabled) → SD (disabled) → **Hard Drive** → Proxmox GRUB → Proxmox up.

## Step 8 – validate

```bash
ping -c 2 10.99.1.1
curl -sk -o /dev/null -w 'HTTP %{http_code}\n' https://10.99.1.1:8006
ssh root@10.99.1.1 'pveversion; zpool status; ip -4 addr show'
```

Login at `https://10.99.1.1:8006` (or `:8006` of whichever host) with the
`root-password` from the answer file.

## Step 9 – tear down ISO server (optional)

When both hosts are installed and verified:

```bash
ssh oc.int.lowercase.no "
  sudo docker rm -f pve-iso-server
  rm /tmp/proxmox-ve_9.1-1.iso
  rm -rf /tmp/pve-autoinstall
"
```

Also rotate the `ebx0sB55!` install-time root password to a strong unique value
on each host and store in 1Password vault `o19g`.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| "Attempting Boot From CD-ROM" → falls through to USB instantly | nginx not actually serving with ranged-requests, or CD URL stale | Verify `curl -I -H 'Range: bytes=0-1023' <iso-url>` returns 206. Re-eject + re-insert via Redfish to refresh URL connection |
| BIOS keeps booting old ESXi/whatever from internal USB stick | `UsbBoot=Enabled` and stick physically present | Disable `UsbBoot` per Step 7 |
| BIOS hits "313-HPE Smart Storage Battery 1 Failure" then auto-restarts | Failed FBWC battery on RAID controller | Transient — BIOS retries and proceeds. Disable cache for the controller (`ssacli ctrl slot=N modify nobatterywritecache=enable`) if you need to do online operations like deleting LDs |
| Proxmox installs but unreachable on configured IP | Wrong NIC matched by `filter.INTERFACE` | SSH from iLO console (or use IRC), check `ip a`, fix `/etc/network/interfaces`, restart networking |
| F11 boot menu not working from a Mac | macOS captures F11 for "Show Desktop" | System Settings → Keyboard → Keyboard Shortcuts → Mission Control → uncheck "Show Desktop" |
| Auto-install loops, re-installs every boot | Virtual CD not ejected after first install | Eject via Redfish (Step 7) |

## Reference: things that don't work (so don't bother trying)

- `BootSourceOverrideTarget=Cd` (Redfish): on iLO 4 firmware tested, the URL-mounted
  virtual CD does not appear as a recognized `Cd` boot source in UEFI mode → override
  is silently ignored.
- HPE OEM `BootOnNextServerReset` flag on `VirtualMedia/2`: gets set, gets cleared on
  reset, never actually causes the CD to boot. Maybe-bug in firmware.
- iLO web UI "One-Time Boot" dropdown: shows in the menu but the available targets
  in UEFI mode don't include the URL-mounted virtual CD.
- Wiping the boot USB stick from running ESXi: `dd`, `partedUtil mklabel`, `esxcli
  storage core device set --state off`, `detached add` all fail with "Read-only file
  system" or "device is busy by VMkernel". ESXi protects its own boot device while
  running. Either boot something else first, or pull the stick.
