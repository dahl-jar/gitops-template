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
  monitoring/               Grafana Alloy pushing metrics and logs to Grafana Cloud
  traefik/                  ingress controller config
manifests/
  app/                      the app namespace and its workloads
    deployment.yaml         the app Deployment
    postgres/               StatefulSet, Service, exporter, backup CronJob
    redis/                  StatefulSet, Service
    meilisearch/            StatefulSet, Service
    minio/                  StatefulSet, Service, bucket-and-user setup Job
    networkpolicy.yaml      default-deny plus per-flow allows
    kustomization.yaml      lists every resource; CI pins the image tag
    seal-*.sh               encrypt example secrets into committable SealedSecrets
```

## Architecture

Traffic enters through the Cloudflare Tunnel: `cloudflared` connects outbound
to Cloudflare and forwards each public hostname to Traefik, which routes by
host. CI rewrites the
image tag in `manifests/app/kustomization.yaml`; Argo CD syncs the commit and
rolls the Deployment. Alloy pushes metrics and pod logs to Grafana Cloud.

## Secrets

[Bitnami SealedSecrets](https://github.com/bitnami-labs/sealed-secrets): only
the cluster's controller can decrypt the committed `sealedsecret.yaml` files.
Fill each `secret.example.yaml`, then:

```sh
cd manifests/app
./seal-secrets.sh        # app, postgres, meilisearch, backup
./seal-minio.sh          # generates and seals MinIO creds
GH_USER=your-org GHCR_PAT=... ./seal-ghcr-pull.sh   # private image pull
```

## Requirements

- A cluster (k3s or otherwise) with Traefik and the SealedSecrets controller
- Argo CD pointed at your fork
- A Cloudflare Tunnel, and an S3-compatible bucket if you want the backups
- A Grafana Cloud stack if you keep the monitoring
- `kubectl` and `kubeseal` on the workstation

## Adapting

Rename the `app` namespace and labels, set the hostname in the ingress and
`cloudflared` config, point the image at your registry, seal your secrets.
`kustomize build manifests/app` renders the set for a dry run.

## License

MIT. See [LICENSE](LICENSE).
