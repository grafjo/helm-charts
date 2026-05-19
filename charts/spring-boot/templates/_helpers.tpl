{{/*
Expand the name of the chart.
*/}}
{{- define "spring-boot.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
Truncated at 63 chars per DNS naming spec. If release name contains chart name,
it's used as the full name.
*/}}
{{- define "spring-boot.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "spring-boot.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "spring-boot.labels" -}}
helm.sh/chart: {{ include "spring-boot.chart" . }}
{{ include "spring-boot.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "spring-boot.selectorLabels" -}}
app.kubernetes.io/name: {{ include "spring-boot.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "spring-boot.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "spring-boot.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Port name where Spring Boot Actuator endpoints are served.
When the management server is broken out onto a separate port, that's
"http-management"; otherwise it shares the application port "http".
*/}}
{{- define "spring-boot.actuatorPortName" -}}
{{- if .Values.customizedManagementServer.enabled -}}
http-management
{{- else -}}
http
{{- end -}}
{{- end }}

{{/*
Render a probe definition with the actuator port resolved.

For probes with httpGet:
  - if port is unset or equals "http", it's set to the actuator port
    ("http-management" when customizedManagementServer.enabled, otherwise "http")
  - any other explicit port (numeric, or "http-management" already set by the
    user) is left untouched
Non-httpGet probes (exec/tcpSocket/grpc) are returned unchanged.

Usage:
  {{- with .Values.livenessProbe }}
  livenessProbe:
    {{- include "spring-boot.renderProbe" (dict "probe" . "ctx" $) | nindent 12 }}
  {{- end }}
*/}}
{{- define "spring-boot.renderProbe" -}}
{{- $probe := deepCopy .probe -}}
{{- if hasKey $probe "httpGet" -}}
{{- $httpGet := index $probe "httpGet" -}}
{{- $port := toString (default "" (index $httpGet "port")) -}}
{{- if or (eq $port "") (eq $port "http") -}}
{{- if .ctx.Values.customizedManagementServer.enabled -}}
{{- $_ := set $httpGet "port" "http-management" -}}
{{- else -}}
{{- $_ := set $httpGet "port" "http" -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- toYaml $probe -}}
{{- end }}

{{/*
Helm 4 capability guard. Chart.yaml has no schema field for minimum Helm
version, so check at render time and fail loud on Helm 3.x.

Bypassed when .Values.skipHelmVersionCheck is true (test harness only —
helm-unittest 1.x embeds a Helm 3 engine and cannot override .Capabilities.HelmVersion).
*/}}
{{- define "spring-boot.assertHelm4" -}}
{{- if not .Values.skipHelmVersionCheck -}}
{{- if not (semverCompare ">=4.0.0-0" .Capabilities.HelmVersion.Version) -}}
{{- fail (printf "spring-boot chart v2 requires Helm 4 or newer (detected: %s)" .Capabilities.HelmVersion.Version) -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Validate a single .Values.env entry. The entry must be a scalar or a map
with exactly one of: value, secretKeyRef, configMapKeyRef, fieldRef,
resourceFieldRef. Refs additionally require their required sub-fields.

Usage: {{- include "spring-boot.validateEnvEntry" (dict "key" $key "val" $val) -}}
*/}}
{{- define "spring-boot.validateEnvEntry" -}}
{{- $key := .key -}}
{{- $val := .val -}}
{{- if kindIs "invalid" $val -}}
{{- fail (printf "env entry %q must not be null" $key) -}}
{{- end -}}
{{- if kindIs "map" $val -}}
{{- $keys := list "value" "secretKeyRef" "configMapKeyRef" "fieldRef" "resourceFieldRef" -}}
{{- $present := list -}}
{{- range $k := $keys -}}
{{- if hasKey $val $k -}}
{{- $present = append $present $k -}}
{{- end -}}
{{- end -}}
{{- if ne (len $present) 1 -}}
{{- fail (printf "env entry %q must have exactly one of: value, secretKeyRef, configMapKeyRef, fieldRef, resourceFieldRef (got: %v)" $key $present) -}}
{{- end -}}
{{- if hasKey $val "secretKeyRef" -}}
{{- $ref := index $val "secretKeyRef" -}}
{{- if or (not (hasKey $ref "name")) (not (hasKey $ref "key")) -}}
{{- fail (printf "env entry %q secretKeyRef requires both 'name' and 'key'" $key) -}}
{{- end -}}
{{- end -}}
{{- if hasKey $val "configMapKeyRef" -}}
{{- $ref := index $val "configMapKeyRef" -}}
{{- if or (not (hasKey $ref "name")) (not (hasKey $ref "key")) -}}
{{- fail (printf "env entry %q configMapKeyRef requires both 'name' and 'key'" $key) -}}
{{- end -}}
{{- end -}}
{{- if hasKey $val "fieldRef" -}}
{{- $ref := index $val "fieldRef" -}}
{{- if not (hasKey $ref "fieldPath") -}}
{{- fail (printf "env entry %q fieldRef requires 'fieldPath'" $key) -}}
{{- end -}}
{{- end -}}
{{- if hasKey $val "resourceFieldRef" -}}
{{- $ref := index $val "resourceFieldRef" -}}
{{- if not (hasKey $ref "resource") -}}
{{- fail (printf "env entry %q resourceFieldRef requires 'resource'" $key) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Render the container env list for the Spring Boot app.
- Chart-managed MANAGEMENT_SERVER_* entries first (when customizedManagementServer is enabled).
- Then user-supplied .Values.env, sorted alphabetically by key.
  - Scalars (string/int/bool/float) → { value: "<stringified>" }, tpl-rendered.
  - Maps → validated, then emitted with the user's value/valueFrom shape verbatim.

Emits nothing when there are no entries at all (so the container's env: key stays absent).
*/}}
{{- define "spring-boot.env" -}}
{{- $entries := list -}}
{{- $userEnv := .Values.env | default dict -}}
{{- if not (hasKey $userEnv "SERVER_PORT") -}}
{{- $entries = append $entries (dict "name" "SERVER_PORT" "value" (toString .Values.image.containerPort)) -}}
{{- end -}}
{{- if not (hasKey $userEnv "SERVER_SHUTDOWN") -}}
{{- $entries = append $entries (dict "name" "SERVER_SHUTDOWN" "value" (toString .Values.gracefulShutdown.mode)) -}}
{{- end -}}
{{- if not (hasKey $userEnv "SPRING_LIFECYCLE_TIMEOUT_PER_SHUTDOWN_PHASE") -}}
{{- $entries = append $entries (dict "name" "SPRING_LIFECYCLE_TIMEOUT_PER_SHUTDOWN_PHASE" "value" (toString .Values.gracefulShutdown.timeout)) -}}
{{- end -}}
{{- if .Values.customizedManagementServer.enabled -}}
{{- if not (hasKey $userEnv "MANAGEMENT_SERVER_PORT") -}}
{{- $entries = append $entries (dict "name" "MANAGEMENT_SERVER_PORT" "value" (toString .Values.customizedManagementServer.port)) -}}
{{- end -}}
{{- if not (hasKey $userEnv "MANAGEMENT_SERVER_ADDRESS") -}}
{{- $entries = append $entries (dict "name" "MANAGEMENT_SERVER_ADDRESS" "value" (toString .Values.customizedManagementServer.address)) -}}
{{- end -}}
{{- end -}}
{{- range $key := (.Values.env | default dict | keys | sortAlpha) -}}
{{- $val := index $.Values.env $key -}}
{{- include "spring-boot.validateEnvEntry" (dict "key" $key "val" $val) -}}
{{- if kindIs "map" $val -}}
{{- if hasKey $val "value" -}}
{{- $entries = append $entries (dict "name" $key "value" (tpl (toString (index $val "value")) $ )) -}}
{{- else -}}
{{- $valueFrom := dict -}}
{{- range $k, $v := $val -}}
{{- $_ := set $valueFrom $k $v -}}
{{- end -}}
{{- $entries = append $entries (dict "name" $key "valueFrom" $valueFrom) -}}
{{- end -}}
{{- else -}}
{{- $entries = append $entries (dict "name" $key "value" (tpl (toString $val) $)) -}}
{{- end -}}
{{- end -}}
{{- if $entries -}}
{{- range $e := $entries }}
- name: {{ $e.name }}
{{- if hasKey $e "value" }}
  value: {{ $e.value | quote }}
{{- else }}
  valueFrom:
{{ toYaml $e.valueFrom | indent 4 }}
{{- end }}
{{- end -}}
{{- end -}}
{{- end }}
