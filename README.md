# gigaplayer

Bootable NIxOS live USB that runs a Snapcast client. Clean slate every boot.

## Usage from your own flake

```nix
packages.x86_64-linux.iso = gigaplayer.lib.mkIso {
  hostName = "livingroom";
  wifi = { ssid = "..."; password = "..."; };
  snapcast = { server = "192.168.1.100"; port = 1704; };
  sshKeys = [ "ssh-ed25519 AAA..." ];
};
```

```bash
nix build .#iso
```

## Options

| Option        | Required | Description                  |
|--------------|-----------|---------------------------|
| hostName      | yes      | Hostname for the live image   |
| wifi.ssid     | yes      | WiFi network name            |
| wifi.password | yes      | WiFi password               |
| snapcast.server | yes      | Snapcast server hostname/IP    |
| snapcast.port | no       | Default 1704                |
| sshKeys       | yes      | List of authorized public keys    |

## Why

Got an old x86_64 box or thin client? Plug in a USB, boot, it's a streaming audio endpoint. No disk install, no state, no surprises.
