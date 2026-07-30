# Host UI: colored launchers + bunker TUI.
{
  lib,
  pkgs,
  bunkerPublicZones ? import ../config/zones.nix,
  ...
}:

let
  colors = import ../config/colors.nix;
  mk =
    id: title: exec: colorName: cat:
    pkgs.makeDesktopItem {
      name = "qube-${id}";
      desktopName = title;
      inherit exec;
      comment = title;
      icon = pkgs.writeText "qube-${id}.svg" ''
        <svg xmlns="http://www.w3.org/2000/svg" width="128" height="128">
          <rect width="128" height="128" rx="16" fill="${(colors.${colorName} or colors.gray).hex}"/>
          <text x="64" y="78" text-anchor="middle" font-size="48" fill="#fff">${lib.toUpper (builtins.substring 0 1 id)}</text>
        </svg>
      '';
      categories = [ cat ];
    };
  visible = lib.filterAttrs (_: z: !(z.invisible or false)) bunkerPublicZones;
  zoneLaunchers = lib.mapAttrsToList (
    name: zone:
    mk name "${name} · ${zone.kind or "appvm"}" "bunker-zone-start ${name}" (zone.color or "gray")
      "X-Qube-AppVM"
  ) visible;
  bunkerTui = pkgs.callPackage ../tools/bunker-tui { };
  bunker = pkgs.writeShellScriptBin "bunker" ''
    [[ -n ''${BUNKER_ZONES_JSON:-} ]] || for p in "$HOME/NixOS-bunker/config/zones.json" /etc/bunker/zones.json; do
      [[ -f $p ]] && export BUNKER_ZONES_JSON=$p && break
    done
    BIN=${bunkerTui}/bin/bunker-tui
    command -v kgx >/dev/null && exec kgx -e "$BIN" || exec "$BIN"
  '';
  services = [
    (mk "net" "net · netvm" "bunker-zone-start net" "black" "X-Qube-Service")
    (mk "usb" "usb · usbvm" "bunker-zone-start usb" "purple" "X-Qube-Service")
    (mk "bunker" "bunker · host" "bunker" "blue" "X-Qube-Service")
    (mk "killswitch" "killswitch" "bunker-killswitch enable" "red" "X-Qube-Service")
  ];
in
{
  environment.systemPackages = zoneLaunchers ++ services ++ [
    bunkerTui
    bunker
  ];
  environment.etc."bunker/colors.json".text = builtins.toJSON (
    lib.mapAttrs (_: v: {
      inherit (v) hex ansi bg;
    }) colors
  );
}
