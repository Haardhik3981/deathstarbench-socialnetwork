{{- define "socialnetwork.templates.baseService" }}

apiVersion: v1
kind: Service
metadata:
  name: {{ .Values.name }}
  labels:
    service: {{ .Values.name }}
  {{- if .Values.global.prometheus.enabled }}
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/path: {{ .Values.global.prometheus.path | quote }}
    prometheus.io/port: {{ .Values.global.prometheus.port | quote }}
    prometheus.io/scheme: {{ .Values.global.prometheus.scheme | default "http" | quote }}
    {{- if .Values.global.prometheus.interval }}
    prometheus.io/interval: {{ .Values.global.prometheus.interval | quote }}
    {{- end }}
  {{- end }}
spec:
  type: {{ .Values.type | default .Values.global.serviceType }}
  ports:
  {{- range .Values.ports }}
  - name: "{{ .port }}"
    port: {{ .port }}
    targetPort: {{ .targetPort }}
    {{- if .protocol }}
    protocol: {{ .protocol }}
    {{- end }}
  {{- end }}
  {{- if .Values.global.prometheus.enabled }}
  # Metrics port for Prometheus sidecar exporter
  - name: metrics
    port: 9091
    targetPort: 9091
    protocol: TCP
  {{- end }}
  selector:
    service: {{ .Values.name }}

{{- if and .Values.global.prometheus.enabled .Values.global.prometheus.serviceMonitor.enabled }}
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ .Values.name }}
  labels:
    service: {{ .Values.name }}
    {{- range $key, $value := .Values.global.prometheus.serviceMonitor.labels }}
    {{ $key }}: {{ $value | quote }}
    {{- end }}
spec:
  namespaceSelector:
    matchNames:
      - {{ .Release.Namespace }}
  selector:
    matchLabels:
      service: {{ .Values.name }}
  endpoints:
    - interval: {{ .Values.global.prometheus.interval | quote }}
      path: {{ .Values.global.prometheus.path | quote }}
      port: {{ .Values.global.prometheus.port | quote }}
      scheme: {{ .Values.global.prometheus.scheme | default "http" | quote }}
      {{- if .Values.global.prometheus.serviceMonitor.scrapeTimeout }}
      scrapeTimeout: {{ .Values.global.prometheus.serviceMonitor.scrapeTimeout | quote }}
      {{- end }}
      {{- if .Values.global.prometheus.serviceMonitor.honorLabels }}
      honorLabels: true
      {{- end }}
      {{- with .Values.global.prometheus.serviceMonitor.metricRelabelings }}
      metricRelabelings:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.global.prometheus.serviceMonitor.relabelings }}
      relabelings:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end }}

{{- end }}