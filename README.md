# k3s GitOps template

Kubernetes manifests for running services on a single-node k3s cluster,
deployed by Argo CD and reached through a Cloudflare Tunnel. One example
service, `app`: a JVM app with Postgres, Redis, Meilisearch and MinIO, plus a
nightly encrypted Postgres backup.

Names are generic (`app`, `your-org`, `example.com`). Secrets are example files
you fill in and seal.

Setup: [tutorial](docs/tutorial.md). Image: [build and push](docs/how-to/build-and-push-image.md).
Second service: [add a service](docs/how-to/add-a-service.md).

## Layout

```text
apps/           one Argo CD Application per service, plus platform
platform/       cluster-wide: Argo CD project, tunnel, monitoring, Traefik, storage class
modules/<svc>/  the service's manifests, never deployed directly
deploy/<svc>/   what Argo CD deploys: the module, its version, and variables.env
versions/<svc>/ image tag and digest, written by CI
scripts/        render and check everything, used by the verify workflow
```

## How a deploy happens

The service repo builds the image and runs the job in
`.github/workflows/pin-image.example.yml`, which writes the new tag and digest
into `versions/<svc>/kustomization.yaml` and pushes. The `verify` workflow
renders every kustomization, validates the output with kubeconform, checks that
every claim uses a Retain storage class and that every pinned image exists in
its registry. Argo CD syncs the commit and rolls the pod. Nobody edits a version
by hand.

## Storage

`platform/storage/local-path-retain.yaml` is the k3s local-path provisioner
with `reclaimPolicy: Retain`. Every claim names it, or `local-static` for a
volume you create yourself, like the backup directory. Deleting a claim or an
Application keeps the data on disk.

## Secrets

[Bitnami SealedSecrets](https://github.com/bitnami-labs/sealed-secrets): only
the cluster's controller can decrypt the committed `sealedsecret.yaml` files.
Fill each `secret.example.yaml`, then:

```sh
cd modules/app/base
./seal-secrets.sh        # app, postgres, meilisearch, backup
./seal-minio.sh          # generates and seals MinIO creds
GH_USER=your-org GHCR_PAT=... ./seal-ghcr-pull.sh   # private image pull
```

## Requirements

- A cluster (k3s or otherwise) with Traefik and the SealedSecrets controller
- Argo CD pointed at your fork
- A Cloudflare Tunnel
- A Grafana Cloud stack if you keep the monitoring
- `kubectl`, `kubeseal` and `kustomize` on the workstation

## License

MIT. See [LICENSE](LICENSE).
