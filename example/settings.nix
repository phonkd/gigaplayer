# Example `gigaplayer.*` settings with PLACEHOLDER credentials.
#
# This file only exists so the flake's demo image (`nix build .#iso`) is
# buildable out of the box. Do NOT put real secrets here. Instead, set these
# options from your own (private) configuration — see the README for the
# recommended `gigaplayer.lib.mkIso { ... }` pattern.
{
  hostName = "gigaplayer";

  wifi = {
    ssid = "REPLACE_ME_SSID";
    # Plaintext PSK ends up in the (world-readable) Nix store of the image.
    psk = "REPLACE_ME_WIFI_PASSWORD";
    # Or keep the PSK out of the store with a runtime file instead:
    #   pskFile = "/run/secrets/wifi.env";   # contents: psk_gigaplayer=...
  };

  ssh.authorizedKeys = [
    # Replace with your real public key(s):
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleReplaceMeReplaceMeReplaceMeReplc user@host"
  ];

  snapcast = {
    # host = "192.168.1.10";   # pin the server, or omit for mDNS discovery
    # soundcard = "default";   # ALSA device; run `snapclient -l` to list
    # name = "Living Room";    # defaults to DMI product name (e.g. "HP EliteBook 840 G5")
  };

  # bluetooth.enable = true;   # A2DP sink; pair with `bluetoothctl` over SSH

  # librespot = {
  #   enable = true;            # Spotify Connect receiver
  #   # name = "Living Room";  # defaults to DMI product name
  # };
}
