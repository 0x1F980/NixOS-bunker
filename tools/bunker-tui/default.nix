{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "bunker-tui";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;
  meta = {
    description = "Single host operator TUI for bunker zones";
    mainProgram = "bunker-tui";
    license = lib.licenses.mit;
  };
}
