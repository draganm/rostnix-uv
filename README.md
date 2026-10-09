# rostnix-uv

[uv](https://github.com/astral-sh/uv) built with
[rostnix](https://github.com/draganm/rostnix): one Nix derivation per cargo
unit, and no Nix file to update when uv's `Cargo.lock` changes.

The flake has no source of its own. uv comes in as a flake input, pinned to
the 0.12.5 tag, and rostnix builds `cargo build -p uv` from it: 645 units
under uv's release profile, fat LTO and `panic = "abort"` included. The
result holds the `uv` and `uvx` binaries.

## Build and run

rostnix runs cargo during Nix evaluation through `builtins.exec`, which Nix
only provides when asked:

```bash
nix build -j 12 --option allow-unsafe-native-code-during-evaluation true
./result/bin/uv --version   # uv 0.12.5 (aarch64-apple-darwin)

nix run --option allow-unsafe-native-code-during-evaluation true . -- --version
```

With that option on, any Nix expression you evaluate can run programs as
you. Pass it per command, for flakes you trust, rather than enabling it in
`nix.conf`.

Every unit is a derivation, so Nix's `max-jobs` is the build's parallelism;
`-j` sets it for one command. With `max-jobs = 1` the units build one at a
time.

The first evaluation takes about a minute, while cargo downloads uv's
crates. The build took about ten minutes on a 14-core Apple Silicon machine,
more than half of it the fat-LTO link of `uv`.

### macOS with the sandbox on

Where `nix.conf` sets `sandbox` to `true` or `relaxed`, the build stops
part-way:

```
sandbox initialization failed: data object length 66230 exceeds maximum (65535)
```

Nix lists every store path a derivation may read in its macOS sandbox
profile, and the profile has a size limit. A unit reads its transitive
dependencies and their sources, which for the larger crates of uv is close
to a thousand paths. Until rostnix needs fewer, build with the sandbox off,
which is Nix's default on macOS and needs a trusted user:

```bash
nix build -j 12 --option sandbox false \
  --option allow-unsafe-native-code-during-evaluation true
```

## What the flake does

```nix
inputs.uv-src = {
  url = "github:astral-sh/uv/0.12.5";
  flake = false;
};

rustEnv = rostnix.lib.mkRustEnv { inherit pkgs; };

packages.uv = rustEnv.buildRustApplication {
  pname = "uv";
  version = (lib.importTOML "${uv-src}/crates/uv/Cargo.toml").package.version;
  src = uv-src;
  packages = [ "uv" ];
  meta.mainProgram = "uv";
};
```

There is no `cargoHash` and no generated `Cargo.nix`. While Nix evaluates,
rostnix asks cargo for the build graph of this source and takes the crate
hashes from uv's `Cargo.lock`. `packages = [ "uv" ]` selects what
`cargo build -p uv` does, leaving out the workspace's development tools.

Nothing in `crateOverrides` is needed. The build scripts that compile C,
those of `aws-lc-sys`, `tikv-jemalloc-sys`, `zstd-sys` and `blake3`, get the
C compiler of the `pkgs` passed to `mkRustEnv`.

## One derivation per unit

The result exposes every unit:

```bash
opt=(--option allow-unsafe-native-code-during-evaluation true)

# The units in the build.
nix eval "${opt[@]}" --json .#uv.units --apply builtins.attrNames

# Build one unit alone.
nix build "${opt[@]}" --no-link --print-out-paths \
  '.#uv.units."uv-cache-key-0.0.72-lib-5dfc1d59"'
```

## Building another uv

Change the tag in `uv-src.url` and run `nix flake update uv-src`. Nothing
else needs regenerating. Two things limit the choice:

- rostnix follows the toolchain of nixpkgs 26.05, Rust 1.95. uv 0.12.5 is
  the newest release that it builds; 0.12.6 raises `rust-version` to 1.96.
- rostnix fetches crates from crates.io only. The `Cargo.lock` of recent
  releases names nothing else; older ones, 0.8.0 for example, have git
  dependencies.

## Notes

- `nix flake check` and `nix flake show` evaluate `packages`, so they need
  the option too.
- The flake defines the package for Linux and macOS on both architectures,
  but it has only been built on aarch64-darwin.
- The installed `uv` keeps the source of `aws-lc-sys`, 66 MB, in its
  closure: the C files compiled by that crate's build script leave their
  store paths in the binary.
