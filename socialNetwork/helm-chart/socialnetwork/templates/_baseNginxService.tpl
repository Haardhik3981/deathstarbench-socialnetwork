{{- define "socialnetwork.templates.baseNginxService" }}

apiVersion: v1
kind: Service
metadata:
  name: {{ .Values.name }}
  labels:
    service: {{ .Values.name }}
  {{- if .Values.global.prometheus.enabled }}
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/path: "/metrics"
    prometheus.io/port: "9091"
    prometheus.io/scheme: "http"
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
  # Metrics port for nginx-prometheus-exporter sidecar
  - name: metrics
    port: 9091
    targetPort: 9091
    protocol: TCP
  {{- end }}
  selector:
    service: {{ .Values.name }}

{{- end }}

