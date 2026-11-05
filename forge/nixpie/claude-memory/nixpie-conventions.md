---
name: nixpie-conventions
description: Commit message and branch conventions in nixpie
metadata:
  type: project
---

Commit subjects are prefixed with a path-like scope, in lowercase: `images: nixos-maths: add cvxopt`, `pkgs: sdl: ...`, `modules: pkgs: net: ...`, `profiles: core: ...`, `treewide: ...`, `flake: update inputs`. Branch names look like `<issue#>-<slug>` (GitLab, gitlab.cri.epita.fr).

Custom python derivations follow `pkgs/development/python-modules/missingno/default.nix`: `buildPythonPackage rec`, `pyproject = true`, `build-system = [ setuptools ]`, `propagatedBuildInputs`, `doCheck = false`, and a meta with homepage/description/license. Related: [[nixpie-repo-layout]].
