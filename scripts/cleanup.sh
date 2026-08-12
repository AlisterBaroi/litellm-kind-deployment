#!/usr/bin/env bash
# Remove the LiteLLM release and namespace (Postgres PVC goes with it).
#
#   ./scripts/cleanup.sh                     # keep the kind cluster
#   CLUSTER_NAME=my-cluster ./scripts/cleanup.sh
#   DELETE_CLUSTER=true ./scripts/cleanup.sh # delete the whole kind cluster
#
# Without CLUSTER_NAME, the script looks across your kind clusters for the
# one that actually has the LiteLLM release installed. Cluster deletion
# never auto-detects: it only targets CLUSTER_NAME (default "litellm"),
# so a guess can't take down an unrelated cluster.
set -euo pipefail

NAMESPACE="${NAMESPACE:-litellm}"
RELEASE="litellm"

if [ "${DELETE_CLUSTER:-false}" = "true" ]; then
  CLUSTER_NAME="${CLUSTER_NAME:-litellm}"
  echo ">> Deleting kind cluster '$CLUSTER_NAME'"
  kind delete cluster --name "$CLUSTER_NAME"
  exit 0
fi

if [ -z "${CLUSTER_NAME:-}" ]; then
  echo ">> CLUSTER_NAME not set - looking for a kind cluster with a '$RELEASE' release"
  MATCHES=""
  for c in $(kind get clusters 2>/dev/null); do
    if helm status "$RELEASE" -n "$NAMESPACE" --kube-context "kind-$c" >/dev/null 2>&1; then
      MATCHES="$MATCHES $c"
    fi
  done
  MATCHES="${MATCHES# }"
  if [ -z "$MATCHES" ]; then
    echo "ERROR: no kind cluster has a '$RELEASE' release in namespace '$NAMESPACE'." >&2
    echo "Existing kind clusters: $(kind get clusters 2>/dev/null | tr '\n' ' ')" >&2
    echo "If you know the target, re-run with CLUSTER_NAME=<name>." >&2
    exit 1
  fi
  case "$MATCHES" in
    *" "*)
      echo "ERROR: several kind clusters have a '$RELEASE' release: $MATCHES" >&2
      echo "Pick one by re-running with CLUSTER_NAME=<name>." >&2
      exit 1
      ;;
  esac
  CLUSTER_NAME="$MATCHES"
  echo ">> Found it on kind cluster '$CLUSTER_NAME'"
fi

CTX="kind-${CLUSTER_NAME}"

echo ">> Uninstalling release '$RELEASE'"
helm uninstall "$RELEASE" -n "$NAMESPACE" --kube-context "$CTX" || true

echo ">> Deleting namespace '$NAMESPACE' (includes the Postgres PVC)"
kubectl --context "$CTX" delete namespace "$NAMESPACE" --ignore-not-found

echo ">> Done. The kind cluster '$CLUSTER_NAME' itself was kept."