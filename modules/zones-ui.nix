# Host UI: colored zone launchers + infra (net / usb / vault).
{
  lib,
  pkgs,
  bunkerAppZones ? import ../config/zones.nix,
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
    pkgs.writeText "bunker-zone-${name}.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" width="128" height="128">
        <rect width="128" height="128" rx="16" fill="${c.hex}"/>
        <text x="64" y="78" text-anchor="middle" font-size="48"
              font-family="sans-serif" fill="#ffffff">${letter}</text>
      </svg>
    '';

  mkLauncher =
    {
      name,
      desktopName,
      comment,
      exec,
      colorName,
      keywords ? [ ],
    }:
    let
      icon = mkIcon name colorName;
    in
    pkgs.makeDesktopItem {
      inherit name desktopName comment exec;
      icon = "${icon}";
      categories = [
        "System"
        "Network"
      ];
      keywords = [
        "bunker"
        "zone"
      ]
      ++ keywords;
    };

  mkAppLauncher =
    name: zone:
    let
      colorName = zone.color or "gray";
      disp = if zone.disposable or false then " (disposable)" else "";
    in
    mkLauncher {
      name = "bunker-zone-${name}";
      desktopName = "Bunker: ${name}${disp}";
      comment = "${colorName} · ${zone.template} · ${zone.ip} · net=${zone.internet or "proxy"}";
      exec = "bunker-zone-start ${name}";
      inherit colorName;
      keywords = [
        colorName
        "app"
      ];
    };

  appLaunchers = lib.mapAttrsToList mkAppLauncher bunkerAppZones;

  # Infrastructure brokers (not in zones.json)
  brokerTui = pkgs.callPackage ../tools/bunker-broker-tui { };

  # Opens ratatui in a terminal window (clickable from GNOME)
  brokerLauncher = pkgs.writeShellScriptBin "bunker-broker" ''
    set -euo pipefail
    # Writable source of truth (etc copy is read-only)
    if [[ -z "''${BUNKER_ZONES_JSON:-}" ]]; then
      for p in \
        "$HOME/nixos-bunker/config/zones.json" \
        /etc/bunker/zones.json
      do
        if [[ -f "$p" ]]; then
          export BUNKER_ZONES_JSON="$p"
          break
        fi
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

  infraLaunchers = [
    (mkLauncher {
      name = "bunker-broker-tui";
      desktopName = "Bunker: net + USB defaults";
      comment = "ratatui — set 1→many net/usb defaults for all zones";
      exec = "bunker-broker";
      colorName = "blue";
      keywords = [
        "broker"
        "net"
        "usb"
        "ratatui"
        "defaults"
      ];
    })
    (mkLauncher {
      name = "bunker-infra-net";
      desktopName = "Bunker: net (egress)";
      comment = "Start netVM 10.0.0.1 — Nym/i2p/Tor SOCKS for all zones";
      exec = "bunker-zone-start net";
      colorName = "black";
      keywords = [
        "net"
        "nym"
        "tor"
        "i2p"
      ];
    })
    (mkLauncher {
      name = "bunker-infra-net-term";
      desktopName = "Bunker: net terminal";
      comment = "SSH into netVM (zone@10.0.0.1)";
      exec = "bunker-term net";
      colorName = "black";
      keywords = [
        "net"
        "term"
      ];
    })
    (mkLauncher {
      name = "bunker-infra-usb";
      desktopName = "Bunker: usb (I/O)";
      comment = "Start usbVM 10.0.0.2 — USB broker 1→many";
      exec = "bunker-zone-start usb";
      colorName = "purple";
      keywords = [
        "usb"
        "io"
      ];
    })
    (mkLauncher {
      name = "bunker-infra-usb-term";
      desktopName = "Bunker: usb terminal";
      comment = "SSH into usbVM (zone@10.0.0.2)";
      exec = "bunker-term usb";
      colorName = "purple";
      keywords = [
        "usb"
        "term"
      ];
    })
    (mkLauncher {
      name = "bunker-infra-usb-attach";
      desktopName = "Bunker: USB attach…";
      comment = "Attach a device from usbVM into an app zone";
      exec = "bunker-usb-gui attach";
      colorName = "purple";
      keywords = [
        "usb"
        "attach"
      ];
    })
    (mkLauncher {
      name = "bunker-infra-usb-detach";
      desktopName = "Bunker: USB detach…";
      comment = "Release USB from an app zone (stays on usbVM)";
      exec = "bunker-usb-gui detach";
      colorName = "purple";
      keywords = [
        "usb"
        "detach"
      ];
    })
    (mkLauncher {
      name = "bunker-infra-vault";
      desktopName = "Bunker: vault";
      comment = "Start vault (air-gapped, no NIC)";
      exec = "bunker-zone-start vault";
      colorName = "gray";
      keywords = [ "vault" ];
    })
    (mkLauncher {
      name = "bunker-infra-killswitch";
      desktopName = "Bunker: killswitch on";
      comment = "Block app-VM WAN; allow only netVM egress";
      exec = "bunker-killswitch enable";
      colorName = "red";
      keywords = [ "killswitch" ];
    })
  ];

  usbGui = pkgs.writeShellScriptBin "bunker-usb-gui" ''
    set -euo pipefail
    export PATH="${pkgs.zenity}/bin:${pkgs.coreutils}/bin:$PATH"
    OP="''${1:-attach}"
    ZONES="$(bunker-zone list 2>/dev/null | awk 'NR>1 {print $1}' || true)"
    if [[ -z "$ZONES" ]]; then
      ZONES=$'personal\nwork\nbrowse\nradio'
    fi
    ZONE="$(zenity --list --title="Bunker USB $OP" --text="App zone:" \
      --column="zone" $ZONES 2>/dev/null || true)"
    [[ -n "''${ZONE:-}" ]] || exit 0
    DEVID="$(zenity --entry --title="Bunker USB $OP" \
      --text="USB vendor:product (hex), e.g. 0bda:2838" \
      --entry-text="0bda:2838" 2>/dev/null || true)"
    [[ -n "''${DEVID:-}" ]] || exit 0
    if [[ "$OP" == "detach" ]]; then
      bunker-usb-detach "$ZONE" "$DEVID"
      zenity --info --text="Detached $DEVID from $ZONE" || true
    else
      bunker-usb-attach "$ZONE" "$DEVID"
      zenity --info --text="Attached $DEVID → $ZONE (via usbVM)" || true
    fi
  '';

  legend = pkgs.writeTextDir "share/doc/bunker/labels.md" ''
    # Bunker zone labels

    Infra: **net** (egress) · **usb** (I/O broker) · **vault** (airgap)

    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: zone:
        let
          c = colors.${zone.color or "gray"} or colors.gray;
        in
        "- **${name}** `${zone.color or "gray"}` ${c.hex} — template=${zone.template} internet=${zone.internet or "proxy"}"
      ) bunkerAppZones
    )}
  '';
in
{
  environment.systemPackages = appLaunchers ++ infraLaunchers ++ [
    legend
    usbGui
    pkgs.zenity
    brokerTui
    brokerLauncher
  ];
  environment.etc."bunker/colors.json".text = builtins.toJSON (
    lib.mapAttrs (_: v: {
      inherit (v) hex ansi bg;
    }) colors
  );
}
