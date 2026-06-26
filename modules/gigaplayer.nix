{ config, lib, pkgs, ... }:

let
  cfg = config.gigaplayer;

  # Identifier used inside `wifi.pskFile` to look up the PSK at runtime.
  pskExtName = "psk_gigaplayer";

  snapclientArgs = lib.concatStringsSep " " (
    lib.optional (cfg.snapcast.host != null) "--host ${cfg.snapcast.host}"
    ++ [ "--port ${toString cfg.snapcast.port}" ]
    ++ lib.optional (cfg.snapcast.soundcard != null) "--soundcard ${cfg.snapcast.soundcard}"
    ++ lib.optional (cfg.snapcast.name != null) "--hostID ${cfg.snapcast.name}"
    ++ cfg.snapcast.extraArgs
  );
in
{
  options.gigaplayer = {
    enable = lib.mkEnableOption "the gigaplayer stateless Snapcast client appliance";

    hostName = lib.mkOption {
      type = lib.types.str;
      default = "gigaplayer";
      description = "System hostname.";
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
        description = ''
          Client id reported to the server (snapclient `--hostID`). Defaults
          to deriving one from the hardware/hostname when `null`.
        '';
      };

      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra command-line arguments passed to snapclient.";
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

    networking.hostName = cfg.hostName;

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

    environment.systemPackages = with pkgs; [ snapcast alsa-utils ];

    systemd.services.snapclient = {
      description = "Snapcast client";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "sound.target" ];
      wants = [ "network.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.snapcast}/bin/snapclient ${snapclientArgs}";
        Restart = "always";
        RestartSec = 5;
        DynamicUser = true;
        SupplementaryGroups = [ "audio" ];
        # Light hardening (snapclient only needs the network and /dev/snd).
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectControlGroups = true;
        ProtectKernelTunables = true;
        NoNewPrivileges = true;
      };
    };
  };
}
