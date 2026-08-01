{
  description = "Hardened NixOS microVM workstation — KVM on any Linux arch";

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
      # Broad hardware: same flake on PC, ARM board, RISC-V (where nixpkgs+KVM allow).
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "riscv64-linux"
      ];
      forAllSystems = lib.genAttrs systems;

      appZones = import ./config/zones.nix;
      deniableSlots = import ./config/slots.nix;
      isIsoZone = zone: (zone.template or "") == "iso" || ((zone.iso or "") != "");
      isBrokerZone =
        name: zone:
        name == "net" || name == "usb" || (zone.role or "") == "broker";
      # App zones only — net/usb are separate broker guests (still listed in zones.json for TUI kind/CRUD)
      nixosAppZones = lib.filterAttrs (
        name: z: !(isIsoZone z) && !(isBrokerZone name z)
      ) appZones;
      # Public zones + anonymous deniable slot d1 (radio only). Hidden names live only in SFLC.
      allBuildZones = nixosAppZones // deniableSlots;

      mkGuest =
        system: name: modules:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit self;
            bunkerZone = name;
            bunkerAppZones = allBuildZones;
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

      mkGuests =
        system:
        {
          net = mkGuest system "net" [ ./modules/guests/net.nix ];
          usb = mkGuest system "usb" [ ./modules/guests/usb.nix ];
        }
        // lib.mapAttrs (
          name: zone:
          mkGuest system name [
            (import ./modules/guests/mk-app-zone.nix {
              inherit name zone;
            })
          ]
        ) allBuildZones;

      zonePackages =
        system:
        lib.mapAttrs' (name: guest: {
          name = "zone-${name}";
          value = guest.config.microvm.declaredRunner;
        }) (mkGuests system);

      mkHost =
        system:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit self microvm;
            # Include deniable slots so host attaches vm-d1.. taps to br-bunker
            bunkerAppZones = allBuildZones;
            bunkerPublicZones = appZones;
          };
          modules = [
            microvm.nixosModules.host
            ./hosts/bunker/configuration.nix
            ./hosts/bunker/hardware-configuration.nix
            ./hardware/default.nix
            (
              { ... }:
              {
                nixpkgs.hostPlatform = system;
              }
            )
          ];
        };

      # host-x86_64-linux, host-aarch64-linux, host-riscv64-linux
      hostConfigs = lib.listToAttrs (
        map (system: {
          name = "host-${system}";
          value = mkHost system;
        }) systems
      );

      # Guests as nixosConfigurations for the default (native) build machine naming:
      # also expose unqualified names for x86_64 for backwards compat, plus per-system.
      guestConfigs = lib.foldl' (
        acc: system:
        let
          gs = mkGuests system;
          prefixed = lib.mapAttrs' (n: v: {
            name = "${n}-${system}";
            value = v;
          }) gs;
          # Unprefixed aliases only for x86_64 (legacy `.#net`, `.#personal`)
          bare = if system == "x86_64-linux" then gs else { };
        in
        acc // prefixed // bare
      ) { } systems;
    in
    {
      inherit appZones deniableSlots systems;

      nixosConfigurations = hostConfigs
      // {
        # Convenience: `.#host` → x86_64; other arches: `.#host-aarch64-linux` etc.
        host = hostConfigs."host-x86_64-linux";
      }
      // guestConfigs;

      packages = forAllSystems (system: zonePackages system);

      apps = forAllSystems (
        system:
        lib.mapAttrs (_: drv: {
          type = "app";
          program = "${drv}/bin/microvm-run";
        }) (zonePackages system)
      );
    };
}
