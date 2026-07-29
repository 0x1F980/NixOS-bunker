{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "bunker-voice-tui";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;
  meta = {
    description = "Ratatui UI for voiceVM mic anonymizer 1→many zone defaults";
    mainProgram = "bunker-voice-tui";
    license = lib.licenses.mit;
  };
}
