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

      # Default build arch for the host flake output; override via --system when needed.
      defaultSystem = "x86_64-linux";

      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          config = {
            allowUnfreePredicate =
              pkg:
              builtins.elem (lib.getName pkg) [
                "obsidian"
                "nvidia-x11"
                "nvidia-settings"
              ];
          };
        };

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

      guestNames = [
        "net"
        "usb"
        "personal"
        "work"
        "browse"
        "vault"
        "sdr"
      ];

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
                # Declarative microVMs from this flake
                microvm.vms = lib.genAttrs guestNames (name: {
                  flake = self;
                  updateFlake = "git+file://${self.outPath}";
                });
              }
            )
          ];
        };
    in
    {
      nixosConfigurations = {
        host = mkHost defaultSystem;
        host-aarch64 = mkHost "aarch64-linux";

        net = mkGuest "net" defaultSystem [ ./modules/guests/net.nix ];
        usb = mkGuest "usb" defaultSystem [ ./modules/guests/usb.nix ];
        personal = mkGuest "personal" defaultSystem [ ./modules/guests/personal.nix ];
        work = mkGuest "work" defaultSystem [ ./modules/guests/work.nix ];
        browse = mkGuest "browse" defaultSystem [ ./modules/guests/browse.nix ];
        vault = mkGuest "vault" defaultSystem [ ./modules/guests/vault.nix ];
        sdr = mkGuest "sdr" defaultSystem [ ./modules/guests/sdr.nix ];
      };

      # Convenience: packages from default system for scripts wrapping
      packages.${defaultSystem}.default = (mkPkgs defaultSystem).writeText "bunker-readme" ''
        Build host: nixos-rebuild switch --flake .#host
        Start zones: ./scripts/zone-start.sh
      '';
    };
}
