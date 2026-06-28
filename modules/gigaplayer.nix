{ config, lib, pkgs, ... }:

let
  cfg = config.gigaplayer;

  # Identifier used inside `wifi.pskFile` to look up the PSK at runtime.
  pskExtName = "psk_gigaplayer";

  # When true, route audio through PipeWire/WirePlumber (auto-switching
  # between speakers / HDMI / 3.5mm); when false, snapclient talks raw ALSA.
  usePipewire = cfg.audio.autoSwitch;

  snapclientBaseArgs = lib.concatStringsSep " " (
    lib.optional (cfg.snapcast.host != null) "--host ${cfg.snapcast.host}"
    ++ [ "--port ${toString cfg.snapcast.port}" ]
    ++ lib.optional (cfg.snapcast.soundcard != null) "--soundcard ${cfg.snapcast.soundcard}"
    ++ cfg.snapcast.extraArgs
  );

  # When name is set explicitly, pass it straight through. When null, use a
  # shell wrapper that reads the DMI product name at service-start time so the
  # client shows up in Snapserver as e.g. "HP EliteBook 840 G5".
  snapclientExecStart =
    if cfg.snapcast.name != null
    then "${pkgs.snapcast}/bin/snapclient ${snapclientBaseArgs} --hostID ${lib.escapeShellArg cfg.snapcast.name}"
    else
      "${pkgs.writeShellScript "snapclient-start" ''
        name=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
        [ -z "$name" ] && name=$(cat /sys/class/dmi/id/board_name 2>/dev/null)
        [ -z "$name" ] && name=$(hostname)
        exec ${pkgs.snapcast}/bin/snapclient ${snapclientBaseArgs} --hostID "$name"
      ''}";

  librespotBackend = if usePipewire then "pulseaudio" else "alsa";

  librespotExecStart =
    if cfg.librespot.name != null
    then "${pkgs.librespot}/bin/librespot --name ${lib.escapeShellArg cfg.librespot.name} --backend ${librespotBackend}"
    else
      "${pkgs.writeShellScript "librespot-start" ''
        name=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
        [ -z "$name" ] && name=$(cat /sys/class/dmi/id/board_name 2>/dev/null)
        [ -z "$name" ] && name=$(hostname)
        exec ${pkgs.librespot}/bin/librespot --name "$name" --backend ${librespotBackend}
      ''}";
