{{/* k8s resource name == release name (DNS-1123, hyphenated) */}}
{{- define "dagster-code-location.name" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* tenant name derived from the release namespace <tenant>-dagster-<location> (first hyphen segment) */}}
{{- define "dagster-code-location.tenant" -}}
{{- splitList "-" .Release.Namespace | first -}}
{{- end -}}

{{/* dagster location_name: explicit override (for dev/prod parity) else the release name */}}
{{- define "dagster-code-location.locationName" -}}
{{- .Values.locationName | default (include "dagster-code-location.name" .) -}}
{{- end -}}

{{/* full image ref. digest wins when set (repository:tag@digest if both given), else tag; one is required. */}}
{{- define "dagster-code-location.image" -}}
{{- $repo := required "image.repository is required" .Values.image.repository -}}
{{- if .Values.image.digest -}}
{{- if .Values.image.tag -}}
{{- printf "%s:%s@%s" $repo .Values.image.tag .Values.image.digest -}}
{{- else -}}
{{- printf "%s@%s" $repo .Values.image.digest -}}
{{- end -}}
{{- else -}}
{{- printf "%s:%s" $repo (required "image.tag or image.digest is required" .Values.image.tag) -}}
{{- end -}}
{{- end -}}

{{/* -m target: defaults to <release name underscored>.definitions */}}
{{- define "dagster-code-location.module" -}}
{{- .Values.module | default (printf "%s.definitions" (.Release.Name | replace "-" "_")) -}}
{{- end -}}

{{- define "dagster-code-location.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dagster-code-location.name" . }}
app.kubernetes.io/instance: {{ .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{- define "dagster-code-location.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "dagster-code-location.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | default .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: dagster
{{- end -}}

{{/* labels the workspace generator discovers this location by. The generator derives the target core
     namespace from the Service's own namespace (its tenant label -> <tenant>-dagster-core), so no
     core-namespace label is needed here. */}}
{{- define "dagster-code-location.discoveryLabels" -}}
dagster.io/code-location: "true"
dagster.io/location-name: {{ include "dagster-code-location.locationName" . }}
{{- end -}}

{{/* Env for the code server and the run pods: env + extraEnvs (overlay-extend), plus HOME/TMPDIR/
     PYTHONDONTWRITEBYTECODE (the read-only root fs needs a writable HOME) added only when the user has
     not set them, so they stay overridable. DAGSTER_HOME, DAGSTER_PG_PASSWORD and the instance are not
     set here - the Deployment sets them for the code server, run pods get them from the core. */}}
{{- define "dagster-code-location.env" -}}
{{- $env := concat (.Values.env | default list) (.Values.extraEnvs | default list) -}}
{{- $set := dict -}}
{{- range $env -}}{{- $_ := set $set .name true -}}{{- end -}}
{{- if not (hasKey $set "HOME") -}}{{- $env = append $env (dict "name" "HOME" "value" "/tmp") -}}{{- end -}}
{{- if not (hasKey $set "TMPDIR") -}}{{- $env = append $env (dict "name" "TMPDIR" "value" "/tmp") -}}{{- end -}}
{{- if not (hasKey $set "PYTHONDONTWRITEBYTECODE") -}}{{- $env = append $env (dict "name" "PYTHONDONTWRITEBYTECODE" "value" "1") -}}{{- end -}}
{{- toYaml $env -}}
{{- end -}}

{{/* combined envFrom sources: envFrom plus extraEnvFrom (overlay-extend). Standard k8s envFrom entries
     ({secretRef}/{configMapRef}), used as-is on the code server. */}}
{{- define "dagster-code-location.envFrom" -}}
{{- concat (.Values.envFrom | default list) (.Values.extraEnvFrom | default list) | toYaml -}}
{{- end -}}

{{/* Structured volumes: one entry ({name, mountPath, readOnly?, subPath?, volumeSpec})
     renders both a container volumeMount and a pod volume. */}}
{{- define "dagster-code-location.volumeMount" -}}
- name: {{ .name }}
  mountPath: {{ .mountPath }}
  {{- if .readOnly }}
  readOnly: true
  {{- end }}
  {{- if .subPath }}
  subPath: {{ .subPath }}
  {{- end }}
{{- end -}}

{{- define "dagster-code-location.podVolume" -}}
- name: {{ .name }}
  {{- toYaml .volumeSpec | nindent 2 }}
{{- end -}}

{{/* DAGSTER_CLI_API_GRPC_CONTAINER_CONTEXT: the per-location deltas the core's K8sRunLauncher deep-merges
     into this location's run pods. Routing (namespace -> runs launch here, service account, pull secrets)
     and payload (env, env_secrets/env_config_maps, runPod.resources, runPod.podSecurityContext). All
     run-pod hardening (container/pod securityContext, /tmp, sidecars, automountServiceAccountToken) is the
     core baseline; the code location only overrides what differs. */}}
{{- define "dagster-code-location.containerContext" -}}
{{- $env := include "dagster-code-location.env" . | fromYamlArray -}}
{{- $envFrom := include "dagster-code-location.envFrom" . | fromYamlArray -}}
{{- $envSecrets := list -}}
{{- $envConfigMaps := list -}}
{{- range $envFrom -}}
{{- with .secretRef -}}{{- $envSecrets = append $envSecrets .name -}}{{- end -}}
{{- with .configMapRef -}}{{- $envConfigMaps = append $envConfigMaps .name -}}{{- end -}}
{{- end -}}
{{- $pullSecrets := list -}}
{{- range .Values.imagePullSecrets -}}{{- $pullSecrets = append $pullSecrets (dict "name" .) -}}{{- end -}}
{{- $k8s := dict
    "image_pull_secrets" $pullSecrets
    "service_account_name" .Values.serviceAccountName
    "namespace" .Release.Namespace
    "env" $env -}}
{{- with $envSecrets -}}{{- $_ := set $k8s "env_secrets" . -}}{{- end -}}
{{- with $envConfigMaps -}}{{- $_ := set $k8s "env_config_maps" . -}}{{- end -}}
{{- with .Values.runPod.resources -}}{{- $_ := set $k8s "resources" . -}}{{- end -}}
{{- with .Values.runPod.podSecurityContext -}}{{- $_ := set $k8s "run_k8s_config" (dict "pod_spec_config" (dict "security_context" .)) -}}{{- end -}}
{{- dict "k8s" $k8s | toJson -}}
{{- end -}}
