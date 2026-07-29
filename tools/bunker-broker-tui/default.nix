{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "bunker-broker-tui";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;
  meta = {
    description = "Minimal ratatui UI for netVM/usbVM/voiceVM 1→many zone defaults";
    mainProgram = "bunker-broker-tui";
    license = lib.licenses.mit;
  };
}
