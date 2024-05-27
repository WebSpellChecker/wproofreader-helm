{{/*
Expand the name of the chart.
*/}}
{{- define "wproofreader.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "wproofreader.fullname" -}}
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

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "wproofreader.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Generate common labels.
*/}}
{{- define "wproofreader.labels" -}}
helm.sh/chart: {{ include "wproofreader.chart" . }}
{{ include "wproofreader.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Generate selector labels.
*/}}
{{- define "wproofreader.selectorLabels" -}}
app.kubernetes.io/name: {{ include "wproofreader.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use.
*/}}
{{- define "wproofreader.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "wproofreader.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the PersistentVolumeClaim.
*/}}
{{- define "wproofreader.pvcName" -}}
{{- if and .Values.dictionaries.enabled (not .Values.dictionaries.existingClaim) }}
{{- default (include "wproofreader.fullname" .) }}-dict
{{- end }}
{{- end }}

{{/*
Prints key-value pairs encoded in base 64.
*/}}
{{- define "wproofreader.printKeyValue" -}}
    {{- range $k, $v := . }}
{{ $k }}: {{ $v | b64enc | quote }}
    {{- end -}}
{{- end }}

{{/*
Insert key/cert pair from file.
*/}}
{{- define "wproofreader.readCert" -}}
{{- $cert := .Files.Get .Values.certFile -}}
{{- $cert_path := (regexSplit "[/\\\\]" .Values.certFile -1) }}
{{- $key := .Files.Get (required "path to certificate key file is missing (keyFile)" .Values.keyFile) -}}
{{- $key_path := (regexSplit "[/\\\\]" .Values.keyFile -1) }}
{{- template "wproofreader.printKeyValue" (dict (last $cert_path) $cert (last $key_path) $key) }}
{{- end }}

{{/*
Returns default web port as an integer.
*/}}
{{- define "wproofreader.servicePort" -}}
{{ .Values.service.port | default (include "wproofreader.defaultWebPort" .) }}
{{- end }}

{{/*
Returns default web port as an integer.
*/}}
{{- define "wproofreader.defaultWebPort" -}}
{{- if .Values.useHTTPS -}}
{{- print 443 }}
{{- else -}}
{{- print 80 }}
{{- end }}
{{- end }}

{{/*
Returns default web port as an integer.
*/}}
{{- define "wproofreader.containerPort" -}}
{{- if .Values.useHTTPS -}}
{{- print 8443 }}
{{- else -}}
{{- print 8080 }}
{{- end }}
{{- end }}
