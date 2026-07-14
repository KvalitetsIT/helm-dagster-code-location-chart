# helm-dagster-code-location-chart

Helm chart for a single Dagster code location on Kubernetes: a hardened gRPC code server delivered as its own release into a per-project namespace, alongside a tenant Dagster core (see [kds-dagster-components](https://github.com/KvalitetsIT/kds-dagster-components)).

## Charts

| Chart | Description |
|-------|-------------|
| [dagster-code-location](charts/dagster-code-location/) | A hardened gRPC code server (Deployment + Service) with the discovery labels the KDS workspace generator groups locations by, and the container context the tenant core's K8sRunLauncher uses to launch this location's run pods |

## Overview

One release of this chart is one code location. It renders:

- a **Deployment** running the code server (`dagster api grpc` or `dagster code-server start`) with a read-only root filesystem, non-root uid, dropped capabilities and a writable `/tmp`;
- a **Service** on port 4000 carrying the discovery labels (`dagster.io/code-location`, `dagster.io/location-name`) the workspace generator uses;
- a **NetworkPolicy** letting the tenant's dagster-core webserver and daemon reach the code server;
- optional **support resources** (CiliumNetworkPolicy, SealedSecret, reflected Secret mirrors) via the `templates` subchart.

Run pods are launched by the tenant core's K8sRunLauncher into this location's namespace, sized and hardened by the core baseline; per-location deltas go under `runPod`. See the [chart README](charts/dagster-code-location/README.md) for the full values reference.

## Development

### Prerequisites

- Docker (for `make docs` and `make lint`)
- Helm 3 (for manual dependency management)

### Generate docs

Regenerate the chart `README.md` from its `README.md.gotmpl` template:

```bash
make docs
```

### Lint

Run chart-testing lint:

```bash
make lint
```

Run both docs and lint:

```bash
make
```

## Releasing

The chart is released by pushing a `v<version>` tag:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

The [release workflow](.github/workflows/release.yaml) then automatically:

1. Detects the version from the tag
2. Packages the chart (with `helm dependency update`)
3. Publishes it to [KvalitetsIT/helm-repo](https://github.com/KvalitetsIT/helm-repo)
4. Creates a GitHub Release with the matching `CHANGELOG.md` section

## CI

Pull requests are validated by the [PR workflow](.github/workflows/pr.yaml):

- Requires `charts/dagster-code-location/CHANGELOG.md` to be updated
- Checks the chart README is regenerated (`make docs`)
- Lints the chart with `ct lint` and installs it into a KinD cluster with `ct install` (the Cilium CRD is installed first)
