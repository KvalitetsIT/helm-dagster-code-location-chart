# dagster-code-location

A single Dagster code location: a hardened gRPC code server (Deployment + Service) deployed as its own release into a per-project namespace. Carries the discovery labels the KDS workspace generator groups locations by, and the container context the tenant core's K8sRunLauncher uses to launch this location's run pods.

**Homepage:** <https://github.com/KvalitetsIT>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| KvalitetsIT | <kithosting@kvalitetsit.dk> | <https://github.com/KvalitetsIT/helm-repo> |

## Source Code

* <https://github.com/KvalitetsIT/helm-dagster-code-location-chart>
* <https://github.com/KvalitetsIT/helm-templates-chart/tree/main/charts/templates>

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| https://raw.githubusercontent.com/KvalitetsIT/helm-repo/master/ | templates | 2.2.0 |

## Values

### Code location

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| image | object | See [values.yaml](values.yaml) | Code server image. Set tag or digest (or both). |
| image.repository | string | `""` | Image repository, e.g. ghcr.io/my-org/my-location. Required. |
| image.tag | string | `""` | Image tag. Required unless digest is set. |
| image.digest | string | `""` | Image digest (recommended). Required unless tag is set. |
| image.pullPolicy | string | `"IfNotPresent"` | Pull policy for the code server. |
| module | string | `""` | Python module passed as -m. Defaults to <release name, '-'->'_'>.definitions. |
| locationName | string | `""` | Location name and discovery-label value. Defaults to the release name. |
| args | list | See [values.yaml](values.yaml) | Container args for the code server (native container args, templated). Default runs `dagster api grpc` on 4000 serving `module`. Override with the full arg list for a different entrypoint, e.g. `dagster code-server start ...` for hot reload. |
| resources | object | See [values.yaml](values.yaml) | Code-server resources (definition loading only). Run pods are sized via runPod.resources. |
| env | list | [] | Env for the code server and run pods. HOME, TMPDIR and PYTHONDONTWRITEBYTECODE default to /tmp but can be overridden by setting them here. |
| extraEnvs | list | [] | Env appended after env, so an overlay values file extends rather than replaces it. |
| envFrom | list | [] | envFrom sources for the code server and run pods, e.g. `- secretRef: {name: x}`. |
| extraEnvFrom | list | [] | envFrom appended after envFrom, so an overlay values file extends rather than replaces it. |
| volumes | list | See [values.yaml](values.yaml) | Code-server volumes: {name, mountPath, readOnly?, subPath?, volumeSpec}. Default is a writable /tmp the read-only root filesystem needs. Run-pod volumes come from the core runLauncher. |
| extraVolumes | list | [] | Volumes appended after volumes, so an overlay values file extends rather than replaces it. |
| imagePullSecrets | list | `["ghcr-pull"]` | imagePullSecret names for the code server and run pods. |
| serviceAccountName | string | `"default"` | ServiceAccount for the code server and run pods. The code location is unprivileged: the namespace default SA, token unmounted, no RBAC. |
| metadataSecret | object | See [values.yaml](values.yaml) | Metadata DB password secret the code server reads as DAGSTER_PG_PASSWORD. Schedule and sensor evaluation run in the code server and access the Dagster instance (Postgres), so it needs the password; run pods get it from the core runLauncher instead. The secret is reflected into the namespace by the tenant projectDefaults under this fixed name. |
| podSecurityContext | object | See [values.yaml](values.yaml) | Pod securityContext for the code server (fsGroup lets the non-root uid write /tmp). |
| containerSecurityContext | object | See [values.yaml](values.yaml) | Container securityContext for the code server. |

### Run pods

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| runPod | object | See [values.yaml](values.yaml) | Per-location run-pod overrides, deep-merged onto the core runLauncher baseline. Set only what differs; empty inherits the core (securityContext, /tmp, netbird, resources floor). |
| runPod.resources | object | `{}` | Run-pod resources (sizes the data work). Empty inherits the core baseline. |
| runPod.podSecurityContext | object | `{}` | Pod securityContext override (e.g. a different runAsUser). Empty inherits the core baseline. |

### Networking

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| networkPolicies | object | See [values.yaml](values.yaml) | NetworkPolicies for this code location. Rendered by this chart (not the subchart) through the templates dependency's renderer with this chart as the root, so template expressions in the values resolve against this chart's helpers. Ships the ingress policy letting the tenant's dagster-core reach the code server; add per-location egress here too. |

