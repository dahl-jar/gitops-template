# Tutorial: from an empty machine to a running app

k3s, the SealedSecrets controller, Argo CD, then the app and its data services
synced from your fork. Ends at a `200` from `/healthz`.

Needs an Ubuntu machine with `sudo`, a GitHub account, and `kubectl` on your
workstation. Build the app image first: [how-to/build-and-push-image.md](how-to/build-and-push-image.md).

## 1. Fork and clone

Fork this repo, then clone your fork:

```sh
git clone https://github.com/<your-user>/<your-fork>.git
cd <your-fork>
```

## 2. Install k3s

On the machine:

```sh
curl -sfL https://get.k3s.io | sh -
sudo k3s kubectl get nodes        # node shows Ready
```

k3s ships Traefik as the ingress controller.

Copy `/etc/rancher/k3s/k3s.yaml` to `~/.kube/config` on your workstation,
replace `127.0.0.1` with the machine's IP, then:

```sh
kubectl get nodes
```

## 3. Install the SealedSecrets controller

```sh
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/latest/download/controller.yaml
kubectl rollout status -n kube-system deployment/sealed-secrets-controller
```

Install the `kubeseal` CLI on your workstation:

```sh
KUBESEAL_VERSION=$(curl -s https://api.github.com/repos/bitnami-labs/sealed-secrets/releases/latest | grep -oP '"tag_name": "v\K[^"]+')
curl -sLo kubeseal.tar.gz "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
tar xf kubeseal.tar.gz kubeseal
sudo install kubeseal /usr/local/bin/
```

## 4. Install Argo CD

```sh
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl rollout status -n argocd deployment/argocd-server
```

Get the admin password and open the UI:

```sh
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

Log in at `https://localhost:8080` as `admin`. Leave the port-forward running.

## 5. Seal the secrets

```sh
cd manifests/app
# fill every secret.example.yaml first
./seal-secrets.sh
./seal-minio.sh
```

Commit the sealed output:

```sh
cd ../..
git add manifests/app/**/sealedsecret.yaml manifests/app/sealedsecret.yaml
git commit -m "Add sealed secrets"
git push
```

## 6. Point the manifests at your fork

Replace `https://github.com/your-org/your-repo.git` in:

```text
apps/app.yaml
apps/infrastructure.yaml
infrastructure/argocd/appproject.yaml
```

```sh
git commit -am "Point Argo at this fork"
git push
```

## 7. Apply the Applications

```sh
kubectl apply -f infrastructure/argocd/appproject.yaml
kubectl apply -f apps/
kubectl get applications -n argocd        # app, infrastructure -> Synced/Healthy
```

## 8. Verify

```sh
kubectl get pods -n app
kubectl port-forward -n app svc/app 8088:80
curl -i http://localhost:8088/healthz     # 200
```

## Next steps

- Hostname: set it in `manifests/app/ingress.yaml` and
  `infrastructure/cloudflared/configmap.yaml`, create a Cloudflare Tunnel.
- Backups: build an image with `pg_dump`, `gzip`, `gpg`, `rclone`, set it in
  `manifests/app/postgres/backup-cronjob.yaml`, seal the backup secret.
- Monitoring: put your Grafana Cloud push URLs in
  `infrastructure/monitoring/configmap.yaml`. Delete the directory if you
  don't want it.
- Seal the tunnel and Grafana Cloud secrets with kubeseal:

```sh
kubeseal --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system --format=yaml \
  < infrastructure/monitoring/secret.example.yaml \
  > infrastructure/monitoring/sealedsecret.yaml
```
