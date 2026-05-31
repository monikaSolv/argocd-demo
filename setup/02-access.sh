#!/usr/bin/env bash
# =============================================================================
# ARGOCD ACCESS — 02-access.sh
# =============================================================================
# Gets the initial admin password and opens port-forward to the ArgoCD UI.
#
# ArgoCD UI is a pod inside the cluster — not exposed externally by default.
# kubectl port-forward creates a tunnel: localhost:8080 → argocd-server pod:443.
# The tunnel exists only while this script runs (Ctrl+C to stop).
#
# In production: you'd set up an Ingress or LoadBalancer.
# For learning on kind: port-forward is enough.
# =============================================================================

set -euo pipefail

# =============================================================================
# Get the initial admin password
# =============================================================================
# ArgoCD generates a random password on first install and stores it in a Secret.
# Secret name: argocd-initial-admin-secret
# Key: password (base64 encoded — kubectl strips the encoding with -o jsonpath)
#
# Username is always: admin
# After first login, change this password via the UI or argocd CLI.

echo ">>> ArgoCD initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo ""  # newline after password (jsonpath output has no trailing newline)

# =============================================================================
# Log in via the argocd CLI
# =============================================================================
# argocd CLI is used for: creating apps, syncing, checking status, diffs.
# --insecure: ArgoCD uses a self-signed TLS cert in this demo — skip verification.
# --grpc-web: required when accessing behind a proxy or port-forward.

echo ">>> Logging in via argocd CLI..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

argocd login localhost:8080 \
  --username admin \
  --password "${ARGOCD_PASSWORD}" \
  --insecure \
  --grpc-web &
# Running in background so port-forward can start next.
# In practice: log in first, then start port-forward in a separate terminal.

sleep 2

# =============================================================================
# Port-forward to ArgoCD UI
# =============================================================================
echo ""
echo ">>> Opening port-forward on localhost:8080..."
echo ">>> Open browser: https://localhost:8080"
echo ">>> Username: admin"
echo ">>> Password shown above"
echo ">>> Press Ctrl+C to stop."
echo ""

kubectl port-forward svc/argocd-server -n argocd 8080:443
# This command blocks — terminal is now the tunnel.
# Open a NEW terminal for all subsequent commands.
