{{/*
Nombre completo de los recursos: <release>-todo-app
(si el nombre del release ya contiene "todo-app", se usa tal cual)
*/}}
{{- define "todo-app.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Tag de la imagen: el de values o, si está vacío, el appVersion del Chart.yaml
*/}}
{{- define "todo-app.imageTag" -}}
{{- .Values.image.tag | default .Chart.AppVersion -}}
{{- end -}}

{{/*
Labels comunes a todos los recursos
*/}}
{{- define "todo-app.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{ include "todo-app.selectorLabels" . }}
app.kubernetes.io/version: {{ include "todo-app.imageTag" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Labels que usa el Service y el Deployment para encontrar los pods
*/}}
{{- define "todo-app.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
