---
name: nixpie-python-jupyter
description: How Python packages reach Jupyter in nixpie images (single python3.withPackages env built from cri.packages.pythonPackages)
metadata:
  type: project
---

`cri.packages.pythonPackages` is an attrset of `p: [ ... ]` functions (`modules/packages/default.nix`). All of them are merged into ONE `python3.withPackages` env (ignoreCollisions = true) in `environment.systemPackages`. jupyter/jupyterlab are in that same env, so any package added to any list is importable from the notebook kernel; no separate kernel setup is needed.

nixos-maths uses `cri.packages.pythonPackages.nixosMathsCustom` in `images/nixos-maths.nix`. Packages from nixpkgs go in as `foo` (via `with p;`). Our own packages go in as `pkgs.foo` (e.g. `pkgs.jupyter-dash`, `pkgs.nbtranslate`), see [[nixpie-repo-layout]].

Python is 3.13 on 26.05. A broken package is commented out with a reason and date, e.g. `#osmnx # FIXME: build failure as of 2026-08-26`.
