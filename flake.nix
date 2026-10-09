{
  description = "uv, built with rostnix: one derivation per cargo unit";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    systems.url = "github:nix-systems/default";

    rostnix = {
      url = "github:draganm/rostnix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
    };

    # The newest release that the rustc of nixpkgs 26.05, 1.95, can build:
    # 0.12.6 raises rust-version to 1.96. Its Cargo.lock names crates.io
    # packages only, which is all rostnix fetches so far.
    uv-src = {
      url = "github:astral-sh/uv/0.12.5";
      flake = false;
    };
  };

  outputs = { nixpkgs, systems, rostnix, uv-src, ... }:
    let
      inherit (nixpkgs) lib;
      eachSystem = f:
        lib.genAttrs (import systems)
        (system: f nixpkgs.legacyPackages.${system});
    in {

      # Evaluating these runs cargo through builtins.exec, so every command
      # that touches them needs
      #   --option allow-unsafe-native-code-during-evaluation true
      packages = eachSystem (pkgs:
        let rustEnv = rostnix.lib.mkRustEnv { inherit pkgs; };
        in rec {
          uv = rustEnv.buildRustApplication {
            pname = "uv";
            version = (lib.importTOML "${uv-src}/crates/uv/Cargo.toml").package.version;
            src = uv-src;
            # `cargo build -p uv`: the uv and uvx binaries, and none of the
            # workspace's development tools.
            packages = [ "uv" ];
            meta.mainProgram = "uv";
          };
          default = uv;
        });
    };
}