in
{
  options.gigaplayer = {
    enable = lib.mkEnableOption "the gigaplayer stateless Snapcast client appliance";

    hostName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "living-room";
      description = ''
        System hostname. When `null` (the default), a oneshot service sets
        the hostname at boot from the DMI product name
        (`/sys/class/dmi/id/product_name`), so each device announces a
        distinct name on mDNS (e.g. `hp-elitebook-840-g5.local`).

        Set an explicit string to pin a friendly name instead.
      '';
    };

    wifi = {
      ssid = lib.mkOption {
        type = lib.types.str;
        example = "MyHomeNetwork";
        description = "SSID of the WiFi network to join.";
      };

      psk = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "correcthorsebatterystaple";
        description = ''
          WiFi pre-shared key as a plaintext string.

          WARNING: this value is written world-readable into the Nix store of
          the built image. For a private home appliance that is usually fine.
          To keep the secret out of the store, leave this `null` and use
          {option}`gigaplayer.wifi.pskFile` instead.

          Mutually exclusive with {option}`gigaplayer.wifi.pskFile`.
        '';
      };

      pskFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = "/run/secrets/wifi.env";
        description = ''
          Path to a file *on the running device* that holds the WiFi PSK,
          keeping it out of the Nix store. The file must contain a single
          line of the form:

          ```
          ${pskExtName}=your-wifi-password
          ```

          Mutually exclusive with {option}`gigaplayer.wifi.psk`.
        '';
      };

      hidden = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Set to true if the network does not broadcast its SSID.";
      };
    };

    ssh.authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "ssh-ed25519 AAAA... user@host" ];
      description = ''
        SSH public keys allowed to log in. Password authentication is
        disabled, so at least one key is required (otherwise you would be
        locked out of the device).
      '';
    };

    user.name = lib.mkOption {
      type = lib.types.str;
      default = "player";
      description = "Name of the unprivileged login user that owns the SSH keys.";
    };

    snapcast = {
      host = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "192.168.1.10";
        description = ''
          Address of the Snapserver to connect to. Leave `null` to
          auto-discover the server on the local network via mDNS/Avahi.
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 1704;
        description = "Snapserver stream port.";
      };

      soundcard = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "default:CARD=Device";
        description = ''
          ALSA sound device to play to (snapclient `--soundcard`). Leave
          `null` for the default device. Run `snapclient -l` over SSH to list
          available devices.
        '';
      };

      name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "Living Room";
        description = ''
          Display name reported to the Snapserver (snapclient `--hostID`).

          When `null` (the default), the name is read from the DMI product
          string at boot (`/sys/class/dmi/id/product_name`, falling back to
          the board name and then the hostname), so the client shows up as
          e.g. "HP EliteBook 840 G5" without any manual configuration.

          Set an explicit string to override that with a friendlier label
          such as `"Living Room"`.
        '';
      };

      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra command-line arguments passed to snapclient.";
      };
    };

    bluetooth = {
      enable = lib.mkEnableOption ''
        Bluetooth audio receiver. Enables the Bluetooth stack (BlueZ) and
        powers on the adapter at boot. Pair devices over SSH with
        {command}`bluetoothctl`. Audio routing is automatic when
        {option}`gigaplayer.audio.autoSwitch` is enabled (PipeWire handles
        A2DP natively)
      '';
    };

    librespot = {
      enable = lib.mkEnableOption "Spotify Connect receiver via librespot";

      name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "Living Room";
        description = ''
          Spotify Connect device name shown in the Spotify app. When `null`
          (the default), the name is read from the DMI product string at boot,
          using the same logic as {option}`gigaplayer.snapcast.name`.
        '';
      };
    };

    audio = {
      autoSwitch = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Route audio through PipeWire + WirePlumber so the output follows
          whatever is connected: built-in speakers by default, switching to
          HDMI or the 3.5mm jack when plugged in and back when removed.

          When false, snapclient talks to raw ALSA instead (lighter, no audio
          daemon). The codec's "Auto-Mute Mode" still handles speaker <-> 3.5mm
          switching, but HDMI does not auto-switch (pin it with
          {option}`gigaplayer.snapcast.soundcard`).
        '';
      };

      unmuteAtBoot = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Unmute outputs and set a volume on every sound card at boot.

          The image is stateless (RAM-only), so there is no saved ALSA mixer
          state to restore; many laptop codecs then come up muted / at zero.
          This runs `amixer` on each card at boot to unmute
          Master/Speaker/Headphone/PCM (leaving the codec's "Auto-Mute Mode"
          at its default so jack-sense switching keeps working).
        '';
      };

      volume = lib.mkOption {
        type = lib.types.ints.between 0 100;
        default = 80;
        description = ''
          Playback volume percent set on the hardware mixer at boot. With
          {option}`gigaplayer.audio.autoSwitch` enabled, WirePlumber manages
          the effective volume on top of this (adjust live with `wpctl`).
        '';
      };
    };

    console.autologin = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Keep the live image's passwordless console autologin (the `nixos`
        user with passwordless sudo). Set to false to harden against
        physical access; you then rely entirely on SSH.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.ssh.authorizedKeys != [ ];
        message = ''
          gigaplayer: password SSH auth is disabled, so
          gigaplayer.ssh.authorizedKeys must contain at least one key.
        '';
      }
      {
        assertion = !(cfg.wifi.psk != null && cfg.wifi.pskFile != null);
        message = "gigaplayer: set only one of gigaplayer.wifi.psk or gigaplayer.wifi.pskFile.";
      }
    ];

    networking.hostName = if cfg.hostName != null then cfg.hostName else "gigaplayer";

    # When hostName is null, override at boot from DMI so each device gets a
    # unique mDNS name without any per-device config.
    systemd.services.gigaplayer-set-hostname = lib.mkIf (cfg.hostName == null) {
      description = "Set hostname from DMI product name";
      wantedBy = [ "network-pre.target" ];
      before = [ "network-pre.target" "avahi-daemon.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        name=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
        [ -z "$name" ] && name=$(cat /sys/class/dmi/id/board_name 2>/dev/null)
        [ -z "$name" ] && exit 0
        # Lower-case and replace spaces/underscores with hyphens for a valid hostname.
        name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' _' '-' | tr -cd 'a-z0-9-')
        ${pkgs.util-linux}/bin/hostnamectl set-hostname "$name"
      '';
    };

    # --- WiFi (wpa_supplicant, declarative) -------------------------------
    # Firmware for most consumer WiFi chips ships as redistributable blobs.
    hardware.enableRedistributableFirmware = true;

    # The live-image base ships NetworkManager; it conflicts with declarative
    # wpa_supplicant networks, so turn it off. dhcpcd then handles DHCP once
    # wpa_supplicant has associated.
    networking.networkmanager.enable = lib.mkForce false;

    networking.wireless = {
      # mkForce so we win over any base/live-image default.
      enable = lib.mkForce true;
      secretsFile = lib.mkIf (cfg.wifi.pskFile != null) cfg.wifi.pskFile;
      networks.${cfg.wifi.ssid} =
        { hidden = cfg.wifi.hidden; }
        // lib.optionalAttrs (cfg.wifi.psk != null) { psk = cfg.wifi.psk; }
        // lib.optionalAttrs (cfg.wifi.pskFile != null) { pskRaw = "ext:${pskExtName}"; };
    };

    # --- SSH (key only) ---------------------------------------------------
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = lib.mkForce false;
        KbdInteractiveAuthentication = lib.mkForce false;
        PermitRootLogin = lib.mkForce "no";
      };
    };

    users.users.${cfg.user.name} = {
      isNormalUser = true;
      extraGroups = [ "wheel" "audio" ];
      openssh.authorizedKeys.keys = cfg.ssh.authorizedKeys;
    };

    # The only way in is the SSH key, so let the key holder sudo without a
    # password (they are already fully trusted). Override if undesired.
    security.sudo.wheelNeedsPassword = lib.mkDefault false;

    # Optionally drop the live image's passwordless console autologin.
    services.getty.autologinUser = lib.mkIf (!cfg.console.autologin) (lib.mkForce null);

    # --- Snapcast client --------------------------------------------------
    # mDNS so snapclient can find the server when no host is pinned.
    services.avahi = lib.mkIf (cfg.snapcast.host == null) {
      enable = true;
      nssmdns4 = true;
    };

    environment.systemPackages = with pkgs; [ snapcast alsa-utils ]
      ++ lib.optional usePipewire pkgs.wireplumber   # `wpctl` for debugging
      ++ lib.optional cfg.bluetooth.enable pkgs.bluez # `bluetoothctl` for pairing
      ++ lib.optional cfg.librespot.enable pkgs.librespot;

    # --- Audio routing (PipeWire) -----------------------------------------
    # System-wide PipeWire (no graphical/user session on this appliance).
    # WirePlumber then auto-routes the snapclient stream to the active output
    # and switches when HDMI / the 3.5mm jack are (un)plugged.
    security.rtkit.enable = lib.mkIf usePipewire true;
    services.pipewire = lib.mkIf usePipewire {
      enable = true;
      systemWide = true;
      alsa.enable = true; # ALSA `default` -> PipeWire, so snapclient routes through it
      alsa.support32Bit = false;
      pulse.enable = true;
    };

    # Don't pin a saved default sink; pick the best available output by
    # priority so a newly connected HDMI/headphone takes over (and hands back
    # when removed) instead of sticking to the previous one.
    environment.etc."wireplumber/wireplumber.conf.d/51-gigaplayer-autoswitch.conf" =
      lib.mkIf usePipewire {
        text = ''
          wireplumber.settings = {
            device.restore-default-target = false
            node.stream.restore-target = false
          }
        '';
      };

    # Stateless image: no saved mixer state, so unmute every card at boot
    # (runs before snapclient so audio is audible immediately).
    systemd.services.gigaplayer-alsa-unmute = lib.mkIf cfg.audio.unmuteAtBoot {
      description = "Unmute ALSA outputs (stateless image has no saved mixer state)";
      wantedBy = [ "multi-user.target" ];
      before = [ "snapclient.service" ] ++ lib.optional usePipewire "pipewire.service";
      path = [ pkgs.alsa-utils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        cards=$(aplay -l 2>/dev/null | sed -n 's/^card \([0-9]\+\):.*/\1/p' | sort -u)
        for c in $cards; do
          amixer -c "$c" sset 'Master'    ${toString cfg.audio.volume}% unmute || true
          amixer -c "$c" sset 'Speaker'   unmute || true
          amixer -c "$c" sset 'Headphone' unmute || true
          amixer -c "$c" sset 'PCM'       100% unmute || true
        done
      '';
    };

    # --- Bluetooth audio receiver -----------------------------------------
    hardware.bluetooth = lib.mkIf cfg.bluetooth.enable {
      enable = true;
      powerOnBoot = true;
    };

    # --- Spotify Connect (librespot) --------------------------------------
    systemd.services.librespot = lib.mkIf cfg.librespot.enable {
      description = "Spotify Connect receiver (librespot)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "sound.target" ]
        ++ lib.optional usePipewire "pipewire.service";
      wants = [ "network.target" ]
        ++ lib.optional usePipewire "pipewire.service";
      serviceConfig = {
        ExecStart = librespotExecStart;
        Restart = "always";
        RestartSec = 5;
        DynamicUser = true;
        SupplementaryGroups = [ "audio" ] ++ lib.optional usePipewire "pipewire";
        Environment = lib.optionals usePipewire [
          "PIPEWIRE_RUNTIME_DIR=/run/pipewire"
          "PULSE_RUNTIME_PATH=/run/pipewire/pulse"
        ];
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectControlGroups = true;
        ProtectKernelTunables = true;
        NoNewPrivileges = true;
      };
    };

    # --- Snapcast client --------------------------------------------------
    systemd.services.snapclient = {
      description = "Snapcast client";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "sound.target" ]
        ++ lib.optional usePipewire "pipewire.service";
      wants = [ "network.target" ]
        ++ lib.optional usePipewire "pipewire.service";
      serviceConfig = {
        ExecStart = snapclientExecStart;
        Restart = "always";
        RestartSec = 5;
        DynamicUser = true;
        # `audio` for raw /dev/snd; `pipewire` to reach the system-wide socket.
        SupplementaryGroups = [ "audio" ] ++ lib.optional usePipewire "pipewire";
        # Let the PipeWire client libs find the system-wide runtime sockets.
        Environment = lib.optionals usePipewire [
          "PIPEWIRE_RUNTIME_DIR=/run/pipewire"
          "PULSE_RUNTIME_PATH=/run/pipewire/pulse"
        ];
        # Light hardening (snapclient only needs the network and audio).
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectControlGroups = true;
        ProtectKernelTunables = true;
        NoNewPrivileges = true;
      };
    };
  };
}
