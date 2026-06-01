{
  description = "Build Shell with any dependency of the project";

  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = import nixpkgs { inherit system; };
      in
      {
        devShell = pkgs.mkShell {
          packages = [
            # JavaScript / Node.js
            pkgs.nodejs_20               # Node.js 20 LTS
            pkgs.nodePackages.pnpm       # pnpm v9 package manager

            # Build tooling
            pkgs.typescript              # tsc for type checking

            # Development utilities
            pkgs.git
            pkgs.curl
            pkgs.jq
          ];

          shellHook = ''
            echo "Forge::frontends Development Environment"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Node:  $(node --version)"
            echo "pnpm:  $(pnpm --version)"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "Quick Start:"
            echo "  Install deps:   pnpm install"
            echo "  Dev (operator): pnpm nx serve operator"
            echo "  Dev (discord):  pnpm nx serve discord"
            echo "  Build all:      pnpm nx run-many -t build"
            echo "  Lint:           pnpm nx run-many -t lint"
            echo ""
          '';
        };
      }
    );
}
