# Host UI: zone launchers + single bunker TUI. Minimal.
{
  lib,
  pkgs,
  bunkerPublicZones ? import ../config/zones.nix,
  ...
}:

let
  colors = import ../config/colors.nix;

  mkIcon =
    name: colorName:
    let
      c = colors.${colorName} or colors.gray;
      letter = lib.toUpper (builtins.substring 0 1 name);
    in
    pkgs.writeText "qube-${name}.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" width="128" height="128">
        <rect width="128" height="128" rx="16" fill="${c.hex}"/>
        <text x="64" y="78" text-anchor="middle" font-size="48"
              font-family="sans-serif" fill="#ffffff">${letter}</text>
      </svg>
    '';

  mkLauncher =
    {
      id,
      title,
      comment,
      exec,
      colorName,
      category,
      keywords ? [ ],
      terminal ? false,
    }:
    pkgs.makeDesktopItem {
      name = "qube-${id}";
      desktopName = title;
      genericName = comment;
      inherit comment exec;
      icon = mkIcon id colorName;
      categories = [ category ];
      inherit keywords terminal;
    };

  # Skip invisible zones on static GNOME grid (unlocked via bunker-sflc → /run/bunker/xdg)
  visibleZones = lib.filterAttrs (_: z: !(z.invisible or false)) bunkerPublicZones;

  zoneLaunchers = lib.mapAttrsToList (
    name: zone:
    let
      kind = zone.kind or (if zone.disposable or false then "disposable" else "appvm");
      cat =
        if kind == "disposable" || zone.disposable or false then
          "X-Qube-Disposable"
        else
          "X-Qube-AppVM";
    in
    mkLauncher {
      id = name;
      title = "${name} · ${kind}";
      comment = "zone start";
      exec = "bunker-zone-start ${name}";
      colorName = zone.color or "gray";
      category = cat;
      keywords = [ name ];
    }
  ) visibleZones;

  bunkerTui = pkgs.callPackage ../tools/bunker-tui { };

  bunkerLauncher = pkgs.writeShellScriptBin "bunker" ''
    set -euo pipefail
    if [[ -z "''${BUNKER_ZONES_JSON:-}" ]]; then
      for p in "$HOME/NixOS-bunker/config/zones.json" "$HOME/nixos-bunker/config/zones.json" /etc/bunker/zones.json; do
        [[ -f "$p" ]] && export BUNKER_ZONES_JSON="$p" && break
      done
    fi
    BIN="${bunkerTui}/bin/bunker-tui"
    if command -v kgx >/dev/null 2>&1; then
      exec kgx -e "$BIN"
    elif command -v gnome-terminal >/dev/null 2>&1; then
      exec gnome-terminal -- "$BIN"
    else
      exec "$BIN"
    fi
  '';

  serviceLaunchers = [
    (mkLauncher {
      id = "net";
      title = "net · netvm";
      comment = "Egress broker";
      exec = "bunker-zone-start net";
      colorName = "black";
      category = "X-Qube-Service";
    })
    (mkLauncher {
      id = "usb";
      title = "usb · usbvm";
      comment = "USB broker";
      exec = "bunker-zone-start usb";
      colorName = "purple";
      category = "X-Qube-Service";
    })
    (mkLauncher {
      id = "voice";
      title = "voice · voicevm";
      comment = "Mic anonymizer";
      exec = "bunker-zone-start voice";
      colorName = "orange";
      category = "X-Qube-Service";
    })
    (mkLauncher {
      id = "bunker";
      title = "bunker · host";
      comment = "Operator TUI";
      exec = "bunker";
      colorName = "blue";
      category = "X-Qube-Service";
    })
    (mkLauncher {
      id = "killswitch";
      title = "killswitch · service";
      comment = "WAN killswitch";
      exec = "bunker-killswitch enable";
      colorName = "red";
      category = "X-Qube-Service";
    })
  ];

  dirAppvm = pkgs.writeTextDir "share/desktop-directories/qubes-appvm.directory" ''
    [Desktop Entry]
    Type=Directory
    Name=Zones
    Icon=applications-system
  '';
  dirSvc = pkgs.writeTextDir "share/desktop-directories/qubes-service.directory" ''
    [Desktop Entry]
    Type=Directory
    Name=Service
    Icon=network-workgroup
  '';
  qubesMenu = pkgs.writeTextDir "etc/xdg/menus/applications-merged/qubes-bunker.menu" ''
    <!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
      "http://www.freedesktop.org/standards/menu-spec/menu-1.0.dtd">
    <Menu>
      <Name>Applications</Name>
      <Menu>
        <Name>Zones</Name>
        <Directory>qubes-appvm.directory</Directory>
        <Include><Category>X-Qube-AppVM</Category><Category>X-Qube-Disposable</Category></Include>
      </Menu>
      <Menu>
        <Name>Service</Name>
        <Directory>qubes-service.directory</Directory>
        <Include><Category>X-Qube-Service</Category></Include>
      </Menu>
    </Menu>
  '';
in
{
  environment.pathsToLink = [
    "/share/desktop-directories"
    "/etc/xdg/menus/applications-merged"
  ];

  environment.systemPackages = zoneLaunchers ++ serviceLaunchers ++ [
    bunkerTui
    bunkerLauncher
    dirAppvm
    dirSvc
    qubesMenu
  ];

  environment.etc."xdg/menus/applications-merged/qubes-bunker.menu".source =
    "${qubesMenu}/etc/xdg/menus/applications-merged/qubes-bunker.menu";

  environment.etc."bunker/colors.json".text = builtins.toJSON (
    lib.mapAttrs (_: v: {
      inherit (v) hex ansi bg;
    }) colors
  );

  environment.etc."bunker/qube-model".text = ''
    Minimal zone model:
      bunker · host  — TUI (brokers / zones / panic)
      zones.json     — apps[], mem, diskGb, invisible, layer, panic
      brokers        — net / usb / voice always visible
    man bunker
  '';
}
