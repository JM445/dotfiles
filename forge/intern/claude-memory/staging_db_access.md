---
name: staging-db-access
description: How to kubectl port-forward to the staging database pod for this project
metadata: 
  node_type: memory
  type: reference
  originSessionId: 75e51dbb-3583-44a4-9eed-c302befcdb64
  modified: 2026-08-21T09:40:45.126Z
---

Cluster access uses `kube-switcher` (the `switch` shell command, hooked into the user's zshrc) to select the kubeconfig context — it is not set by default in a fresh/non-interactive shell (e.g. this agent's Bash tool), so `kubectl config current-context` showing empty there is expected, not a bug to fix.

Pod discovery happens via the Rancher UI, but pod names alone are not enough — `kubectl port-forward pods/<name>` without `-n <namespace>` looks in the context's default namespace and 404s even when the name is correct. The staging DB pod (StatefulSet-style name like `forge-staging-main-cluster-0`) lives in a non-default namespace.

Working flow:
1. In a real interactive terminal: `switch` → pick the staging cluster.
2. `kubectl get pods --all-namespaces | grep forge-staging-main-cluster` to get the exact name + namespace together.
3. `kubectl port-forward -n <namespace> pod/forge-staging-main-cluster-0 8888:5000 --address 0.0.0.0`

**How to apply:** When the user is stuck on kubectl "pod not found" errors for this project, check context selection (`switch`) and namespace flag before doubting the pod name itself.
