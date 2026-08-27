# Changelog - dagster-code-location

All notable changes to the dagster-code-location chart are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [0.0.4] - 2026-08-27
- Rename referenced repo to kds-components
- Add revisionHistoryLimit to 2
- CI: `ct install` now brings the `ci/` examples up for real. They run the public `dagster/user-code-example` image with a throwaway definitions package mounted from a ConfigMap, and the lint-test workflow stubs the secrets and config the platform normally reflects into the namespace. `ct.yaml` no longer skips clean-up, so each example is uninstalled before the next one installs. Examples and CI only; no template or values schema changes.

## [0.0.3] - 2026-07-15

### Changed
- Cleaned up chart comments, the README and the `ci/` example values to be generic. Documentation and examples only; no template behavior or values schema changes.

## [0.0.2] - 2026-07-14

### Changed
- `image`: removed `image.registry` and the auto-derived `<registry>/<release-name>` repository. Set `image.repository` explicitly instead (it was already the primary field). Consumers using `image.registry` must switch to `image.repository`.
- `command`: replaced the `command: api-grpc | code-server` mode enum with a native, templated `args` list (defaults to `dagster api grpc` on 4000 serving `module`). Override `args` with the full arg list for a different entrypoint, e.g. `dagster code-server start ...`. Consumers setting `command` must move to `args`.

### Fixed
- `app.kubernetes.io/instance` label is now truncated to 63 characters (like the name label), so a long release name cannot produce an invalid label value.
- `HOME`, `TMPDIR` and `PYTHONDONTWRITEBYTECODE` are now added only when not already present in `env`/`extraEnvs`, so they can be overridden instead of being silently forced.

## [0.0.1] - 2026-07-14

### Added
- Initial release. A single Dagster code location: a hardened gRPC code server (Deployment + Service) deployed as its own release into a per-project namespace. Carries the discovery labels the KDS workspace generator groups locations by, and the `DAGSTER_CLI_API_GRPC_CONTAINER_CONTEXT` the tenant core's K8sRunLauncher uses to launch this location's run pods.
- `env` / `extraEnvs`, `envFrom` / `extraEnvFrom` and `volumes` / `extraVolumes`: base plus overlay lists so a `values-<env>.yaml` extends rather than replaces the base.
- `runPod.resources` / `runPod.podSecurityContext`: per-location run-pod overrides, deep-merged onto the core runLauncher baseline.
- `networkPolicies`: rendered by this chart through the `templates` dependency's renderer (so template expressions resolve against this chart's helpers); ships the ingress policy letting the tenant's dagster-core reach the code server on 4000.
- `templates`: passthrough to the `templates` subchart for CiliumNetworkPolicy, SealedSecret, reflected Secret mirrors and generic resources.
