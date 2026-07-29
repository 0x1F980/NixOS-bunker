{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "bunker-panic-tui";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;
  meta = {
    description = "Panic button ratatui for deniable zone key wipe";
    mainProgram = "bunker-panic-tui";
    license = lib.licenses.mit;
  };
}
