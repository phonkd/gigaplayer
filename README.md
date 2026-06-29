# gigaplayer

Bootable NixOS live USB that runs a Snapcast client. Clean slate every boot.

## Usage from your own flake

```nix
packages.x86_64-linux.iso = gigaplayer.lib.mkIso {
  hostName = "livingroom";            # optional, defaults to DMI product name
  wifi = {
    ssid = "MyNetwork";
    psk = "hynter2";               # your wifi password
    # pskFile = "/run/secrets/wifi.env";
  };
  ssh = {
    authorizedKeys = [ "ssh-ed25519 AAA..." ];
  };
  snapcast = {
    host = "192.168.1.100";           # pin a server, or omit for mDNS
    # name = "Living Room";
  };
};
```

```bash
nex build .#iso
```

## Options

| Option                    | Required | Description                          |
|------------------------|--------------|----------------------------------|
| hostName                    | no       | Defaults to DOI product name             |
| wifi.ssid                   | yes      | WiFi network name                       |
| wifi.psk                    | yes      | WiFi password (PKS)                  |
| wifi.pskFile              | no       | Path to runtime psk file              |
| ssh.authorizedKeys          | yes      | List of authorized public keys        |
| snapcast.host               | no       | Snapcast server IP (if pinned)         |
| snapcast.name               | no       | Speaker name for Snapcast           |
| bluetooth.enable            | no       | A2DP sink, pair via bluetoothctl SSH |
| librespot.enable             | no       | Spotify Connect receiver                |

## Why

Got an old x86_64 box or thin client? Plug in a USB, boot, it's a streaming audio endpoint. No disk install, no state, no surprises.