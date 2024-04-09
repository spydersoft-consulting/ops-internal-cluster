{{- define "sm.loki.name" -}}
{{- $default := ternary "enterprise-logs" "loki" .Values.loki.enterprise.enabled }}
{{- coalesce .Values.loki.nameOverride $default | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "sm.loki.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sm.loki.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Cluster label for rules and alerts.
*/}}
{{- define "sm.loki.clusterLabel" -}}
{{- $name := include "sm.loki.name" . }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}