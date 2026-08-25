{
  description = "Build Shell with any dependency of the project";

  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem(system:
        let
          pkgs = import nixpkgs { inherit system; };
          lsWithColor = pkgs.writeShellScriptBin "ls" ''
            exec ${pkgs.coreutils}/bin/ls --color=auto "$@"
          '';
        in
        {
          devShell = pkgs.mkShell {
            packages = [
            # Java Development
              pkgs.jdk21
              pkgs.maven                    # Apache Maven 3.x

              # Container Infrastructure
              pkgs.docker                   # Docker for running services
              pkgs.docker-compose           # Docker Compose for orchestration

              # Database Tools
              pkgs.postgresql_17            # PostgreSQL client tools (psql)

              # Development Utilities
              pkgs.git                      # Version control
              pkgs.curl                     # HTTP client for API testing
              pkgs.jq                       # JSON processor (useful for API responses)

              # Optional
              pkgs.which                    # Utility to locate programs
              pkgs.gnumake                  # Build automation (if needed)
            ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [ lsWithColor ];

            shellHook = ''
              nix build nixpkgs#openjdk -o ~/.local/lib/openjdk
              echo "🚀 Forge::dev Development Environment"
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo "Java:    $(java -version 2>&1 | head -n 1)"
              echo "Maven:   $(mvn -version 2>&1 | head -n 1)"
              echo "Docker:  $(docker --version)"
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo ""
              echo "📋 Quick Start Commands:"
              echo "  • Start infrastructure:  docker-compose up -d postgres kafka"
              echo "  • Build srvc-stats:      ./mvnw -pl apps/srvc-stats -am clean install"
              echo "  • Run srvc-stats dev:    ./mvnw -pl apps/srvc-stats quarkus:dev"
              echo "  • Connect to DB:         psql -h localhost -U postgres -d srvc_stats"
              echo ""

              # Set JAVA_HOME for tools that need it
              export JAVA_HOME="${pkgs.jdk21}"

              # Force Docker api version (must reach the Surefire-forked JVM too,
              # so this needs JDK_JAVA_OPTIONS rather than MAVEN_OPTS)
              export JDK_JAVA_OPTIONS="-Dapi.version=1.41"

              # Route this repo's Claude Code auto-memory into this flake's own
              # (git-synced) directory instead of the per-machine default, so it
              # follows the dotfiles repo across hosts. `self` resolves to wherever
              # this flake.nix actually lives on the current host, so no path is
              # hardcoded here.
              CLAUDE_MEMORY_DIR="${self}/claude-memory"
              mkdir -p "$CLAUDE_MEMORY_DIR" .claude
              cat > .claude/settings.local.json <<SETTINGS
{
  "autoMemoryDirectory": "$CLAUDE_MEMORY_DIR"
}
SETTINGS


              # # Ensure Docker is accessible (if using Docker daemon socket)
              # export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock"
              '';
          };
        }
      );
}
