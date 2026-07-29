# Host UI: colored zone launchers + label legend (Qubes-inspired).
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
    name: zone:
    let
      colorName = zone.color or "gray";
      c = colors.${colorName} or colors.gray;
      icon = mkIcon name colorName;
      disp = if zone.disposable or false then " (disposable)" else "";
    in
    pkgs.makeDesktopItem {
      name = "bunker-zone-${name}";
      desktopName = "Bunker: ${name}${disp}";
      comment = "${colorName} · ${zone.template} · ${zone.ip} · net=${zone.internet or "proxy"}";
      exec = "bunker-zone-start ${name}";
      icon = "${icon}";
      categories = [
        "System"
        "Network"
      ];
      keywords = [
        "bunker"
        "zone"
        colorName
      ];
    };

  launchers = lib.mapAttrsToList mkLauncher bunkerAppZones;

  legend = pkgs.writeTextDir "share/doc/bunker/labels.md" ''
    # Bunker zone labels (Qubes-inspired)

    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: zone:
        let
          c = colors.${zone.color or "gray"} or colors.gray;
        in
        "- **${name}** `${zone.color or "gray"}` ${c.hex} — template=${zone.template} internet=${zone.internet or "proxy"} disposable=${
          if zone.disposable or false then "yes" else "no"
        }"
      ) bunkerAppZones
    )}
  '';
in
{
  environment.systemPackages = launchers ++ [ legend ];
  environment.etc."bunker/colors.json".text = builtins.toJSON (
    lib.mapAttrs (_: v: {
      inherit (v) hex ansi bg;
    }) colors
  );
}
