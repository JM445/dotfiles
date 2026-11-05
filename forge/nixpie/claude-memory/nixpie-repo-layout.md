---
name: nixpie-repo-layout
description: How the nixpie repo (EPITA lab NixOS images) is structured and how images/packages are wired
metadata:
  type: project
---

Nix PIE = NixOS configs for EPITA computer labs (~1000 PXE-booted machines). Flake on nixos-26.05, with `pkgsUnstable`/`pkgsMaster` also available.

- `images/<name>.nix`: one NixOS config per boot image (e.g. `nixos-maths.nix`; `exam-maths.nix` imports it, so maths packages also land in the exam image).
- `modules/packages/`: `cri.packages.*` options. `cri.packages.pkgs.<bundle>.enable` toggles bundles in `modules/packages/pkgs/`.
- `pkgs/top-level/all-packages.nix`: registry of our own derivations, turned into one overlay each by `pkgs/overlays.nix`. Python packages are under `pkgs/development/python-modules/<name>/` and registered with `callPackage = final: prev: final.python3Packages.callPackage;`, so they show up as **top-level** `pkgs.<name>`, NOT `python3Packages.<name>`.
- `pkgs/overrides.nix`: pulls specific packages from pkgsUnstable.
- Test a VM: `nix build -L .#nixosConfigurations.<image>.config.system.build.vm`.
- Check whether nixpkgs has a package: `nix eval --raw .#nixosConfigurations.nixos-maths.pkgs.python3Packages.<x>.name`.

See [[nixpie-python-jupyter]], [[nixpie-conventions]].
