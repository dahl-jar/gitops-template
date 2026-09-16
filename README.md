# gitops-template

Manifests for a single-node k3s cluster. Argo CD deploys everything from this
repo, traffic comes in through a Cloudflare Tunnel, and CI decides which image
version runs.

The example service is `app`: a JVM app with Postgres, Redis, Meilisearch and
MinIO, and a nightly encrypted Postgres backup. Names are placeholders (`app`,
`your-org`, `example.com`).

## How it fits together

Each service has three folders. `modules/app` holds the manifests. `deploy/app`
is what Argo CD points at; it pulls in the module, the version and
`variables.env`. `versions/app` holds the image tag and digest, and only CI
writes it.

When the service repo builds an image, it runs the job in
`.github/workflows/pin-image.example.yml`. That job writes the new tag and
digest into `versions/app` and pushes. The `verify` workflow renders and
validates every manifest, and Argo CD rolls out the commit.

`platform/` holds the cluster-wide pieces: the Argo CD project, the tunnel,
monitoring, Traefik and a storage class with `Retain`, so deleting a claim or an
Application keeps the data on disk.

## Getting started

- [Tutorial](docs/tutorial.md), from an empty machine to a running app
- [Build and push the image](docs/how-to/build-and-push-image.md)
- [Add a service](docs/how-to/add-a-service.md)

## Secrets

Fill each `secret.example.yaml`, then seal it. Only the cluster can decrypt the
committed `sealedsecret.yaml` files.

```sh
cd modules/app/base
./seal-secrets.sh        # app, postgres, meilisearch, backup
./seal-minio.sh          # generates and seals MinIO creds
GH_USER=your-org GHCR_PAT=... ./seal-ghcr-pull.sh   # private image pull
```

## License

MIT. See [LICENSE](LICENSE).
