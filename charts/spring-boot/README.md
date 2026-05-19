# Spring Boot

Helm chart for deploying a Spring Boot application on Kubernetes. Requires
**Helm 4+** and **Kubernetes 1.33+**.

Targets the standard Spring Boot toolchain: images built with the Spring Boot
Maven/Gradle plugin ([Paketo Buildpacks](https://paketo.io/)) running with
Spring Boot defaults. The chart auto-wires `SERVER_PORT`, Actuator probes,
ServiceMonitor scraping, and graceful shutdown against those defaults.

## Install

```
helm install my-spring-boot oci://ghcr.io/grafjo/charts/spring-boot --version <x.y.z>
```

### Verifying releases

Charts are signed with [cosign](https://github.com/sigstore/cosign) using
GitHub OIDC keyless signing. Verify before installing:

```
cosign verify ghcr.io/grafjo/charts/spring-boot:<x.y.z> \
  --certificate-identity-regexp 'https://github.com/grafjo/helm-charts/.github/workflows/release-oci.yaml@.+' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

Re-signing an already-published version requires bumping the chart version —
OCI artifacts are content-addressed and won't be re-pushed on the same tag.

## Build the image

[Cloud Native Buildpacks](https://docs.spring.io/spring-boot/reference/packaging/container-images/cloud-native-buildpacks.html):

```console
$ ./gradlew bootBuildImage --imageName=my-org/my-app:1.0.0
$ ./mvnw spring-boot:build-image -Dspring-boot.build-image.imageName=my-org/my-app:1.0.0
```

## Image

`image.repository` is **required** — it has no default. `image.tag` defaults to
`.Chart.AppVersion`; set it explicitly to pin a version.

```yaml
image:
  repository: my-org/my-app
  tag: "1.0.0"
  containerPort: 8080   # SERVER_PORT is auto-set to this value
```

## Environment variables

App env goes in the `env:` map. Each value is one of:

- scalar (string / int / bool / float) — stringified and quoted
- `{value: <scalar>}`
- `{secretKeyRef: {name, key, optional?}}` / `{configMapKeyRef: ...}`
- `{fieldRef: {fieldPath, apiVersion?}}` / `{resourceFieldRef: ...}`

```yaml
env:
  POSTGRES_DB: app
  FEATURE_ON: true
  SPRING_DATASOURCE_PASSWORD:
    secretKeyRef: { name: postgres-creds, key: password }
  POD_IP:
    fieldRef: { fieldPath: status.podIP }
```

Chart-managed entries render first (`SERVER_PORT`, `SERVER_SHUTDOWN`,
`SPRING_LIFECYCLE_TIMEOUT_PER_SHUTDOWN_PHASE`, optionally `MANAGEMENT_SERVER_*`);
user entries from `env:` follow alphabetically. To override a chart-managed
entry, supply the same key in `env:`.

Because the map deep-merges under Flux HelmRelease patches, overlays specify
only what differs from base — at any key, a scalar replaces a map cleanly:

```yaml
# base
env:
  DB_PASSWORD:
    secretKeyRef: { name: prod-pg, key: password }

# overlay
env:
  DB_PASSWORD: "dev-password"
```

**`$(VAR)` interpolation is unsupported** because entries render in alphabetical
order. Inline literal values instead of chaining.

## Spring Boot Actuator

By default Actuator shares the application port. To expose it on a dedicated
port:

```yaml
customizedManagementServer:
  enabled: true
  port: 8090
  address: 0.0.0.0
```

This adds an `http-management` container/Service port and auto-injects
`MANAGEMENT_SERVER_PORT` / `MANAGEMENT_SERVER_ADDRESS`. The default probes and
ServiceMonitor automatically follow the Actuator port.

## Graceful Shutdown

Kubernetes sends `SIGTERM` and starts removing the pod from Service endpoints
**in parallel** — without a `preStop` hook, in-flight requests die while
clients still route to the draining pod via stale endpoint caches.

The chart ships an end-to-end recipe out of the box:

```
0s              10s                     40s                  60s
│───preStop sleep───│───graceful shutdown───│────JVM slack────│
                                                              │
                                                          SIGKILL
```

| Step | Where | Default |
|---|---|---|
| `lifecycle.preStop.sleep` | pod | 10s |
| `SERVER_SHUTDOWN=graceful` (auto-injected env) | container | `graceful` |
| `SPRING_LIFECYCLE_TIMEOUT_PER_SHUTDOWN_PHASE` (auto-injected env) | container | `30s` |
| `terminationGracePeriodSeconds` | pod | 60s |

**Invariant:** `terminationGracePeriodSeconds ≥ preStop + springTimeout + jvmSlack`.

Override either env var by adding the key to `env:`. Drop the preStop hook
with `lifecycle: null`.

## Prometheus Operator

```yaml
serviceMonitor:
  enabled: true
```

Scrapes `/actuator/prometheus`. Port follows Actuator (auto-switched when
`customizedManagementServer.enabled`).

## Other knobs

Toggle via `values.yaml`:

- `ingress.enabled` / `httpRoute.enabled` — Ingress and Gateway API routing
- `autoscaling.enabled` — HPA
- `extraInitContainers` — `tpl`-rendered string
- `volumes` / `volumeMounts` / `podLabels` / `nodeSelector` / `tolerations` /
  `affinity` / `topologySpreadConstraints` — standard pod-spec passthrough

## Migrating from v1.x

`v2.0.0` is a breaking release.

1. **`extraEnv` / `extraEnvFrom` → `env` map.** Plain entries become scalar
   shorthand; secret references become `{secretKeyRef: ...}`.
2. **Inline `$(VAR)` chains** — interpolation no longer resolves reliably.
3. **Probes are structured YAML**, not `tpl`-rendered strings.
4. **Drop manual `http-management` overrides** on probes and `serviceMonitor.port`
   — auto-switched now.
5. **`serviceAccount.automountServiceAccountToken` → `serviceAccount.automount`**
   (applied to the SA object, not the pod spec).
6. **Unopinionated defaults** for `securityContext`, `podSecurityContext`,
   `resources` — now `{}`. Set them explicitly.
7. **`image.tag` defaults to `.Chart.AppVersion`** — set explicitly to override.
8. **`rbac` block removed.** Manage `Role`/`Binding` as separate Kustomize
   resources next to your `HelmRelease`.
9. **`secrets` block removed.** Manage `Secret` resources externally (SealedSecrets,
   ExternalSecrets, CSI Secrets Store) and reference them via the `env` map:
   ```yaml
   # before (v1.x)
   secrets:
     db:
       password: "s3cret"

   # after (v2.x) — create the Secret out-of-band, then:
   env:
     DB_PASSWORD:
       secretKeyRef: { name: my-app-db, key: password }
   ```
10. **Helm 4 + Kubernetes 1.33+ required.**
