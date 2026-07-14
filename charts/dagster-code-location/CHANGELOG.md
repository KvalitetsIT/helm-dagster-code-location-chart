# Changelog - dagster-code-location

All notable changes to the dagster-code-location chart are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

### Added
- Initial release. A single Dagster code location: a hardened gRPC code server (Deployment + Service) deployed as its own release into a per-project namespace. Carries the discovery labels the KDS workspace generator groups locations by, and the `DAGSTER_CLI_API_GRPC_CONTAINER_CONTEXT` the tenant core's K8sRunLauncher uses to launch this location's run pods.
- `env` / `extraEnvs`, `envFrom` / `extraEnvFrom` and `volumes` / `extraVolumes`: base plus overlay lists so a `values-<env>.yaml` extends rather than replaces the base.
- `runPod.resources` / `runPod.podSecurityContext`: per-location run-pod overrides, deep-merged onto the core runLauncher baseline.
- `networkPolicies`: rendered by this chart through the `templates` dependency's renderer (so template expressions resolve against this chart's helpers); ships the ingress policy letting the tenant's dagster-core reach the code server on 4000.
- `templates`: passthrough to the `templates` subchart for CiliumNetworkPolicy, SealedSecret, reflected Secret mirrors and generic resources.
