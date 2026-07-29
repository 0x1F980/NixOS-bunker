{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "bunker-deniable-tui";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;
  meta = {
    description = "Ratatui UI for deniable (Shufflecake) whole-zone VMs";
    mainProgram = "bunker-deniable-tui";
    license = lib.licenses.mit;
  };
}
