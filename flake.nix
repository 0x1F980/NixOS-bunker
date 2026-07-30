{
  description = "Hardened NixOS microVM workstation — not Qubes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    microvm.url = "github:microvm-nix/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      microvm,
      ...
    }:
    let
      lib = nixpkgs.lib;
      system = "x86_64-linux";
      appZones = import ./config/zones.nix;
      isIsoZone = zone: (zone.template or "") == "iso" || ((zone.iso or "") != "");
      nixosAppZones = lib.filterAttrs (_: z: !(isIsoZone z)) appZones;

      mkGuest =
        name: modules:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit self;
            bunkerZone = name;
            bunkerAppZones = appZones;
          };
          modules = [
            microvm.nixosModules.microvm
            ./modules/guests/microvm-base.nix
            (
              { ... }:
              {
                networking.hostName = name;
              }
            )
          ]
          ++ modules;
        };

      guests = {
        net = mkGuest "net" [ ./modules/guests/net.nix ];
        usb = mkGuest "usb" [ ./modules/guests/usb.nix ];
        voice = mkGuest "voice" [ ./modules/guests/voice.nix ];
        vault = mkGuest "vault" [ ./modules/guests/vault.nix ];
      }
      // lib.mapAttrs (
        name: zone:
        mkGuest name [
          (import ./modules/guests/mk-app-zone.nix {
            inherit name zone;
          })
        ]
      ) nixosAppZones;

      zonePackages = lib.mapAttrs' (name: guest: {
        name = "zone-${name}";
        value = guest.config.microvm.declaredRunner;
      }) guests;
    in
    {
      inherit appZones;

      nixosConfigurations = {
        host = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit self microvm;
            bunkerAppZones = appZones;
            bunkerPublicZones = appZones;
          };
          modules = [
            microvm.nixosModules.host
            ./hosts/bunker/configuration.nix
            ./hosts/bunker/hardware-configuration.nix
            ./hardware/generic-x86_64.nix
            (
              { ... }:
              {
                nixpkgs.hostPlatform = system;
              }
            )
          ];
        };
      }
      // guests;

      packages.${system} = zonePackages // {
        default = (import nixpkgs { inherit system; }).writeText "bunker-readme" ''
          nixos-rebuild switch --flake .#host
          bunker
        '';
      };

      apps.${system} = lib.mapAttrs (_: drv: {
        type = "app";
        program = "${drv}/bin/microvm-run";
      }) zonePackages;
    };
}
