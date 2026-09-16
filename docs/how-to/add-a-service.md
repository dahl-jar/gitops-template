# How to add a service

```sh
# manifests
mkdir -p modules/<svc>/base deploy/<svc> versions/<svc>
cp modules/app/module.yaml modules/<svc>/module.yaml
cp deploy/app/kustomization.yaml deploy/<svc>/
cp versions/app/kustomization.yaml versions/<svc>/
```

Write the service's manifests under `modules/<svc>/base` with a
`kustomization.yaml` listing them. Put every claim on `local-path-retain`.

Replace `app` with `<svc>` in the three copied files and in a copy of
`apps/app.yaml`. Give the service its own AppProject next to
`platform/argocd/appproject.yaml`.

Plain settings go in `deploy/<svc>/variables.env`. Secrets are sealed into the
module base.

```sh
# check before pushing
scripts/render-all.sh
uv run --with pyyaml python3 scripts/check-storage-classes.py out/*.yaml
```

In the service repo, call `pin-image.example.yml` after the image push with
`service: <svc>`. The first push writes the real tag and digest into
`versions/<svc>`.
