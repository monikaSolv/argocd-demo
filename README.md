# ArgoCD — Redis on Kind (Local GitOps Demo)

End-to-end GitOps setup using ArgoCD on a local kind cluster.  
Deploys Redis with a ConfigMap, Deployment, Service, and Namespace — all managed from Git.

---

## What is GitOps / ArgoCD

**GitOps** means Git is the single source of truth for your cluster state.  
You push YAML to Git. A controller watches Git and applies the diff to the cluster automatically.  
If someone manually changes the cluster, the controller reverts it. Git always wins.

**ArgoCD** is that controller. It runs inside Kubernetes and continuously reconciles:

```
Git repo (desired state)
     ↓  ArgoCD polls every 3 min (or webhook)
ArgoCD compares desired vs live state
     ↓  if diff found
ArgoCD applies the diff  (kubectl apply under the hood)
     ↓
Live cluster matches Git
```

**Key terms:**
| Term | Meaning |
|---|---|
| Application | ArgoCD CRD — "watch this repo path, deploy to this namespace" |
| Synced | Git matches cluster |
| OutOfSync | Git differs from cluster — change pending |
| Healthy | All pods running and passing probes |
| Self-heal | ArgoCD reverts manual kubectl changes back to Git state |
| Prune | ArgoCD deletes resources removed from Git |

---

## Prerequisites

```bash
brew install kind kubectl argocd
docker   # must be running
```

---

## Directory Structure

```
argocd/
├── setup/
│   ├── 01-install.sh            # create kind cluster + install ArgoCD
│   ├── 02-access.sh             # port-forward UI + login
│   └── 03-deploy-and-demo.sh    # apply Application + demo scripts
├── apps/
│   └── redis/
│       ├── namespace.yaml       # redis namespace
│       ├── configmap.yaml       # redis.conf (maxmemory, eviction policy)
│       ├── deployment.yaml      # Redis pod with probes + resource limits
│       └── service.yaml         # ClusterIP — stable DNS for Redis
└── argocd-applications/
    └── redis.yaml               # ArgoCD Application CRD — the wiring file
```

ArgoCD watches `apps/redis/` in this repo. Every YAML file in that directory is applied to the cluster. Add a file → ArgoCD deploys it. Remove a file → ArgoCD deletes the resource (with `prune: true`).

---

## Setup

### 1 — Create kind cluster and install ArgoCD

```bash
bash setup/01-install.sh
```

What it does:
- Creates a kind cluster
- Creates the `argocd` namespace
- Applies the official ArgoCD install manifest (~15 pods)
- Waits for `argocd-server` Deployment to become available

Takes ~90 seconds for images to pull.

### 2 — Get password and open UI (keep this terminal running)

```bash
bash setup/02-access.sh
```

What it does:
- Reads the auto-generated admin password from `argocd-initial-admin-secret`
- Logs in via the `argocd` CLI
- Opens port-forward: `localhost:8080` → `argocd-server` pod

Open browser: `https://localhost:8080`  
Username: `admin`  
Password: printed by the script

> Open a **new terminal** for all remaining steps.

### 3 — Push this repo to your GitHub

ArgoCD needs a remote Git URL — it cannot read local files.

```bash
git init
git config user.email "<YOUR_EMAIL>"
git config user.name  "<YOUR_GITHUB_USERNAME>"
git add .
git commit -m "Initial ArgoCD Redis example"
git remote add origin git@github.com:<YOUR_GITHUB_USERNAME>/argocd-demo.git
git push -u origin main
```

Then update `repoURL` in `argocd-applications/redis.yaml`:
```yaml
repoURL: https://github.com/<YOUR_GITHUB_USERNAME>/argocd-demo.git
```
Push the change.

### 4 — Apply the ArgoCD Application

```bash
kubectl apply -f argocd-applications/redis.yaml
```

This is the **only** `kubectl apply` you run manually.  
After this, ArgoCD manages everything — it reads the Application spec, clones the repo, and applies `apps/redis/` to the cluster.

Watch sync:
```bash
kubectl get pods -n redis -w
```

Expected progression:
```
NAME            READY   STATUS              RESTARTS
redis-xxxxx     0/1     ContainerCreating   0
redis-xxxxx     0/1     Running             0
redis-xxxxx     1/1     Running             0
```

Or watch in the UI — tile goes: `OutOfSync → Synced → Healthy`

### 5 — Verify Redis is reachable

```bash
kubectl run redis-test \
  --image=redis:7-alpine \
  --restart=Never \
  --rm -it \
  -n redis \
  -- redis-cli -h redis -p 6379 ping
```

Expected: `PONG`

`-h redis` works because the Service name is `redis` — Kubernetes DNS resolves `redis.redis.svc.cluster.local` automatically.

---

## Demo Workflows

### GitOps Update — change Git, cluster follows

1. Edit `apps/redis/deployment.yaml`: change `replicas: 1` → `replicas: 2`
2. Commit and push
3. Force sync (or wait ~3 min):
   ```bash
   argocd app sync redis --grpc-web
   ```
4. Watch:
   ```bash
   kubectl get pods -n redis
   ```
   Two Redis pods appear — without ever running `kubectl scale`.

**This is GitOps**: cluster state follows Git state. No direct kubectl changes.

### Self-Healing — manual change gets reverted

```bash
kubectl scale deployment redis --replicas=0 -n redis
```

Redis pods terminate. ArgoCD detects OutOfSync and reverts to `replicas: 2` (or whatever Git says) within ~3 minutes. Force immediately:

```bash
argocd app sync redis --grpc-web
```

**This is self-healing**: ArgoCD guarantees Git is always the truth, even if someone bypasses it with kubectl.

### Rollback — revert a Git commit

```bash
git revert HEAD --no-edit
git push
```

ArgoCD syncs back to the previous state automatically.

Or use ArgoCD's built-in rollback (without touching Git):
```bash
argocd app history redis --grpc-web
argocd app rollback redis <revision-id> --grpc-web
```

---

## Key Files Explained

### `argocd-applications/redis.yaml`

The most important file. Tells ArgoCD:
- **WHERE** to get desired state → `repoURL` + `path`
- **WHERE** to deploy → `destination.server` + `namespace`
- **HOW** to behave → `syncPolicy`

`destination.server: https://kubernetes.default.svc` means "the same cluster ArgoCD is running in." This is the Kubernetes API server's internal DNS — automatically available in every cluster, no setup needed.

`selfHeal: true` — reverts manual kubectl changes.  
`prune: true` — deletes resources removed from Git.  
`CreateNamespace=true` — creates the `redis` namespace if it doesn't exist.

### `apps/redis/deployment.yaml`

- `resources.requests` — minimum CPU/memory the scheduler reserves for this pod
- `resources.limits` — hard ceiling enforced by the kernel (OOMKill if exceeded)
- `livenessProbe` — restarts container if `redis-cli ping` fails
- `readinessProbe` — removes pod from Service endpoints until it can serve traffic
- `volumeMounts` + `volumes` — mounts `redis-config` ConfigMap as `/etc/redis/redis.conf`

### `apps/redis/configmap.yaml`

`maxmemory 128mb` must be less than the Deployment's memory limit (`256Mi`).  
Redis evicts keys before the kernel kills the pod — correct order of protection.

---

## Cleanup

```bash
# Delete just the ArgoCD Application (removes all Redis resources too)
kubectl delete -f argocd-applications/redis.yaml

# Or delete the entire kind cluster (wipes everything)
kind delete cluster --name <YOUR_CLUSTER_NAME>
```
