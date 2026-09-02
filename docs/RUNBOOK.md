# Runbook

## Provision from zero

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

## Cluster bring-up

```bash
cd ../ansible
cp inventory.ini.example inventory.ini
ansible k3s_cluster -i inventory.ini -m ping
ansible-playbook -i inventory.ini site.yml
ssh -i ~/.ssh/<key> ubuntu@<control-plane-ip> "sudo kubectl get nodes -o wide"
```

## Local kubectl access

The API server (6443) is intentionally not public. Access it via an SSH tunnel:

```bash
ssh -i ~/.ssh/<key> ubuntu@<control-plane-ip> "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/capstone-config
sed -i 's/127.0.0.1/<control-plane-ip>/' ~/.kube/capstone-config
ssh -i ~/.ssh/<key> -L 6443:localhost:6443 ubuntu@<control-plane-ip> -N &
sed -i 's/<control-plane-ip>/127.0.0.1/' ~/.kube/capstone-config
export KUBECONFIG=~/.kube/capstone-config
kubectl get nodes
```

## Install platform components

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.1/controller.yaml
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.0/manifests/install.yaml
```

## Deploy the app

```bash
kubectl apply -f manifests/base/namespace.yaml
kubectl apply -f manifests/config/
kubectl apply -f manifests/database/
kubectl apply -f manifests/backend/
kubectl apply -f manifests/frontend/
kubectl apply -f manifests/ingress/cluster-issuer.yaml
kubectl apply -f manifests/ingress/ingress.yaml
kubectl apply -f gitops/applications/taskapp.yaml
```

## Deploy a change

Preferred (GitOps): edit a manifest, commit, push to `main`. Argo CD should auto-sync within ~3 minutes.

```bash
git add manifests/<changed-file>
git commit -m "..."
git push
kubectl get application taskapp -n argocd
```

Known limitation: automated sync has been unreliable in this environment (see ARCHITECTURE.md). If a change hasn't applied after several minutes:

```bash
kubectl patch application taskapp -n argocd --type merge -p '{"metadata": {"annotations": {"argocd.argoproj.io/refresh": "hard"}}}'
kubectl apply -f manifests/<changed-file>
```

## Scale

Backend scales automatically via HPA (2-6 replicas, 60% CPU target):

```bash
kubectl get hpa -n taskapp
```

## Roll back a bad deploy

```bash
kubectl rollout history deployment/backend -n taskapp
kubectl rollout undo deployment/backend -n taskapp
```

## Recover from a dead worker node

```bash
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
kubectl get pods -n taskapp -o wide
kubectl uncordon <node-name>
```

PodDisruptionBudgets (minAvailable: 1 on backend and frontend) prevent a drain from taking either service fully offline.

## Recover from a dead backend

```bash
kubectl get pods -n taskapp -l app=backend
kubectl logs <pod-name> -n taskapp
kubectl describe pod <pod-name> -n taskapp
```

## Recover from a bad migration

```bash
kubectl logs -l job-name=backend-migrate -n taskapp
kubectl delete job backend-migrate -n taskapp
kubectl apply -f manifests/backend/migration-job.yaml
```

## Common gotchas encountered during this build

- Public IP drift: EC2 assigns a new public IP on reconnect. If SSH/kubectl time out, check current IP against terraform.tfvars my_ip, update, terraform apply.
- 6443 is intentionally not public; use the SSH tunnel above.
- CPU credit exhaustion on t3.micro caused k3s agents to fail joining; fixed by resizing to t3.small.
