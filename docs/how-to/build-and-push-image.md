# How to build and push the container image

## 1. Dockerfile

Multi-stage, distroless non-root runtime to match the pod `securityContext`:

```dockerfile
FROM eclipse-temurin:21-jdk AS build
WORKDIR /src
COPY . .
RUN ./gradlew --no-daemon bootJar

FROM gcr.io/distroless/java21-debian12:nonroot
COPY --from=build /src/build/libs/*.jar /app/app.jar
USER nonroot
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

## 2. Build and push

```sh
echo "$GHCR_PAT" | docker login ghcr.io -u your-org --password-stdin   # PAT: write:packages
TAG=sha-$(git rev-parse HEAD)
docker build -t ghcr.io/your-org/app:$TAG .
docker push ghcr.io/your-org/app:$TAG
docker buildx imagetools inspect ghcr.io/your-org/app:$TAG --format '{{json .Manifest.Digest}}'
```

## 3. Pin the version

In CI, call `.github/workflows/pin-image.example.yml` from the service repo
after the push, with the image name and the digest from step 2. It writes
`versions/app/kustomization.yaml` and pushes; Argo CD rolls the Deployment.

By hand, the same thing is:

```sh
cd versions/app
kustomize edit set image ghcr.io/your-org/app=ghcr.io/your-org/app:$TAG@$DIGEST
git commit -am "Deploy app $TAG" && git push
```

For a private package, seal a pull secret once:

```sh
GH_USER=your-org GHCR_PAT=... ./seal-ghcr-pull.sh   # in modules/app/base
```