### Templates

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| templates | object | {} | Support resources rendered by the [templates subchart](https://github.com/KvalitetsIT/helm-templates-chart/tree/main/charts/templates): CiliumNetworkPolicy, SealedSecret, reflected Secret mirrors and generic resources. Plain NetworkPolicies live under `networkPolicies` above. |

## Deployment

This chart renders one Dagster code location (a single gRPC code server) as its own Helm release, deployed into its own project namespace, conventionally `<tenant>-dagster-<location>`. All chart resources are namespace-agnostic (they use `Release.Namespace`), so the deploy namespace is set by the ArgoCD `Application` resource in your environment repo.

The code location is unprivileged: the code server runs under the namespace `default` ServiceAccount with its token unmounted (no kube-config), and it makes no Kubernetes API calls. It serves definitions; the tenant core runs them.

### ArgoCD Application example (multi-source)

Each code location combines two ArgoCD sources: this chart, pinned to a git tag of this repo, and a values file from the tenant/environment repo. Using the [`argocd-apps`](https://github.com/argoproj/argo-helm/tree/main/charts/argocd-apps) chart:

```yaml
applications:
  my-location:
    namespace: tenant-a-dagster-my-location
    project: tenant-a-dagster-my-location
    sources:
      - repoURL: git@github.com:KvalitetsIT/kds-dagster-components.git
        targetRevision: <repo-tag>          # git tag from this repo
        path: dagster-code-location
        helm:
          releaseName: my-location
          valueFiles:
            - $values/dagster-my-location/code-location/values.yaml
            - $values/dagster-my-location/code-location/values-test.yaml
      - ref: values
        repoURL: git@github.com:my-org/tenant-a-apps.git
        targetRevision: main
    destination:
      server: https://kubernetes.default.svc
      namespace: tenant-a-dagster-my-location
```

## Cross-chart contract

This chart's Service is how the [`dagster-workspace-generator`](https://github.com/KvalitetsIT/kds-dagster-components/tree/main/dagster-workspace-generator) discovers code locations and groups them under the right tenant core. The Service and Deployment carry two labels:

- `dagster.io/code-location: "true"` - the generator's label selector for finding code-location Services cluster-wide.
- `dagster.io/location-name: <locationName>` - the workspace `location_name` the generator writes into the core's `dagster-workspace-yaml` ConfigMap. Defaults to the release name; override via `locationName` for dev/prod parity with the module folder name.

There is deliberately no core-namespace label: the generator derives the target core namespace from the Service's own namespace (its `tenant.kitkube.dk/name` label, or the namespace's first hyphen segment, mapped to `<tenant>-dagster-core`). The Service exposes a port named `grpc` on `4000`, the address the generator writes into the workspace entry (`host: <service>.<namespace>`, `port: 4000`) and the address the tenant core's webserver and daemon connect to.

## Environment variables

`env` is the location's app config (database and bucket connection env, credentials via `valueFrom.secretKeyRef`), applied to both the code server and the launched run pods. `extraEnvs` is appended after `env` so an overlay values file (e.g. `values-<env>.yaml`) can extend it without replacing it - Helm replaces list values across files rather than merging them, so a single `env` key across two files would lose the base entries. `envFrom` (extended by `extraEnvFrom`) carries whole-secret / ConfigMap sources as standard envFrom entries (`{secretRef}`/`{configMapRef}`); the chart applies them verbatim to the code server and extracts their names into the run pods' container context (`env_secrets`/`env_config_maps`). The chart appends `HOME=/tmp`, `TMPDIR=/tmp` and `PYTHONDONTWRITEBYTECODE=1` (the read-only root filesystem needs a writable `HOME`).

## Container context and run pods

The code server sets `DAGSTER_CLI_API_GRPC_CONTAINER_CONTEXT` on its own container: a JSON blob the tenant core's K8sRunLauncher deep-merges into every run pod it launches for this location. It carries only per-location deltas - routing (`namespace: <Release.Namespace>` so runs launch into this location's own namespace, the `default` ServiceAccount, image pull secrets) and payload (the location `env`, `env_secrets`, and `runPod.resources`). Optionally it carries `runPod.podSecurityContext` when the location image needs a different uid.

