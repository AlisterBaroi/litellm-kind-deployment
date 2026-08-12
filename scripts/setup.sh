#!/usr/bin/env bash
# One-shot LiteLLM-on-kind install. Safe to re-run: reuses an existing
# cluster/release and keeps the existing master key on upgrades.
#
# Works from a repo checkout or straight from curl:
#   ./scripts/setup.sh
#   CLUSTER_NAME=my-cluster ./scripts/setup.sh
#   curl -fsSL https://raw.githubusercontent.com/AlisterBaroi/litellm-kind-deployment/main/scripts/setup.sh | bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-litellm}"
NAMESPACE="${NAMESPACE:-litellm}"
RELEASE="litellm"
CHART="${LITELLM_CHART:-oci://ghcr.io/berriai/litellm-helm}"
# Pinned on purpose (unlike the LiteLLM version, which floats to the newest
# release): the init-image workaround below targets a tag hardcoded in this
# chart version's templates. Re-test the workarounds before bumping.
CHART_VERSION="${LITELLM_CHART_VERSION:-0.1.100}"
# Hardcoded as the db-ready init container in the chart's Deployment template;
# only exists under bitnamilegacy/ on Docker Hub these days (see README step 2).
INIT_IMAGE_TAG="16.1.0-debian-11-r20"

CTX="kind-${CLUSTER_NAME}"

for cmd in docker kind kubectl helm openssl curl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: '$cmd' not found in PATH" >&2; exit 1; }
done

# values.yaml ships next to this script in the repo. When the script runs
# without a checkout (curl ... | bash), fetch the file instead.
VALUES_URL="${LITELLM_VALUES_URL:-https://raw.githubusercontent.com/AlisterBaroi/litellm-kind-deployment/main/values.yaml}"
SCRIPT_PATH="${BASH_SOURCE[0]:-}"
if [ -n "$SCRIPT_PATH" ] && [ -f "$(dirname "$SCRIPT_PATH")/../values.yaml" ]; then
  VALUES_FILE="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)/values.yaml"
else
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  VALUES_FILE="$TMP_DIR/values.yaml"
  echo ">> No local checkout found - fetching values.yaml"
  curl -fsSL "$VALUES_URL" -o "$VALUES_FILE"
fi

# Resolve the newest stable LiteLLM release unless the caller picked one.
# GitHub marks release candidates as pre-releases, so releases/latest only
# ever returns a stable version.
VERSION_RESOLVED=true
if [ -z "${LITELLM_VERSION:-}" ]; then
  LITELLM_VERSION="$(curl -sf https://api.github.com/repos/BerriAI/litellm/releases/latest \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' || true)"
fi
if [ -z "${LITELLM_VERSION:-}" ]; then
  echo "WARN: could not resolve the latest LiteLLM release from the GitHub API" >&2
  VERSION_RESOLVED=false
fi
echo ">> LiteLLM version: ${LITELLM_VERSION:-latest (Docker tag fallback)}"

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo ">> Using existing kind cluster '$CLUSTER_NAME'"
else
  echo ">> Creating kind cluster '$CLUSTER_NAME'"
  kind create cluster --name "$CLUSTER_NAME"
fi

echo ">> Pre-loading Postgres init image onto cluster node(s)"
for node in $(kind get nodes --name "$CLUSTER_NAME"); do
  docker exec "$node" crictl pull "docker.io/bitnamilegacy/postgresql:${INIT_IMAGE_TAG}"
  docker exec "$node" ctr --namespace=k8s.io images tag --force \
    "docker.io/bitnamilegacy/postgresql:${INIT_IMAGE_TAG}" \
    "docker.io/bitnami/postgresql:${INIT_IMAGE_TAG}"
done

# On upgrades, only move the image tag when we actually resolved a release;
# otherwise --reuse-values keeps whatever version is already running.
IMAGE_TAG_ARGS=()
if [ "$VERSION_RESOLVED" = true ]; then
  IMAGE_TAG_ARGS=(--set image.tag="$LITELLM_VERSION")
fi

if helm status "$RELEASE" -n "$NAMESPACE" --kube-context "$CTX" >/dev/null 2>&1; then
  echo ">> Release exists - upgrading (master key and DB password are kept)"
  helm upgrade "$RELEASE" "$CHART" --version "$CHART_VERSION" \
    --kube-context "$CTX" -n "$NAMESPACE" \
    --reuse-values -f "$VALUES_FILE" \
    ${IMAGE_TAG_ARGS[@]+"${IMAGE_TAG_ARGS[@]}"}
else
  echo ">> Installing chart ${CHART_VERSION}"
  MASTER_KEY="sk-$(openssl rand -hex 16)"
  DB_PASSWORD="$(openssl rand -hex 16)"
  helm install "$RELEASE" "$CHART" --version "$CHART_VERSION" \
    --kube-context "$CTX" -n "$NAMESPACE" --create-namespace \
    -f "$VALUES_FILE" \
    ${IMAGE_TAG_ARGS[@]+"${IMAGE_TAG_ARGS[@]}"} \
    --set masterkey="$MASTER_KEY" \
    --set postgresql.auth.password="$DB_PASSWORD" \
    --set postgresql.auth."postgres-password"="$DB_PASSWORD"
fi

echo ">> Waiting for pods (first run pulls ~1 GB of images - can take a few minutes)"
kubectl --context "$CTX" wait --for=condition=ready pod \
  -l app.kubernetes.io/name=litellm -n "$NAMESPACE" --timeout=600s
kubectl --context "$CTX" get pods -n "$NAMESPACE"

echo ""
echo ">> Fetching the master key, by running:"
echo "   kubectl --context $CTX get secret litellm-masterkey -n $NAMESPACE -o jsonpath='{.data.masterkey}' | base64 -d"
MASTER_KEY="$(kubectl --context "$CTX" get secret litellm-masterkey -n "$NAMESPACE" -o jsonpath='{.data.masterkey}' | base64 -d)"

cat <<EOF

LiteLLM is up.

  Master key: $MASTER_KEY

Start a port-forward and leave it running:

  kubectl --context $CTX port-forward -n $NAMESPACE svc/litellm 4000:4000

Then open the web UI at http://localhost:4000/ui and log in with:

  username: admin
  password: the master key above

Or call the API from another terminal:

  curl -s http://localhost:4000/v1/chat/completions \\
    -H "Authorization: Bearer $MASTER_KEY" \\
    -H "Content-Type: application/json" \\
    -d '{"model": "mock-gpt", "messages": [{"role": "user", "content": "Are you alive?"}]}'
EOF
