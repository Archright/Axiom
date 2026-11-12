# =============================================================================
# Axiom Nix Flake — L0 of the 5-Layer Defense Stack
# =============================================================================
#
# Reproducible build environment pinning exact toolchain versions.
#
# PREREQUISITES (manual — do NOT run these as root/sudo from agent):
#   1. Install Nix:  curl -L https://nixos.org/nix/install | sh
#   2. Enable flakes:  mkdir -p ~/.config/nix && echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
#   3. (Optional) Install direnv:  cargo install direnv  (or system package)
#   4. Activate:  direnv allow  (or  nix develop  for manual shell)
#
# PINNED VERSIONS:
#   - Nim:      2.2.10  (via nim2 package; exact pin requires nixpkgs commit pinning — see below)
#   - Z3:       4.13.3  (stable on nixos-24.05)
#   - Lean 4:   4.29.0  (via elan, which manages Lean versions)
#   - Lake:     5.0.0   (bundled with Lean 4.29.0 via elan)
#
# NOTES:
#   - nim2 in nixos-24.05 tracks Nim 2.x line but may lag behind 2.2.10.
#     To pin an exact Nim version, override with a specific nixpkgs commit:
#       nixpkgs.url = "github:NixOS/nixpkgs/<commit-sha>";
#     Find the commit via:  https://search.nixos.org/packages (filter by nim version).
#   - Z3 4.13.3 is available on nixos-24.05. If missing, pin nixpkgs-unstable.
#   - elan is the recommended Lean toolchain manager; it downloads the correct
#     Lean + Lake versions on first use based on lean-toolchain.
#   - Lean 4.29.0 + Lake 5.0.0 are declared in proofs/lean-toolchain.
#
# USAGE:
#   nix develop          — enter the dev shell
#   nix build            — (future) reproducible build
#   direnv allow         — auto-activate on cd (requires direnv)
# =============================================================================

{
  description = "Axiom — Integrity proof engine for AI-generated software logic";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # --- Version overrides (uncomment and adjust as needed) ---
        # To pin an exact nixpkgs commit for a specific Nim/Z3 version,
        # replace nixpkgs.url above with a pinned commit hash, e.g.:
        #   nixpkgs.url = "github:NixOS/nixpkgs/<commit-sha>";
        #
        # Or override the package set directly:
        # nimVersion = pkgs.nim.overrideAttrs (old: {
        #   version = "2.2.10";
        #   src = pkgs.fetchurl {
        #     url = "https://nim-lang.org/download/nim-2.2.10.tar.xz";
        #     sha256 = "FIXME";  # compute with: nix-prefetch-url --unpack <url>
        #   };
        # });

      in {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            # === Core toolchain ===
            pkgs.nim2          # Nim 2.x line (verify version in shellHook)
            pkgs.z3            # Z3 SMT solver
            pkgs.elan          # Lean toolchain manager (installs Lean 4.29.0 + Lake 5.0.0)

            # === Build tools ===
            pkgs.git
            pkgs.gnumake
            pkgs.pkg-config

            # === Dependencies ===
            pkgs.openssl
          ];

          # Environment variables
          shellHook = ''
            echo "============================================="
            echo " Axiom dev environment (Nix Flake — L0)"
            echo "============================================="

            # Verify Nim
            if command -v nim &>/dev/null; then
              NIM_VER=$(nim --version 2>/dev/null | head -1)
              echo "  Nim:     $NIM_VER"
            else
              echo "  Nim:     NOT FOUND"
            fi

            # Verify Z3
            if command -v z3 &>/dev/null; then
              Z3_VER=$(z3 --version 2>/dev/null | head -1)
              echo "  Z3:      $Z3_VER"
            else
              echo "  Z3:      NOT FOUND"
            fi

            # Verify Lean (via elan)
            if command -v lean &>/dev/null; then
              LEAN_VER=$(lean --version 2>/dev/null | head -1)
              echo "  Lean:    $LEAN_VER"
            else
              echo "  Lean:    (via elan — run 'elan install' to fetch toolchain)"
            fi

            # Ensure PATH includes project binaries
            export PATH="$PWD/bin:$PATH"

            echo "============================================="
          '';
        };
      }
    );
}
