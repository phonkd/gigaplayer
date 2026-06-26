{
  description = "gigaplayer — bootable, stateless x86 NixOS Snapcast client (live USB/ISO)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";

      # The live-ISO base: a minimal NixOS that runs entirely from a squashfs
      # in RAM. Nothing is installed to disk, so the system is stateless by
      # construction — every boot is a clean slate.
      isoBase = "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix";

      mkSystem = settings: nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          isoBase
          self.nixosModules.gigaplayer
          { image.baseName = nixpkgs.lib.mkDefault "gigaplayer"; }
          { gigaplayer = settings // { enable = true; }; }
        ];
      };
    in
    {
      # The reusable product. Import this in your own configuration and set
      # the `gigaplayer.*` options (see modules/gigaplayer.nix). It is a plain
      # NixOS module, so it also composes into non-ISO systems if you ever
      # want to install to disk instead.
      nixosModules.gigaplayer = import ./modules/gigaplayer.nix;
      nixosModules.default = self.nixosModules.gigaplayer;

      # Convenience builder: turn a `gigaplayer.*` settings attrset into a
      # bootable, stateless live ISO (x86_64-linux), pinned to this flake's
      # nixpkgs. This is the recommended entry point for downstream users —
      # they keep their credentials in their own flake, not in this repo.
      lib.mkIso = settings: (mkSystem settings).config.system.build.isoImage;

      # Demo image built from placeholder credentials so the flake is
      # buildable as-is. Build your *real* image with `lib.mkIso` from your
      # own flake (see README).
      packages.${system} = {
        iso = self.lib.mkIso (import ./example/settings.nix);
        default = self.packages.${system}.iso;
      };

      # Inspectable example system (placeholder credentials), handy for
      # `nix eval` / `nixos-rebuild build-vm`-style poking.
      nixosConfigurations.example = mkSystem (import ./example/settings.nix);
    };
}
