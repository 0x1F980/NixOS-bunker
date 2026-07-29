{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "bunker-zones-tui";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;
  meta = {
    description = "Minimal ratatui UI for AppVM/Disposable CRUD via zones.json";
    mainProgram = "bunker-zones-tui";
    license = lib.licenses.mit;
  };
}
