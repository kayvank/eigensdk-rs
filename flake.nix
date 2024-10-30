{
  description = "minotaur-connectors project";
  inputs = {
    nixpkgs.url = "github:NixOs/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    flake-utils.url = "github:numtide/flake-utils";
    foundry.url = "github:shazow/foundry.nix/monthly"; # Use monthly branch for permanent releases
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
  };
  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
      flake-utils,
      foundry,
      pre-commit-hooks,
      ...
    }@inputs:

    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            rust-overlay.overlays.default
            foundry.overlay
          ];
        };
        hook = pre-commit-hooks.lib.${system};
        tools = import "${pre-commit-hooks}/nix/call-tools.nix" pkgs;
        toolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
        cargoTomlContents = builtins.readFile ./Cargo.toml;
        version = (builtins.fromTOML cargoTomlContents).package.version;

        ethereumEs = pkgs.rustPlatform.buildRustPackage {
          inherit version;
          name = "ethereumEs";
          buildInputs = with pkgs; [ openssl ];
          nativeBuildInputs = with pkgs; [
            pkg-config
            openssl.dev
          ];

          src = pkgs.lib.cleanSourceWith { src = self; };

          cargoLock.lockFile = ./Cargo.lock;

        };
      in
      rec {
        checks.pre-commit-check = hook.run {
          src = self;
          tools = tools;
          # enforce pre-commit-hook
          hooks = {
            eslint.enable = true;
            rustfmt.enable = true;
            nixfmt-rfc-style.enable = true;
          };
        };

        overlays.default = final: prev: { ethereumEs = ethereumEs; };

        gitRev = if (builtins.hasAttr "rev" self) then self.rev else "dirty";

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Ethereum stuff (dev only)
            foundry-bin
            solc
            openssl
            pkg-config
            # Rust stuff (dev only)
            eza
            rust-analyzer-unwrapped
            watchexec
            # Rust stuff (CI + dev)
            toolchain
            cargo-deny
            # Spelling and linting
            codespell
            eclint
          ];
          packages = with pkgs; [
            tools.nixpkgs-fmt
            tools.eslint
            tools.rustfmt
            tools.nixfmt-rfc-style
          ];

          shellHook = ''
            ${checks.pre-commit-check.shellHook}
            export RUST_SRC_PATH="${toolchain}/lib/rustlib/src/rust/library"
            export CARGO_HOME="$(pwd)/.cargo"
            export PATH="$CARGO_HOME/bin:$PATH"
            export RUST_BACKTRACE=1
            export RPC_URL='127.0.0.1:8545'
          '';
        };
      }
    );
}
