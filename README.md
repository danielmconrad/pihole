# pihole

Setup and config for Pi-hole on a Raspberry Pi 3B+ running Raspberry Pi OS Lite, hardwired to the network at `192.168.1.2`. A second Pi at `192.168.1.3` can be set up the same way, so one can be upgraded while the other keeps serving DNS.

Everything runs from your laptop over SSH. You don't need to clone this repo onto the Pi.

- Pi-hole is installed natively, without Docker. That uses less memory on a 1 GB Pi and works on both 32-bit and 64-bit Raspberry Pi OS.
- Blocklists (gravity) update automatically every day around 03:30–04:30 via a systemd timer.
- OS, kernel, and Pi-hole upgrades are manual, using `make upgrade`.
- Settings and blocklists live in this repo (`settings.conf`, `adlists.txt`), so every Pi gets the same config.

## Before you start

1. Flash Raspberry Pi OS Lite with Raspberry Pi Imager. In its settings, create a user, enable SSH, and add your public key. Plug the Pi into ethernet.
2. If an old device still holds `192.168.1.2`, turn it off before running setup. If you've SSH'd to that address before, clear the old host key with `ssh-keygen -R 192.168.1.2`.
3. Make sure `.2` and `.3` are outside the UDM's DHCP range. They are by default, but check under Settings > Networks.
4. Copy `.env.example` to `.env` and fill it in. `IP`, `NAME`, and `HOST` there pick the Pi that every `make` command targets.

## First-time setup

Find the Pi's current DHCP address (try `raspberrypi.local`, or look in the UniFi client list), then run:

```sh
make setup HOST=raspberrypi.local
```

`IP` and `NAME` come from `.env`. This command:

1. Installs your SSH public key on the Pi (`make ssh-key`), so after one password prompt the rest runs without asking again.
2. Upgrades the OS.
3. Sets the hostname and timezone.
4. Sets the static IP.
5. Installs Pi-hole unattended.
6. Applies `settings.conf` and `adlists.txt`.
7. Turns on the daily gravity timer.
8. Reboots onto the new IP and confirms that DNS is answering and ads are blocked.

The web UI is then at http://192.168.1.2/admin, using the password from `.env`.

Finally, point your network at the Pi. In UniFi, go to Settings > Networks > your LAN > DHCP Service Management > DNS Server and set `192.168.1.2`, plus `192.168.1.3` if you add a second Pi.

### Second Pi

```sh
make setup HOST=<its current address> IP=192.168.1.3 NAME=pihole2
```

## Day to day

Every command targets the Pi in `.env`. `IP` is the Pi's LAN address; `HOST` is where SSH connects and defaults to `IP`. DNS checks run on the Pi itself against `IP`, so setting `HOST` to a Tailscale name in `.env` lets every command work when you're away from home. Anything in `.env` can be overridden per command:

```sh
make status HOST=192.168.1.2
make upgrade HOST=pihole2.tailnet-name.ts.net IP=192.168.1.3
```

| Command | What it does |
| --- | --- |
| `make upgrade` | Upgrades OS packages and the kernel, then Pi-hole. Reboots and waits until DNS answers again. |
| `make upgrade-os` | Upgrades OS packages and the kernel only. Does not reboot. |
| `make upgrade-pihole` | Runs `pihole -up` only. |
| `make reboot` | Reboots and waits for DNS. |
| `make status` | Shows Pi-hole status, versions, the next gravity run, and whether a reboot is pending. |
| `make deploy` | Pushes edits to `settings.conf` or `adlists.txt` and applies them. Pi-hole restarts briefly, and gravity runs. |
| `make gravity` | Updates blocklists now. |
| `make check` | Confirms DNS is resolving and blocking. |
| `make ssh` | Opens a shell on the Pi. |
| `make ssh-key` | Installs your SSH public key on the Pi, if you're being asked for a password. |

If you have two Pis, upgrade them one after the other. Each `make upgrade` waits until its Pi is serving DNS again before it finishes:

```sh
make upgrade && make upgrade IP=192.168.1.3 HOST=192.168.1.3  # or its Tailscale name
```

## Notes

- `settings.conf` wins. Any setting listed there is reapplied on every `make deploy` and overwrites what you changed in the web UI. Settings that aren't listed stay editable in the UI.
- Blocklists: `make deploy` adds the URLs in `adlists.txt` and removes ones you've deleted from the file. Lists added by hand in the web UI are left alone.
- Pi-hole also has its own weekly gravity cron job (Sunday around 02:00). It overlaps with the daily timer and is harmless.
- The Pi resolves DNS through `1.1.1.1` rather than through itself, so upgrades still work if Pi-hole is broken.
- Kernel updates come through `apt` (`make upgrade-os`). Don't use `rpi-update`, which installs pre-release firmware.
