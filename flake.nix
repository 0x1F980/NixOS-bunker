{
  description = "Hardened, reproducible, compartmentalized NixOS workstation (microVM) — not Qubes";

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
      defaultSystem = "x86_64-linux";

      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          config = {
            allowUnfreePredicate =
              pkg: builtins.elem (lib.getName pkg) [ "obsidian" ];
          };
        };

      guestNames = [
        "net"
        "usb"
        "personal"
        "work"
        "browse"
        "vault"
        "sdr"
      ];

      mkGuest =
        name: system: modules:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit self;
            bunkerZone = name;
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

      # Host does NOT embed all guest flakes (avoids building every zone into host closure).
      # Zones are on-demand via `nix run .#zone-<name>` / bunker-zone-start.
      mkHost =
        system:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit self microvm; };
          modules = [
            microvm.nixosModules.host
            ./hosts/bunker/configuration.nix
            ./hosts/bunker/hardware-configuration.nix
            (
              { ... }:
              {
                nixpkgs.hostPlatform = system;
              }
            )
          ];
        };

      guests = {
        net = mkGuest "net" defaultSystem [ ./modules/guests/net.nix ];
        usb = mkGuest "usb" defaultSystem [ ./modules/guests/usb.nix ];
        personal = mkGuest "personal" defaultSystem [ ./modules/guests/personal.nix ];
        work = mkGuest "work" defaultSystem [ ./modules/guests/work.nix ];
        browse = mkGuest "browse" defaultSystem [ ./modules/guests/browse.nix ];
        vault = mkGuest "vault" defaultSystem [ ./modules/guests/vault.nix ];
        sdr = mkGuest "sdr" defaultSystem [ ./modules/guests/sdr.nix ];
      };

      zonePackages = lib.listToAttrs (
        map (name: {
          name = "zone-${name}";
          value = guests.${name}.config.microvm.declaredRunner;
        }) guestNames
      );
    in
    {
      nixosConfigurations = {
        host = mkHost defaultSystem;
        host-aarch64 = mkHost "aarch64-linux";
      }
      // guests;

      packages.${defaultSystem} = zonePackages
        // {
          default = (mkPkgs defaultSystem).writeText "bunker-readme" ''
            Build host: nixos-rebuild switch --flake .#host
            Run zone:   nix run .#zone-net
                        bunker-zone-start personal
          '';
        };

      apps.${defaultSystem} = lib.mapAttrs (name: drv: {
        type = "app";
        program = "${drv}/bin/microvm-run";
      }) zonePackages;
    };
}
