# Build a minimal tinted XCursor theme for a bunker zone label color.
# Used by NixOS app zones so the guest mouse cursor matches zone.color.
{
  pkgs,
  colorName,
  hex,
}:

pkgs.runCommand "bunker-cursor-${colorName}"
  {
    nativeBuildInputs = [
      pkgs.imagemagick
      pkgs.xorg.xcursorgen
    ];
  }
  ''
    set -euo pipefail
    THEME="bunker-${colorName}"
    OUT="$out/share/icons/$THEME"
    mkdir -p "$OUT/cursors" "$OUT/cursors_src"

    cat > "$OUT/index.theme" <<EOF
    [Icon Theme]
    Name=$THEME
    Comment=Bunker zone cursor (${colorName})
    Inherits=
    EOF

    make_ptr() {
      local sz="$1" hot="$2"
      ${pkgs.imagemagick}/bin/convert -size "''${sz}x''${sz}" xc:none \
        -fill '${hex}' -stroke '#111111' -strokewidth 1 \
        -draw "polygon ''${hot},''${hot} $((sz - hot)),$((sz / 2)) ''${hot},$((sz - hot)) ''${hot},$((sz / 2 + hot))" \
        "$OUT/cursors_src/left_ptr_''${sz}.png"
    }

    make_ptr 24 4
    make_ptr 32 5

    cat > "$OUT/cursors_src/left_ptr.cfg" <<EOF
    24 4 4 left_ptr_24.png
    32 5 5 left_ptr_32.png
    EOF

    ( cd "$OUT/cursors_src" && ${pkgs.xorg.xcursorgen}/bin/xcursorgen left_ptr.cfg "$OUT/cursors/left_ptr" )

    for alias in default arrow hand1 hand2 pointer text xterm sb_v_double_arrow sb_h_double_arrow; do
      ln -sfn left_ptr "$OUT/cursors/$alias"
    done

    rm -rf "$OUT/cursors_src"
  ''
