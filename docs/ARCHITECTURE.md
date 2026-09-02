# Architecture

## Node topology

- 1 control-plane node (k3s server) + 2 worker nodes (k3s agents), all `t3.small` EC2 instances in a single AWS VPC (`10.0.0.0/16`), single public subnet.
- Control plane runs the k3s API server, scheduler, controller-manager, and the embedded SQLite/kine datastore. Workers run application pods only.
- Nodes were originally `t3.micro`; upgraded to `t3.small` after the control plane's CPU credit balance was exhausted under load (see Known Issues).

## Networking

- AWS Security Group: SSH (22) restricted to the operator's current IP, HTTP/HTTPS (80/443) open to the world, Kubernetes API (6443) and Flannel/kubelet ports restricted to the VPC CIDR only — never public.
- Pod network: Flannel VXLAN (k3s default CNI), pod CIDR `10.42.0.0/16`.
- Host-level firewall (UFW) mirrors the Security Group rules as defense-in-depth, applied via the Ansible `hardening` role.

## Request flow

1. Client resolves `taskapp.<control-plane-ip>.nip.io` (nip.io wildcard DNS — maps any subdomain containing an IP back to that IP, avoiding the need for a registered domain).
2. Request hits the control plane's public IP on 443, terminated by Traefik (k3s's bundled ingress controller).
3. cert-manager + a Let's Encrypt `ClusterIssuer` (HTTP-01 challenge via Traefik) issue and renew the TLS certificate automatically.
4. Traefik routes to the `frontend` Service, which load-balances across frontend Pods (nginx serving the built SPA).
5. The frontend's nginx reverse-proxies `/api/*` to the `backend` Service (`backend:5000`) — same-origin API, no separate `api.` subdomain, chosen to avoid a second DNS/cert flow for a small app.
6. Backend Pods connect to Postgres via a headless Service (`postgres:5432`, stable DNS from the StatefulSet).

## Single-server assumptions fixed, per Core requirement

| Requirement | Single-server assumption it removes |
|---|---|
| Namespace + ConfigMap/Secret split | Config and secrets were env vars/files on one host; now cluster-portable and GitOps-manageable |
| Postgres StatefulSet + PVC | DB lived on one host's disk; now on a stable, replaceable volume independent of any one node |
| Backend/frontend 2+ replicas, anti-affinity | App had a single point of failure; now survives losing any one node |
| Migration Job (separate from replica entrypoint) | Migrations ran once, implicitly, on the only instance; now must be safe to run once *explicitly* even though replicas may race (see Known Issues) |
| Probes on every workload | A hung single process was invisible; now Kubernetes actively detects and replaces unhealthy Pods |
| Resource requests/limits | One host, no contention; now the scheduler must pack Pods without starving neighbors |
| `maxUnavailable: 0` rolling updates | Deploys meant downtime; now updates are zero-downtime by construction |
| Ingress + cert-manager TLS | TLS was manually renewed on one box; now automatically issued/renewed per Service |
| Pinned image tags | `:latest` meant "whatever's on this host right now"; now every deploy is reproducible |

## Advanced features implemented

- **HPA** (backend, CPU-based, 2–6 replicas, 60% target) — demonstrates horizontal scaling under load.
- **PodDisruptionBudget** (`minAvailable: 1` on both backend and frontend) — ensures voluntary disruptions (node drains, upgrades) can't take the app fully offline.
- **securityContext** — `allowPrivilegeEscalation: false` on both backend and frontend containers; `runAsNonRoot`/dropped Linux capabilities were attempted but reverted for the frontend specifically (see Known Issues) because the base nginx image requires root to create its cache directories.

## Known issues and trade-offs (documented honestly)

**1. Migration race condition.** The backend image's entrypoint runs `alembic upgrade head` on every container start, in addition to the dedicated migration `Job` this repo provides per the brief's requirement. At 2+ replicas, both could theoretically race on the same migration. In practice, Alembic uses a database-level advisory lock during `upgrade head`, so concurrent attempts are safe: one applies the migration, the other observes the schema is already at head and no-ops. The dedicated Job remains the canonical, explicit migration step; the entrypoint behavior is a pre-existing constraint of the provided image, not something this repo's manifests can remove without patching the image itself.

**2. Anti-affinity: `preferred`, not `required`.** Initial manifests used `requiredDuringSchedulingIgnoredDuringExecution` pod anti-affinity to force replicas onto separate nodes. With exactly 3 nodes and `maxSurge: 1`, this deadlocked every rolling update: Kubernetes could not schedule the transient 4th Pod, since no node was permitted a second replica. Switched to `preferredDuringSchedulingIgnoredDuringExecution` (weight 100) — spreading across nodes remains the default outcome, but updates no longer deadlock. Trade-off: under scheduler pressure, replicas can transiently co-locate on one node (observed: frontend and backend replicas colocating after a rollout) rather than being hard-guaranteed to spread.

**3. GitOps auto-sync reliability.** Argo CD was installed, and the initial full sync of `manifests/` to the cluster works and shows `Synced`/`Healthy`. However, incremental changes (e.g. a replica count bump) pushed to `main` were not reliably picked up by Argo's automated sync in this environment — `operationState` on the Application repeatedly showed no actual sync operation despite the app reporting "Synced". A full reinstall of Argo CD resolved this once, but the issue recurred. Root cause not conclusively identified; resource starvation was checked and ruled out (CPU/memory usage was low at the time). Manual `kubectl apply`/`kubectl scale` was used as a workaround to keep the cluster's live state matching git during development. This is a genuine limitation of this deployment as currently configured, not a design choice.

**4. HPA vs. static `replicas`.** Once the HPA is attached to the backend Deployment, it owns the `replicas` field; the static `replicas: 3` in `manifests/backend/deployment.yaml` is superseded and the HPA's `minReplicas`/`maxReplicas` (2–6) govern actual Pod count based on live CPU usage.

## Secrets

Secrets are managed with Sealed Secrets (Bitnami controller): a plaintext Secret is encrypted client-side with `kubeseal` against the cluster's public key, producing a `SealedSecret` that is safe to commit to git. The controller decrypts it into a normal Kubernetes Secret on the cluster. No plaintext secret material is ever committed.
