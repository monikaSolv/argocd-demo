#!/usr/bin/env bash
# =============================================================================
# DEPLOY + DEMO — 03-deploy-and-demo.sh
# =============================================================================
# Run this AFTER:
#   1. 01-install.sh completed (ArgoCD is running)
#   2. 02-access.sh port-forward is running in another terminal
#   3. You pushed this repo to GitHub and updated repoURL in redis.yaml
#
# WHAT THIS SCRIPT WALKS THROUGH:
#   A. Push manifests to GitHub (you do this manually)
#   B. Apply the ArgoCD Application — ArgoCD takes over from here
#   C. Watch sync happen
#   D. Demo: GitOps update (change replicas in Git → ArgoCD syncs)
#   E. Demo: self-healing (manual kubectl change → ArgoCD reverts)
#   F. Demo: rollback (revert Git commit → ArgoCD rolls back)
# =============================================================================

set -euo pipefail

# =============================================================================
# A — Push to GitHub (do this manually before running this script)
# =============================================================================
# These are the commands to run once — initialize git and push to GitHub.
# Replace <YOUR_GITHUB_USERNAME> and <YOUR_REPO_NAME> with your values.
#
# cd /Users/monika.y/Desktop/Projects/repo
# git init
# git add custom-scripts/argocd/
# git commit -m "Add ArgoCD Redis example"
# git remote add origin https://github.com/<YOUR_GITHUB_USERNAME>/<YOUR_REPO_NAME>.git
# git push -u origin main
#
# Also update repoURL in argocd-applications/redis.yaml before pushing.

echo ">>> Assuming repo is already pushed to GitHub."
echo ">>> Applying the ArgoCD Application..."

# =============================================================================
# B — Apply the ArgoCD Application CRD
# =============================================================================
# This is the ONLY thing you manually apply. ArgoCD manages everything else.
# After this kubectl apply, ArgoCD:
#   1. Reads the Application spec
#   2. Clones the Git repo
#   3. Renders all YAML in apps/redis/
#   4. Applies them to the cluster
#   5. Reports sync status and health

kubectl apply -f ../argocd-applications/redis.yaml

echo ">>> Application created. ArgoCD is now syncing..."

# =============================================================================
# C — Watch the sync
# =============================================================================

echo ""
echo ">>> Watching ArgoCD application status (Ctrl+C to stop):"
watch -n 3 "argocd app get redis --grpc-web"
# argocd app get: shows sync status, health, and resource tree.
# watch -n 3: refreshes every 3 seconds.
# Expected progression:
#   Sync Status: OutOfSync → Synced
#   Health:      Missing   → Progressing → Healthy

# Or watch pods directly:
# kubectl get pods -n redis -w

# =============================================================================
# D — DEMO: GitOps update — change replicas in Git, push, watch ArgoCD sync
# =============================================================================
# Manual steps (run in your terminal, not in this script):
#
# 1. Edit apps/redis/deployment.yaml: change replicas: 1 to replicas: 2
# 2. Git commit and push:
#      git add apps/redis/deployment.yaml
#      git commit -m "Scale Redis to 2 replicas"
#      git push
# 3. Wait ~3 minutes for ArgoCD to poll (or force sync):
#      argocd app sync redis --grpc-web
# 4. Watch:
#      kubectl get pods -n redis
# Expected: two redis-* pods running
#
# This is GitOps: Git change → cluster change. No kubectl scale. Git is truth.

echo ""
echo ">>> DEMO D: Edit deployment.yaml replicas: 1 → 2, push to Git."
echo ">>> Then run: argocd app sync redis --grpc-web"
echo ">>> Watch:    kubectl get pods -n redis -w"
read -p "Press Enter when ready for self-healing demo..."

# =============================================================================
# E — DEMO: Self-healing — manual kubectl change → ArgoCD reverts it
# =============================================================================
echo ""
echo ">>> DEMO E: Self-healing"
echo ">>> Scaling Redis to 0 manually (bypassing Git)..."

kubectl scale deployment redis --replicas=0 -n redis

echo ">>> Redis scaled to 0. Watch ArgoCD revert it within ~3 minutes..."
echo ">>> Or force immediate sync: argocd app sync redis --grpc-web"
echo ""

kubectl get pods -n redis -w &
WATCH_PID=$!

echo ">>> Forcing sync to see immediate revert..."
sleep 5
argocd app sync redis --grpc-web

wait $WATCH_PID 2>/dev/null || true
# Expected output:
#   redis-<hash>   1/1   Running  → (you scaled to 0) → Terminating
#   redis-<hash>   0/1   Pending  → (ArgoCD reverts) → Running

# =============================================================================
# F — DEMO: Rollback — revert a Git commit → ArgoCD rolls back
# =============================================================================
# After the replicas: 2 change in demo D:
#
# 1. Revert the commit:
#      git revert HEAD --no-edit
#      git push
# 2. ArgoCD detects the revert, syncs back to replicas: 1
# 3. One pod terminates, one remains
#
# OR use ArgoCD's built-in history rollback (without Git revert):
#      argocd app history redis --grpc-web
#      argocd app rollback redis <revision-id> --grpc-web
# This rolls back to a previous sync without touching Git.
# NOTE: with selfHeal: true, ArgoCD will re-sync to Git after rollback.
# For a stable rollback: revert in Git.

echo ""
echo ">>> DEMO F: Revert Git commit to roll back replicas change."
echo ">>> Run: git revert HEAD --no-edit && git push"
echo ">>> ArgoCD will sync back to replicas: 1 automatically."

# =============================================================================
# G — Verify Redis is working (connect to it)
# =============================================================================
echo ""
echo ">>> Verifying Redis connectivity..."

# Run a temporary redis-cli pod inside the cluster to test the Service DNS.
kubectl run redis-test \
  --image=redis:7-alpine \
  --restart=Never \
  --rm \
  -it \
  -n redis \
  -- redis-cli -h redis -p 6379 ping
# -h redis: hostname = Service name. DNS: redis.redis.svc.cluster.local
# -p 6379:  Redis port
# Expected output: PONG
# --rm: delete the test pod after it exits

echo ""
echo ">>> If you saw PONG: Redis is reachable via the Service. End-to-end working."
