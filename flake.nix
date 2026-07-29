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

      # Every Linux double nixpkgs exposes in flakes — that is the ceiling.
      # (Not "every chip ever made": only what NixOS/nixpkgs can target.)
      supportedSystems =
        let
          exposed = lib.filter (lib.hasSuffix "-linux") (lib.systems.flakeExposed or [ ]);
          # Extra Linux ISAs sometimes missing from flakeExposed but present in nixpkgs
          extra = [
            "x86_64-linux"
            "i686-linux"
            "aarch64-linux"
            "armv7l-linux"
            "armv6l-linux"
            "riscv64-linux"
            "riscv32-linux"
            "powerpc64le-linux"
            "powerpc64-linux"
            "powerpc-linux"
            "mipsel-linux"
            "mips64el-linux"
            "loongarch64-linux"
            "s390x-linux"
          ];
        in
        lib.unique (exposed ++ extra);

      cpuOf = system: lib.removeSuffix "-linux" system;

      # .#host for x86_64; .#host-aarch64 / .#host-riscv64 / .#host-loongarch64 / …
      hostAttrName =
        system: if system == "x86_64-linux" then "host" else "host-${cpuOf system}";

      hardwareOverlay =
        system:
        if system == "x86_64-linux" then
          [ ./hardware/generic-x86_64.nix ]
        else if system == "aarch64-linux" then
          [ ./hardware/aarch64-generic.nix ]
        else if system == "riscv64-linux" || system == "riscv32-linux" then
          [ ./hardware/riscv64-generic.nix ]
        else
          [ ./hardware/generic-linux.nix ];

      publicZones = import ./config/zones.nix;
      deniableZones = import ./config/deniable-zones.nix;
      # Guests + net SOCKS include deniable VMs; GNOME static launchers stay public-only
      appZones = publicZones // deniableZones;

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

      mkHost =
        system:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit self microvm;
            bunkerAppZones = appZones;
            bunkerPublicZones = publicZones;
            bunkerDeniableZones = deniableZones;
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
          ++ hardwareOverlay system;
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

      guestsPrefixed =
        system:
        lib.mapAttrs' (name: value: {
          name = "${name}-${cpuOf system}";
          inherit value;
        }) (mkGuests system);

      nonX86Systems = lib.filter (s: s != "x86_64-linux") supportedSystems;

      allPrefixedGuests = lib.foldl' (
        acc: system:
        acc // guestsPrefixed system
      ) { } nonX86Systems;

      hostConfigs = lib.listToAttrs (
        map (system: {
          name = hostAttrName system;
          value = mkHost system;
        }) supportedSystems
      );

      readmeFor =
        system:
        (mkPkgs system).writeText "bunker-readme" ''
          All nixpkgs Linux ISAs (see docs/portability.md).
          This machine: ${system}
          Host:  nixos-rebuild switch --flake .#${hostAttrName system}
          Zones: nix run .#zone-<name>
        '';
    in
    {
      inherit appZones;
      # Re-export for docs / scripts
      bunkerSupportedSystems = supportedSystems;

      nixosConfigurations = hostConfigs // guestsX86 // allPrefixedGuests;

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
