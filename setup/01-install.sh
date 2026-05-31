#!/usr/bin/env bash
# =============================================================================
# ARGOCD SETUP — 01-install.sh
# =============================================================================
# WHAT IS ARGOCD?
#   ArgoCD is a GitOps continuous delivery tool for Kubernetes.
#   GitOps = Git is the single source of truth for your cluster state.
#
#   The core idea:
#     1. You write Kubernetes manifests (YAML) and push them to Git.
#     2. ArgoCD watches that Git repo continuously.
#     3. When Git changes, ArgoCD applies the diff to the cluster automatically.
#     4. If someone manually changes the cluster (kubectl edit), ArgoCD reverts it.
#
#   Result: Git = cluster. Always. No drift. No "who ran kubectl" mysteries.
#   Same principle as Terraform for infra — declare desired state, tool converges.
#
# HOW ARGOCD WORKS (the loop):
#
#   Git repo (desired state)
#        ↓  ArgoCD polls every 3 min (or webhook triggers immediately)
#   ArgoCD compares desired vs live state
#        ↓  if diff exists
#   ArgoCD applies the diff (kubectl apply under the hood)
#        ↓
#   Live cluster matches Git
#
# KEY OBJECTS (you will see these throughout the files):
#
#   Application   The ArgoCD CRD. One Application = one service to manage.
#                 Says: "watch THIS repo path, deploy to THIS namespace."
#
#   AppProject    Groups Applications, controls RBAC and allowed repos.
#                 'default' project allows everything — fine for learning.
#
#   Sync          The act of applying Git state to the cluster.
#                 Synced    = Git matches cluster.
#                 OutOfSync = Git differs from cluster (change pending).
#
#   Health        Did the deployed resources actually start correctly?
#                 Healthy   = pods running, endpoints responding.
#                 Degraded  = CrashLoopBackOff, pending, etc.
#                 Progressing = still starting up.
#
# PRE-REQUISITES (already on your M2 Mac):
#   brew install kind kubectl argocd
#
# HOW TO RUN THIS SCRIPT:
#   bash 01-install.sh
#   OR run commands one by one — recommended on first learning pass.
# =============================================================================

set -euo pipefail
# set -e  exit immediately if any command fails
# set -u  treat unset variables as errors
# set -o pipefail  catch failures inside pipes (cmd1 | cmd2 — catches cmd1 fail)

# =============================================================================
# STEP 1 — Create a kind cluster
# =============================================================================
# kind (Kubernetes-in-Docker) runs a full k8s cluster inside Docker containers.
# Each "node" is a Docker container. No VMs, no cloud needed.
# --name gives it a unique name so you can have multiple clusters locally.

echo ">>> Creating kind cluster..."
kind create cluster --name argocd-demo --config - <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    # extraPortMappings: map host ports to container ports.
    # ArgoCD UI runs on port 443 inside the cluster.
    # We map it to host port 8080 so the browser can reach it.
    extraPortMappings:
      - containerPort: 30080
        hostPort: 8080
        protocol: TCP
EOF

# Verify cluster is up
kubectl cluster-info --context kind-argocd-demo
echo ">>> Cluster ready."

# =============================================================================
# STEP 2 — Install ArgoCD into the cluster
# =============================================================================
# ArgoCD runs as a set of pods inside the 'argocd' namespace.
# Components installed:
#   argocd-server         — API server + Web UI
#   argocd-repo-server    — clones Git repos, renders templates
#   argocd-application-controller — the reconciliation loop (watches cluster)
#   argocd-dex-server     — SSO/auth (not used in this demo)
#   argocd-redis          — internal cache for ArgoCD itself (not your Redis app)

echo ">>> Creating argocd namespace..."
kubectl create namespace argocd

echo ">>> Installing ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# =============================================================================
# STEP 3 — Wait for ArgoCD pods to be ready
# =============================================================================
# ArgoCD takes 60-90 seconds to pull images and start.
# --for=condition=available waits until the Deployment reports all replicas ready.
# --timeout=300s gives it 5 minutes before failing.

echo ">>> Waiting for ArgoCD to be ready (takes ~90s)..."
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=300s

echo ""
echo ">>> ArgoCD installed. Run 02-access.sh to open the UI."
