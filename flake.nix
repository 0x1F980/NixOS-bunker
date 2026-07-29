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

      # Host + guests for each arch. Same machine ISA required (KVM).
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

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
          ]
          ++ lib.optionals (system == "aarch64-linux") [ ./hardware/aarch64-generic.nix ]
          ++ lib.optionals (system == "x86_64-linux") [ ./hardware/generic-x86_64.nix ];
        };

      mkGuests =
        system:
        let
          systemGuests = {
            net = mkGuest "net" system [ ./modules/guests/net.nix ];
            usb = mkGuest "usb" system [ ./modules/guests/usb.nix ];
            vault = mkGuest "vault" system [ ./modules/guests/vault.nix ];
          };
          appGuests = lib.mapAttrs (
            name: zone:
            mkGuest name system [
              (import ./modules/guests/mk-app-zone.nix {
                inherit name zone;
              })
            ]
          ) appZones;
        in
        systemGuests // appGuests;

      mkZonePackages =
        system:
        lib.mapAttrs' (name: guest: {
          name = "zone-${name}";
          value = guest.config.microvm.declaredRunner;
        }) (mkGuests system);

      guestsX86 = mkGuests "x86_64-linux";
      guestsAarch64 = mkGuests "aarch64-linux";

      readmeFor =
        system:
        (mkPkgs system).writeText "bunker-readme" ''
          Portable: x86_64-linux and aarch64-linux (native ISA + KVM).
          Host:  nixos-rebuild switch --flake .#host          # x86_64
                 nixos-rebuild switch --flake .#host-aarch64  # aarch64
          Zones: nix run .#zone-<name>   # picks THIS machine's arch automatically
          CRUD:  bunker-zone list|add|set|rm|apps|usb
        '';
    in
    {
      inherit appZones;

      nixosConfigurations =
        {
          host = mkHost "x86_64-linux";
          host-aarch64 = mkHost "aarch64-linux";
        }
        # Short names = x86_64 (compat with existing docs/scripts)
        // guestsX86
        # Explicit aarch64 guest configs
        // lib.mapAttrs' (name: value: {
          name = "${name}-aarch64";
          inherit value;
        }) guestsAarch64;

      packages = lib.genAttrs supportedSystems (
        system:
        (mkZonePackages system)
        // {
          default = readmeFor system;
        }
      );

      apps = lib.genAttrs supportedSystems (
        system:
        lib.mapAttrs (name: drv: {
          type = "app";
          program = "${drv}/bin/microvm-run";
        }) (mkZonePackages system)
      );
    };
}
