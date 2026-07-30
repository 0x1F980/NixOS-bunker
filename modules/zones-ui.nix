# Host UI: Qubes-like folders — AppVMs / Disposables / Templates / Service.
# Launcher title = "<name> · <type>" (no product-name prefix).
{
  lib,
  pkgs,
  bunkerAppZones ? import ../config/zones.nix,
  bunkerPublicZones ? bunkerAppZones,
  bunkerDeniableZones ? { },
  ...
}:

let
  colors = import ../config/colors.nix;
  templateNames = [
    "desktop"
    "dev"
    "browser"
    "radio"
  ];

  qubeType =
    zone:
    let
      k = zone.kind or null;
      disp = zone.disposable or false;
      iso = (zone.template or "") == "iso" || ((zone.iso or "") != "");
    in
    if k == "template" then
      "template"
    else if disp || k == "disposable" then
      "disposable"
    else if iso then
      "appvm"
    else
      (k or "appvm");

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

  # Nuclear trefoil for panic · service
  nuclearIcon = pkgs.writeText "bunker-panic-nuclear.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
      <rect width="128" height="128" rx="16" fill="#1a0000"/>
      <circle cx="64" cy="64" r="56" fill="#cc0000"/>
      <circle cx="64" cy="64" r="14" fill="#1a0000"/>
      <path d="M64 18 L78 52 L50 52 Z" fill="#edd400"/>
      <path d="M98 90 L64 78 L90 52 Z" fill="#edd400" transform="rotate(120 64 64)"/>
      <path d="M30 90 L64 78 L38 52 Z" fill="#edd400" transform="rotate(240 64 64)"/>
      <circle cx="64" cy="64" r="8" fill="#edd400"/>
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
      icon ? null,
    }:
    let
      resolvedIcon = if icon != null then icon else (mkIcon id colorName);
    in
    pkgs.makeDesktopItem {
      name = "qube-${id}";
      desktopName = title;
      inherit comment exec terminal;
      icon = "${resolvedIcon}";
      categories = [
        category
        "System"
      ];
      keywords = [
        "qube"
        "zone"
      ]
      ++ keywords;
    };

  mkZoneLauncher =
    name: zone:
    let
      typ = qubeType zone;
      iso = (zone.template or "") == "iso" || ((zone.iso or "") != "");
      cat =
        if typ == "disposable" then
          "X-Qube-Disposable"
        else if typ == "template" then
          "X-Qube-Template"
        else
          "X-Qube-AppVM";
      isoNote = if iso then " · ISO/HVM" else "";
    in
    mkLauncher {
      id = name;
      title = "${name} · ${typ}";
      comment = "template=${zone.template}${isoNote} · ${zone.ip} · net=${zone.internet or "nym"} · color=${zone.color or "gray"}";
      exec = "bunker-zone-start ${name}";
      colorName = zone.color or "gray";
      category = cat;
      keywords = [
        typ
        zone.template
      ]
      ++ lib.optional iso "iso"
      ++ lib.optional iso "hvm";
    };

  # Static GNOME launchers: public zones only (deniable appear under /run/bunker/xdg when unlocked)
  zoneLaunchers = lib.mapAttrsToList mkZoneLauncher bunkerPublicZones;

  templateEdit = pkgs.writeShellScriptBin "bunker-template-edit" ''
    set -euo pipefail
    T="''${1:-}"
    ROOT="''${BUNKER_ROOT:-}"
    if [[ -z "$ROOT" ]]; then
      for d in "$HOME/nixos-bunker" /etc/bunker; do
        [[ -d "$d/templates" ]] && ROOT="$d" && break
      done
    fi
    ROOT="''${ROOT:-$HOME/nixos-bunker}"
    FILE="$ROOT/templates/''${T}.nix"
    if [[ -z "$T" || ! -f "$FILE" ]]; then
      echo "Usage: bunker-template-edit <desktop|dev|browser|radio>" >&2
      echo "Templates in $ROOT/templates:" >&2
      ls -1 "$ROOT/templates"/*.nix 2>/dev/null | xargs -n1 basename | sed 's/\.nix$//' >&2
      exit 1
    fi
    EDITOR="''${EDITOR:-vim}"
    if command -v kgx >/dev/null 2>&1; then
      exec kgx -e "$EDITOR" "$FILE"
    fi
    exec "$EDITOR" "$FILE"
  '';

  templateLaunchers = map (
    t:
    mkLauncher {
      id = "template-${t}";
      title = "${t} · template";
      comment = "Edit TemplateVM package set: templates/${t}.nix (AppVMs inherit this)";
      exec = "bunker-template-edit ${t}";
      colorName = "gray";
      category = "X-Qube-Template";
      keywords = [
        "template"
        t
      ];
    }
  ) templateNames;

  brokerTui = pkgs.callPackage ../tools/bunker-broker-tui { };
  zonesTui = pkgs.callPackage ../tools/bunker-zones-tui { };
  deniableTui = pkgs.callPackage ../tools/bunker-deniable-tui { };
  panicTui = pkgs.callPackage ../tools/bunker-panic-tui { };

  brokerLauncher = pkgs.writeShellScriptBin "bunker-broker" ''
    set -euo pipefail
    if [[ -z "''${BUNKER_ZONES_JSON:-}" ]]; then
      for p in "$HOME/nixos-bunker/config/zones.json" /etc/bunker/zones.json; do
        [[ -f "$p" ]] && export BUNKER_ZONES_JSON="$p" && break
      done
    fi
    BIN="${brokerTui}/bin/bunker-broker-tui"
    if command -v kgx >/dev/null 2>&1; then
      exec kgx -e "$BIN"
    elif command -v gnome-terminal >/dev/null 2>&1; then
      exec gnome-terminal -- "$BIN"
    else
      exec "$BIN"
    fi
  '';

  zonesLauncher = pkgs.writeShellScriptBin "bunker-zones" ''
    set -euo pipefail
    if [[ -z "''${BUNKER_ZONES_JSON:-}" ]]; then
      for p in "$HOME/nixos-bunker/config/zones.json" /etc/bunker/zones.json; do
        [[ -f "$p" ]] && export BUNKER_ZONES_JSON="$p" && break
      done
    fi
    BIN="${zonesTui}/bin/bunker-zones-tui"
    if command -v kgx >/dev/null 2>&1; then
      exec kgx -e "$BIN"
    elif command -v gnome-terminal >/dev/null 2>&1; then
      exec gnome-terminal -- "$BIN"
    else
      exec "$BIN"
    fi
  '';

  deniableLauncher = pkgs.writeShellScriptBin "bunker-deniable" ''
    set -euo pipefail
    if [[ -z "''${BUNKER_DENIABLE_JSON:-}" ]]; then
      for p in "$HOME/nixos-bunker/config/deniable-zones.json" /etc/bunker/deniable-zones.json; do
        [[ -f "$p" ]] && export BUNKER_DENIABLE_JSON="$p" && break
      done
    fi
    BIN="${deniableTui}/bin/bunker-deniable-tui"
    if command -v kgx >/dev/null 2>&1; then
      exec kgx -e "$BIN"
    elif command -v gnome-terminal >/dev/null 2>&1; then
      exec gnome-terminal -- "$BIN"
    else
      exec "$BIN"
    fi
  '';

  panicLauncher = pkgs.writeShellScriptBin "bunker-panic-ui" ''
    set -euo pipefail
    BIN="${panicTui}/bin/bunker-panic-tui"
    if command -v kgx >/dev/null 2>&1; then
      exec kgx -e "$BIN"
    elif command -v gnome-terminal >/dev/null 2>&1; then
      exec gnome-terminal -- "$BIN"
    else
      exec "$BIN"
    fi
  '';

  # Service / infra (netVM, usbVM, …) — not AppVMs but operator tools
  serviceLaunchers = [
    (mkLauncher {
      id = "net";
      title = "net · netvm";
      comment = "Egress broker 10.0.0.1 — start netVM";
      exec = "bunker-zone-start net";
      colorName = "black";
      category = "X-Qube-Service";
      keywords = [ "netvm" ];
    })
    (mkLauncher {
      id = "net-term";
      title = "net-term · netvm";
      comment = "SSH zone@10.0.0.1";
      exec = "bunker-term net";
      colorName = "black";
      category = "X-Qube-Service";
      keywords = [ "netvm" ];
    })
    (mkLauncher {
      id = "usb";
      title = "usb · usbvm";
      comment = "I/O broker 10.0.0.2 — start usbVM";
      exec = "bunker-zone-start usb";
      colorName = "purple";
      category = "X-Qube-Service";
      keywords = [ "usbvm" ];
    })
    (mkLauncher {
      id = "usb-term";
      title = "usb-term · usbvm";
      comment = "SSH zone@10.0.0.2";
      exec = "bunker-term usb";
      colorName = "purple";
      category = "X-Qube-Service";
      keywords = [ "usbvm" ];
    })
    (mkLauncher {
      id = "usb-attach";
      title = "usb-attach · usbvm";
      comment = "Attach device via usbVM into an AppVM";
      exec = "bunker-usb-gui attach";
      colorName = "purple";
      category = "X-Qube-Service";
      keywords = [ "usbvm" ];
    })
    (mkLauncher {
      id = "usb-detach";
      title = "usb-detach · usbvm";
      comment = "Detach USB from AppVM";
      exec = "bunker-usb-gui detach";
      colorName = "purple";
      category = "X-Qube-Service";
      keywords = [ "usbvm" ];
    })
    (mkLauncher {
      id = "voice";
      title = "voice · voicevm";
      comment = "Mic anonymizer broker 10.0.0.3 — start voiceVM";
      exec = "bunker-zone-start voice";
      colorName = "orange";
      category = "X-Qube-Service";
      keywords = [
        "voicevm"
        "chimera"
        "mic"
      ];
    })
    (mkLauncher {
      id = "voice-term";
      title = "voice-term · voicevm";
      comment = "SSH zone@10.0.0.3";
      exec = "bunker-term voice";
      colorName = "orange";
      category = "X-Qube-Service";
      keywords = [ "voicevm" ];
    })
    (mkLauncher {
      id = "vault";
      title = "vault · appvm";
      comment = "Air-gapped vault (no NIC)";
      exec = "bunker-zone-start vault";
      colorName = "gray";
      category = "X-Qube-AppVM";
      keywords = [ "vault" ];
    })
    (mkLauncher {
      id = "defaults";
      title = "defaults · service";
      comment = "ratatui — net/usb/voice/mat2 defaults";
      exec = "bunker-broker";
      colorName = "blue";
      category = "X-Qube-Service";
      keywords = [ "broker" ];
    })
    (mkLauncher {
      id = "zones";
      title = "zones · service";
      comment = "ratatui — AppVM/Disposable CRUD (zones.json)";
      exec = "bunker-zones";
      colorName = "green";
      category = "X-Qube-Service";
      keywords = [
        "crud"
        "qube"
        "zones"
      ];
    })
    (mkLauncher {
      id = "deniable";
      title = "deniable · service";
      comment = "ratatui — hide/show whole VMs via Shufflecake layers";
      exec = "bunker-deniable";
      colorName = "purple";
      category = "X-Qube-Service";
      keywords = [
        "shufflecake"
        "deniable"
        "hidden"
      ];
    })
    (mkLauncher {
      id = "panic";
      title = "panic · service";
      comment = "☢ destroy panic-flagged deniable zone keys + RAM wipe";
      exec = "bunker-panic-ui";
      colorName = "red";
      category = "X-Qube-Service";
      icon = nuclearIcon;
      keywords = [
        "panic"
        "nuclear"
        "wipe"
      ];
    })
    (mkLauncher {
      id = "killswitch";
      title = "killswitch · service";
      comment = "Enable app-VM WAN killswitch";
      exec = "bunker-killswitch enable";
      colorName = "red";
      category = "X-Qube-Service";
      keywords = [ "killswitch" ];
    })
    (mkLauncher {
      id = "help";
      title = "help · service";
      comment = "man bunker — operator manual";
      exec = "bunker-help";
      colorName = "gray";
      category = "X-Qube-Service";
      terminal = true;
      keywords = [
        "man"
        "manual"
        "help"
      ];
    })
  ];

  usbGui = pkgs.writeShellScriptBin "bunker-usb-gui" ''
    set -euo pipefail
    export PATH="${pkgs.zenity}/bin:${pkgs.coreutils}/bin:$PATH"
    OP="''${1:-attach}"
    ZONES="$(bunker-zone list 2>/dev/null | awk 'NR>1 {print $1}' || true)"
    [[ -n "$ZONES" ]] || ZONES=$'personal\nwork\nbrowse\nradio'
    mapfile -t _zones < <(printf '%s\n' "$ZONES")
    ZONE="$(zenity --list --title="USB $OP" --text="AppVM:" --column="zone" "''${_zones[@]}" 2>/dev/null || true)"
    [[ -n "''${ZONE:-}" ]] || exit 0
    DEVID="$(zenity --entry --title="USB $OP" --text="vid:pid" --entry-text="0bda:2838" 2>/dev/null || true)"
    [[ -n "''${DEVID:-}" ]] || exit 0
    if [[ "$OP" == "detach" ]]; then
      bunker-usb-detach "$ZONE" "$DEVID"
    else
      bunker-usb-attach "$ZONE" "$DEVID"
    fi
  '';

  # Desktop directories (folders in GNOME app grid)
  dirAppvm = pkgs.writeTextDir "share/desktop-directories/qubes-appvm.directory" ''
    [Desktop Entry]
    Version=1.0
    Type=Directory
    Name=AppVMs
    Comment=Persistent application qubes
    Icon=applications-system
  '';
  dirDisp = pkgs.writeTextDir "share/desktop-directories/qubes-disposable.directory" ''
    [Desktop Entry]
    Version=1.0
    Type=Directory
    Name=Disposables
    Comment=Disposable qubes (wipe after use)
    Icon=user-trash
  '';
  dirTmpl = pkgs.writeTextDir "share/desktop-directories/qubes-template.directory" ''
    [Desktop Entry]
    Version=1.0
    Type=Directory
    Name=Templates
    Comment=TemplateVM package sets (edit → rebuild AppVMs)
    Icon=folder
  '';
  dirSvc = pkgs.writeTextDir "share/desktop-directories/qubes-service.directory" ''
    [Desktop Entry]
    Version=1.0
    Type=Directory
    Name=Service
    Comment=netVM / usbVM / killswitch / defaults
    Icon=network-workgroup
  '';

  # Force qubes into folders (applications-merged)
  qubesMenu = pkgs.writeTextDir "etc/xdg/menus/applications-merged/qubes-bunker.menu" ''
    <!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
      "http://www.freedesktop.org/standards/menu-spec/menu-1.0.dtd">
    <Menu>
      <Name>Applications</Name>
      <Menu>
        <Name>AppVMs</Name>
        <Directory>qubes-appvm.directory</Directory>
        <Include><Category>X-Qube-AppVM</Category></Include>
      </Menu>
      <Menu>
        <Name>Disposables</Name>
        <Directory>qubes-disposable.directory</Directory>
        <Include><Category>X-Qube-Disposable</Category></Include>
      </Menu>
      <Menu>
        <Name>Templates</Name>
        <Directory>qubes-template.directory</Directory>
        <Include><Category>X-Qube-Template</Category></Include>
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

  environment.systemPackages = zoneLaunchers
  ++ templateLaunchers
  ++ serviceLaunchers
  ++ [
    usbGui
    pkgs.zenity
    brokerTui
    brokerLauncher
    zonesTui
    zonesLauncher
    deniableTui
    deniableLauncher
    panicTui
    panicLauncher
    templateEdit
    dirAppvm
    dirDisp
    dirTmpl
    dirSvc
    qubesMenu
  ];

  # Also drop menu into /etc for environments that only read there
  environment.etc."xdg/menus/applications-merged/qubes-bunker.menu".source =
    "${qubesMenu}/etc/xdg/menus/applications-merged/qubes-bunker.menu";

  environment.etc."bunker/colors.json".text = builtins.toJSON (
    lib.mapAttrs (_: v: {
      inherit (v) hex ansi bg;
    }) colors
  );

  environment.etc."bunker/qube-model".text = ''
    Qubes-like model on this host:
      Templates  — templates/*.nix (package sets); edit then nixos-rebuild
      AppVMs     — zones.json disposable=false (or kind=appvm)
      Disposables— zones.json disposable=true  (or kind=disposable)
      Service    — net/usb/voice / zones / deniable / panic / defaults / killswitch / help

    Manual:  man bunker   OR   /etc/bunker/MANUAL   OR   help · service

    Zone CRUD (prefer TUI/CLI — not hand-editing Nix modules):
      zones · service   OR   bunker-zones   OR   bunker-zone list|add|set|rm
      defaults · service — net/usb/voice/metadata (mat2) on|off per zone
      deniable · service — whole hidden VMs (Shufflecake layers)
      panic · service  — wipe panic-flagged deniable keys (☢)
      Hand-edit config/zones.json is OK (same SoT). Then: nixos-rebuild switch

    CRUD:
      bunker-zone list|add|set|rm|apps|usb|templates
      bunker-zone add myvm --template desktop          # AppVM
      bunker-zone add throwaway --template browser --disposable
      bunker-zone set myvm template=dev internet=i2p voice=on metadata=on
      bunker-zone add tails --template iso --iso /var/lib/bunker/isos/tails.iso --disposable
  '';
}
