#!/usr/bin/env bash
# Remove the LiteLLM release and namespace (Postgres PVC goes with it).
#
#   ./scripts/cleanup.sh                     # keep the kind cluster
#   DELETE_CLUSTER=true ./scripts/cleanup.sh # delete the whole kind cluster
#   CLUSTER_NAME=my-cluster ./scripts/cleanup.sh
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-litellm}"
NAMESPACE="${NAMESPACE:-litellm}"
RELEASE="litellm"
CTX="kind-${CLUSTER_NAME}"

if [ "${DELETE_CLUSTER:-false}" = "true" ]; then
  echo ">> Deleting kind cluster '$CLUSTER_NAME'"
  kind delete cluster --name "$CLUSTER_NAME"
  exit 0
fi

echo ">> Uninstalling release '$RELEASE'"
helm uninstall "$RELEASE" -n "$NAMESPACE" --kube-context "$CTX" || true

echo ">> Deleting namespace '$NAMESPACE' (includes the Postgres PVC)"
kubectl --context "$CTX" delete namespace "$NAMESPACE" --ignore-not-found

echo ">> Done. The kind cluster '$CLUSTER_NAME' itself was kept."
