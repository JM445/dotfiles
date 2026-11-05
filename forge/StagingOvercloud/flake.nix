{
  description = "Personal extra tooling for the Forge StagingOvercloud repository";

  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem(system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          # Stacked on top of the repository's own devShell (see link.sh / .envrc):
          # the repo flake already provides opentofu, vault, openstackclient, the
          # pre-commit hooks and sources config.sh, so only add what it lacks here.
          devShells.default = pkgs.mkShell {
            packages = [
              # Kubernetes
              pkgs.kubectl
              pkgs.kustomize                # k8s/ is kustomize based
              pkgs.kubernetes-helm
              pkgs.k9s
              pkgs.kubectx                  # kubectx / kubens
              pkgs.stern                    # Multi-pod log tailing
              pkgs.argocd                   # ArgoCD CLI (k8s/argocd)

              # Ansible (playbooks/, roles/)
              pkgs.ansible

              # Utilities
              pkgs.jq
              pkgs.yq-go
              pkgs.glab
            ];

            shellHook = ''
              echo "🚀 Forge::StagingOvercloud Environment"
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo "Tofu:    $(tofu version 2>/dev/null | head -n 1)"
              echo "kubectl: $(kubectl version --client 2>/dev/null | head -n 1)"
              echo "Vault:   $VAULT_ADDR"
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            '';
          };
        }
      );
}
