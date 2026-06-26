# gigaplayer

A Nix flake that builds a **bootable, stateless x86_64 NixOS live image** whose
only job is to be a [Snapcast](https://github.com/badaix/snapcast) client.

- **Stateless by construction** — it boots as a live image (squashfs in RAM),
  nothing is installed to disk, every boot is a clean slate.
- **WiFi pre-configured** — credentials are *your* input, set from your own
  configuration, never committed to this repo.
- **SSH key only** — password authentication is disabled; you provide the
  authorized public key(s).

This repo is meant to be *consumed* as a flake. You keep your secrets and keys
in your own (private) configuration and point it at this flake.

## Quick start (your own flake)

Create a flake somewhere private and fill in your values:

```nix
{
  inputs.gigaplayer.url = "github:youruser/gigaplayer"; # or path:/path/to/this/repo

  outputs = { self, gigaplayer, ... }: {
        # nix build .#iso  ->  result/iso/*.iso
    packages.x86_64-linux.iso = gigaplayer.lib.mkIso {
      hostName = "livingroom";

      wifi = {
        ssid = "MyHomeNetwork";
        psk  = "correcthorsebatterystaple";   # see "WiFi secrets" below
      };

      ssh.authorizedKeys = [
        "ssh-ed25519 AAAA...yourkey... you@laptop"
      ];

      snapcast = {
        # host = "192.168.1.10";  # pin the server, or omit for mDNS discovery
        # soundcard = "default";  # ALSA device; run `snapclient -l` to list
      };
    };
  };
}
```

Then build and write it to a USB stick / boot medium:

```sh
nix build .#iso
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Boot the x86 machine from it. It joins WiFi, and `snapclient` starts and
connects to your Snapserver. SSH in with `ssh player@<ip>` (your key).

> Building an `x86_64-linux` image requires a Linux builder. On macOS use a
> remote/linux builder (e.g. `nix.linux-builder`, `nixos-anywhere`, a remote
> `--builders` host, or just build on any Linux box).

## Trying it as-is

This repo ships a demo image built from **placeholder** credentials in
[`example/settings.nix`](example/settings.nix) so it builds out of the box:

```sh
nix build .#iso        # uses placeholder wifi/ssh — not usable, just builds
nix flake check        # evaluates the module + example
```

## Options

All options live under `gigaplayer.*` (see
[`modules/gigaplayer.nix`](modules/gigaplayer.nix)):

| Option | Default | Description |
| --- | --- | --- |
| `wifi.ssid` | _(required)_ | WiFi network name. |
| `wifi.psk` | `null` | WiFi password (plaintext; ends up in the Nix store). |
| `wifi.pskFile` | `null` | Runtime file holding the PSK, kept out of the store. |
| `wifi.hidden` | `false` | Set for non-broadcast networks. |
| `ssh.authorizedKeys` | `[]` | Authorized SSH public keys (**at least one required**). |
| `user.name` | `"player"` | Login user that owns the SSH keys. |
| `snapcast.host` | `null` | Snapserver address; `null` = mDNS auto-discovery. |
| `snapcast.port` | `1704` | Snapserver stream port. |
| `snapcast.soundcard` | `null` | ALSA output device. |
| `snapcast.name` | `null` | Client id (`--hostID`). |
| `snapcast.extraArgs` | `[]` | Extra `snapclient` arguments. |
| `hostName` | `"gigaplayer"` | System hostname. |
| `console.autologin` | `true` | Keep the live image's passwordless console autologin. |

## WiFi secrets

By default `wifi.psk` is a plaintext string. Because the image is fully
declarative, that string is written **world-readable into the Nix store** on
the device. For a private home appliance that is usually acceptable.

To keep the PSK out of the store, use `wifi.pskFile` instead — a path to a file
*on the running device* containing one line:

```
psk_gigaplayer=your-wifi-password
```

Since the image is stateless (RAM-only), you would need to provide that file at
runtime (e.g. baked onto a second partition, an initrd secret, or a
secrets-management tool such as sops-nix / agenix layered on top). `wifi.psk`
is the simpler choice unless you specifically need this.

## Security notes

- **Console access**: the live image autologins a passwordless `nixos` user
  with `sudo`. Anyone with physical access + keyboard gets root. Set
  `console.autologin = false;` to disable it and rely solely on SSH.
- **Passwordless sudo**: the SSH key holder can `sudo` without a password
  (they are already trusted via the key). Override with
  `security.sudo.wheelNeedsPassword = true;` if undesired.

## How it works

- `nixosModules.gigaplayer` — the reusable module (options + config above). A
  plain NixOS module, so it also composes into a disk-installed system if you
  ever want persistence instead of a live image.
- `lib.mkIso settings` — wraps that module with the upstream
  `installation-cd-minimal` live base and returns the ISO derivation.
- `packages.x86_64-linux.iso` — the demo image from `example/settings.nix`.
