# k3s GitOps template

Kubernetes manifests for running a stateful web app on a single-node k3s
cluster, deployed by Argo CD and reached through a Cloudflare Tunnel. The app is
a JVM service backed by Postgres, Redis, Meilisearch, and MinIO, with a daily
encrypted Postgres backup.

Names are generic (`app`, `your-org`, `example.com`); secrets are example files
you fill in and seal.

Setup: [tutorial](docs/tutorial.md). Image: [build and push](docs/how-to/build-and-push-image.md).

## Layout

```
apps/                       Argo CD Application definitions
  app.yaml                  points at manifests/app
  infrastructure.yaml       points at infrastructure/
infrastructure/             cluster-wide platform services
  argocd/                   AppProject scoping what the app may deploy
  cloudflared/              tunnel connector and config
  traefik/                  ingress controller config
manifests/
  app/                      the app namespace and its workloads
    deployment.yaml         the app; its Service, Ingress, ConfigMap sit next to it
    postgres/               StatefulSet, Service, exporter, backup CronJob
    redis/                  StatefulSet, Service
    meilisearch/            StatefulSet, Service
    minio/                  StatefulSet, Service, bucket-and-user setup Job
    networkpolicy.yaml      default-deny plus per-flow allows
    kustomization.yaml      ties it together; CI pins the image tag here
    seal-*.sh               turn example secrets into committable SealedSecrets
```

Argo CD reads `apps/`: the two Application objects point it at `infrastructure/`
and `manifests/app`, and it reconciles each.

## Architecture

The cluster opens no inbound ports. `cloudflared` dials out to Cloudflare's edge
and maps a public hostname to the in-cluster Traefik ingress, which routes to the
app by host.

CI builds the image, pushes it, and rewrites the tag in
`manifests/app/kustomization.yaml`. Argo CD reconciles the commit and rolls the
Deployment.

Pods run non-root with a read-only root filesystem and no Linux capabilities.
The namespace denies all traffic by default; each flow is allowed by name. The
app's egress allows HTTPS but excludes the pod and service CIDRs, so a
compromised app pod cannot reach other namespaces.

## Secrets

Secrets use [Bitnami SealedSecrets](https://github.com/bitnami-labs/sealed-secrets).
The controller holds the private key; the encrypted `sealedsecret.yaml` files are
safe to commit and only this cluster can decrypt them.

Set values in each `secret.example.yaml`, then seal:

```sh
cd manifests/app
./seal-secrets.sh        # app, postgres, meilisearch, backup
./seal-minio.sh          # mints and seals MinIO creds
GH_USER=your-org GHCR_PAT=... ./seal-ghcr-pull.sh   # private image pull
```

## Requirements

- A cluster (k3s or otherwise) with Traefik and the SealedSecrets controller
- Argo CD pointed at your fork
- A Cloudflare Tunnel, and an S3-compatible bucket if you want the backups
- `kubectl`, `kubeseal`, and `kustomize` for a local `kustomize build manifests/app`

## Adapting

Rename the `app` namespace and labels, set the hostname in the ingress and
`cloudflared` config, point the image at your registry, seal your secrets.
`kustomize build manifests/app` renders the set for a dry run.

## License

MIT. See [LICENSE](LICENSE).