All run-pod hardening is the core runLauncher baseline, configured once per core and inherited by every location: the container securityContext (drop `ALL`, read-only root filesystem, no privilege escalation), the pod-level securityContext (`runAsNonRoot`/`runAsUser`/`runAsGroup`/`fsGroup`/seccomp Kyverno's Restricted PSS requires), `automountServiceAccountToken: false`, the writable `/tmp` emptyDir, the netbird sidecar label, `DAGSTER_HOME`, and `DAGSTER_PG_PASSWORD` (the metadata password). The Dagster instance is not mounted into run pods at all: the core daemon serializes the full instance into each run's `execute_run` args (`instance_ref`), so the run pod reads its storage config from there rather than from any `dagster.yaml`/ConfigMap in its own namespace.

## Run-pod resources

The core runLauncher's `resources` are a baseline shared by every location of a tenant. To size a single location's runs, set `runPod.resources`; the chart puts them in this location's container context, which Dagster deep-merges onto the launcher baseline and uses for the run container. This is per location and does not touch the shared core. The top-level `resources` value is separate and applies only to the code server (definition loading). Other per-location run-pod overrides live under the same `runPod` key (e.g. `runPod.podSecurityContext`).

## Network policies

NetworkPolicies live under `networkPolicies` and are rendered by this chart through the templates dependency's `templates.networkPolicy` renderer, invoked with this chart as the root - so template expressions in the values (for example the tenant) resolve against this chart's own helpers, not the subchart's. The chart ships `ingress-from-dagster-core`, letting the tenant's `dagster-core` (webserver and daemon) reach the code server on `4000` (tenant derived from the release namespace; disable with `networkPolicies.ingress-from-dagster-core.enabled: false`). The project baseline denies cross-namespace traffic, so add location-specific egress (to the tenant's app-data project, the metadata database in `data-dagster`, object storage) as further entries under `networkPolicies`; they merge with the built-in policy.

## Support resources (templates passthrough)

The `templates` value is passed to the [KvalitetsIT templates subchart](https://github.com/KvalitetsIT/helm-templates-chart/tree/main/charts/templates), which renders CiliumNetworkPolicy, SealedSecret, reflected Secret mirrors and generic resources from values. A common pattern is a `templates.resources` entry of `kind: Secret` carrying reflector's `reflector.v1.k8s.emberstack.com/reflects` annotation, which mirrors a credential from a shared data namespace into this location's namespace without duplicating the value.

### Minimal example

```yaml
# Minimal valid location: only the required knobs set. Renders the Deployment, Service and the default
# network policy; no databases, buckets, extra env, run-pod resource override, or templates-subchart
# resources. The target core namespace is derived from the release namespace at deploy time.
image:
  repository: ghcr.io/example/simple-location
  tag: "1.0.0"
module: simple_location.definitions
locationName: simple_location
```

### Full example

Exercises `env` (database and bucket connection config), an `extraEnvs` overlay, `envFrom`, a `runPod.resources` override, a `networkPolicies` egress rule, and a `templates` block (secret mirror, CiliumNetworkPolicy):

```yaml
# Full location shape: explicit env (database and bucket connection config with credentials via
# valueFrom secretKeyRef), an extraEnvs overlay entry, a run-pod resource override, and this location's
# support resources (secret mirror, network policies, object-storage egress) rendered via the templates
# subchart passthrough. Hardening, /tmp and netbird for run pods come from the tenant core, not here.
image:
  repository: ghcr.io/example/full-location
  tag: "1.1.0"
module: full_location.definitions
locationName: full_location

resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 512Mi

# run pods for this location need more headroom than the shared core baseline; deep-merged on top of it
runPod:
  resources:
    requests:
      cpu: "2"
      memory: 2Gi
    limits:
      cpu: "8"
      memory: 8Gi

env:
  - name: TARGET_FULL_LOCATION_HOST
    value: full-location-rw.svc.cluster.local
  - name: TARGET_FULL_LOCATION_PORT
    value: "5432"
  - name: TARGET_FULL_LOCATION_DBNAME
    value: full_location
  - name: TARGET_FULL_LOCATION_USER
    valueFrom:
      secretKeyRef:
        name: full-location-db
        key: username
  - name: TARGET_FULL_LOCATION_PASSWORD
    valueFrom:
      secretKeyRef:
        name: full-location-db
        key: password
  - name: FULL_LOCATION_S3_ENDPOINT
    value: https://s3.example.com
  - name: FULL_LOCATION_S3_BUCKET
    value: full-location
  - name: FULL_LOCATION_S3_ID
    valueFrom:
      secretKeyRef:
        name: full-location-s3-credentials
        key: access-key-id
  - name: FULL_LOCATION_S3_SECRET
    valueFrom:
      secretKeyRef:
        name: full-location-s3-credentials
        key: secret-access-key

# overlay-style extension (a values-<env>.yaml would set these without replacing env above)
extraEnvs:
  - name: ORACLE_HOST
    value: "oracle.example.com"
  - name: ORACLE_PASSWORD
    valueFrom:
      secretKeyRef:
        name: oracle-creds
        key: password

envFrom:
  - secretRef:
      name: ftps-creds

# extra code-server volume (the default /tmp entry is kept); demonstrates the kitapp-style volume shape
extraVolumes:
  - name: extra-config
    mountPath: /etc/extra
    readOnly: true
    volumeSpec:
      configMap:
        name: extra-config

# location-specific netpol, merged with the built-in ingress-from-dagster-core policy
networkPolicies:
  egress-to-app-data:
    podSelector: {}
    policyTypes:
      - Egress
    egress:
      - to:
          - namespaceSelector:
              matchLabels:
                tenant.kitkube.dk/name: data
                project.kitkube.dk/name: example

templates:
  resources:
    # Mirror this location's app-data DB credentials into the namespace (location-specific). The shared
    # Dagster metadata credentials come from the tenant projectDefaults, not here.
    full-location-db:
      apiVersion: v1
      kind: Secret
      metadata:
        annotations:
          reflector.v1.k8s.emberstack.com/reflects: "data-example/full-location-db"
      data: {}

  ciliumNetworkPolicies:
    object-storage:
      endpointSelector: {}
      egress:
        - toFQDNs:
            - matchPattern: "*.s3.example.com"
          toPorts:
            - ports:
                - port: "443"
                  protocol: TCP
```

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
