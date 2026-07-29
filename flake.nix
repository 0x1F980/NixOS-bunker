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

      # User-editable AppVM registry (templates + disposables)
      appZones = import ./config/zones.nix;

      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          config = {
            allowUnfreePredicate =
              pkg: builtins.elem (lib.getName pkg) [ "obsidian" ];
          };
        };

      mkGuest =
        name: system: modules:
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

      mkAppGuest =
        name: zone:
        mkGuest name defaultSystem [
          (import ./modules/guests/mk-app-zone.nix {
            inherit name zone;
          })
        ];

      # Host does NOT embed all guest flakes (avoids building every zone into host closure).
      mkHost =
        system:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit self microvm;
            bunkerAppZones = appZones;
          };
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

      # Fixed infrastructure VMs
      systemGuests = {
        net = mkGuest "net" defaultSystem [ ./modules/guests/net.nix ];
        usb = mkGuest "usb" defaultSystem [ ./modules/guests/usb.nix ];
        vault = mkGuest "vault" defaultSystem [ ./modules/guests/vault.nix ];
      };

      appGuests = lib.mapAttrs mkAppGuest appZones;

      guests = systemGuests // appGuests;

      guestNames = lib.attrNames guests;

      zonePackages = lib.listToAttrs (
        map (name: {
          name = "zone-${name}";
          value = guests.${name}.config.microvm.declaredRunner;
        }) guestNames
      );
    in
    {
      # Re-export for docs / nix eval .#appZones
      inherit appZones;

      nixosConfigurations = {
        host = mkHost defaultSystem;
        host-aarch64 = mkHost "aarch64-linux";
      }
      // guests;

      packages.${defaultSystem} = zonePackages
        // {
          default = (mkPkgs defaultSystem).writeText "bunker-readme" ''
            Zones CRUD: bunker-zone list|add|set|rm|apps|usb
            Colors:     bunker-zone colors ; bunker-term <zone>
            Edit file:  config/zones.json  (templates in templates/)
            Build host: nixos-rebuild switch --flake .#host
            Run zone:   bunker-zone-start personal
            Wipe disp.: bunker-wipe browse
          '';
        };

      apps.${defaultSystem} = lib.mapAttrs (name: drv: {
        type = "app";
        program = "${drv}/bin/microvm-run";
      }) zonePackages;
    };
}
