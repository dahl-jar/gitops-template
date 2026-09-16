<h1 align="center">gitops-template</h1>

<p align="center">
  Kubernetes manifests for a single-node k3s cluster, deployed by Argo CD from this repo.
</p>

## Stack

k3s · Argo CD · Kustomize · Sealed Secrets · Cloudflare Tunnel · Traefik · Grafana Alloy · GitHub Actions

## Service

The example service is `app`, a JVM app with Postgres, Redis, Meilisearch and MinIO, and a nightly encrypted Postgres backup. The names are placeholders (`app`, `your-org`, `example.com`).

### Layout

Each service has three folders. `modules/app` has the manifests, `deploy/app` is what Argo CD points at, and `versions/app` has the image tag and digest. Only CI writes the version, so nobody has to edit it by hand.

### Deploy

When the service repo builds an image, it runs the job in `.github/workflows/pin-image.example.yml`. The job writes the new tag and digest into `versions/app` and pushes. The `verify` workflow renders and checks every manifest, and Argo CD rolls out the commit.

## Platform

`platform/` has the Argo CD project, the tunnel, monitoring, Traefik and a storage class with `Retain`. Deleting a claim or an Application keeps the data on disk.

## Secrets

Fill each `secret.example.yaml` and seal it. Only the cluster can decrypt the committed `sealedsecret.yaml` files.

```sh
cd modules/app/base
./seal-secrets.sh        # app, postgres, meilisearch, backup
./seal-minio.sh          # generates and seals MinIO creds
GH_USER=your-org GHCR_PAT=... ./seal-ghcr-pull.sh   # private image pull
```

## Docs

[Set up a cluster and run the app](docs/tutorial.md). [Build and push the image](docs/how-to/build-and-push-image.md). [Add a service](docs/how-to/add-a-service.md).

## License

MIT. See [LICENSE](LICENSE).
