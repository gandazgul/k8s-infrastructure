{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "helpers.name" -}}
    {{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "helpers.fullname" -}}
    {{- if .Values.fullnameOverride -}}
        {{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
    {{- else -}}
        {{- $name := default .Chart.Name .Values.nameOverride -}}
        {{- if contains $name .Release.Name -}}
            {{- .Release.Name | trunc 63 | trimSuffix "-" -}}
        {{- else -}}
            {{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
        {{- end -}}
    {{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "helpers.chart" -}}
    {{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "helpers.transmission-ingress" -}}
    {{- printf "%s-%s" .Release.Name "transmission-ingress" | trunc 63 -}}
{{- end -}}

{{- define "helpers.flexget-ingress" -}}
    {{- printf "%s-%s" .Release.Name "flexget-ingress" | trunc 63 -}}
{{- end -}}

{{- define "helpers.peer-port-service" -}}
    {{- printf "%s-%s" .Release.Name "peer-service" | trunc 63 -}}
{{- end -}}

{{- define "helpers.flexget-service" -}}
    {{- printf "%s-%s" .Release.Name "flexget-service" | trunc 63 -}}
{{- end -}}

{{- define "helpers.transmission-service" -}}
    {{- printf "%s-%s" .Release.Name "transmission-service" | trunc 63 -}}
{{- end -}}
