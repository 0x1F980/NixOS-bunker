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

      # Native ISA + KVM on that machine. AMD/Intel = x86_64, ARM = aarch64, RISC-V = riscv64.
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "riscv64-linux"
      ];

      # Flake attr for nixos-rebuild: .#host / .#host-aarch64 / .#host-riscv64
      hostAttrName =
        system:
        if system == "x86_64-linux" then
          "host"
        else if system == "aarch64-linux" then
          "host-aarch64"
        else if system == "riscv64-linux" then
          "host-riscv64"
        else
          "host-${system}";

      hardwareOverlay =
        system:
        if system == "x86_64-linux" then
          [ ./hardware/generic-x86_64.nix ]
        else if system == "aarch64-linux" then
          [ ./hardware/aarch64-generic.nix ]
        else if system == "riscv64-linux" then
          [ ./hardware/riscv64-generic.nix ]
        else
          [ ];

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

      # Non-x86 guest configs: net-aarch64, personal-riscv64, …
      guestsPrefixed =
        system:
        let
          suffix =
            if system == "aarch64-linux" then
              "aarch64"
            else if system == "riscv64-linux" then
              "riscv64"
            else
              system;
        in
        lib.mapAttrs' (name: value: {
          name = "${name}-${suffix}";
          inherit value;
        }) (mkGuests system);

      hostConfigs = lib.listToAttrs (
        map (system: {
          name = hostAttrName system;
          value = mkHost system;
        }) supportedSystems
      );

      readmeFor =
        system:
        (mkPkgs system).writeText "bunker-readme" ''
          Portable CPUs: x86_64 (AMD/Intel), aarch64 (ARM), riscv64 — native ISA + KVM each.
          Host:  nixos-rebuild switch --flake .#${hostAttrName system}
          Zones: nix run .#zone-<name>   # this machine's arch
          Docs:  docs/portability.md
        '';
    in
    {
      inherit appZones;

      nixosConfigurations = hostConfigs // guestsX86 // guestsPrefixed "aarch64-linux" // guestsPrefixed "riscv64-linux";

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
