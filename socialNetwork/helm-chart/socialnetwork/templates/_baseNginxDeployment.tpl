{{- define "socialnetwork.templates.baseNginxDeployment" }}
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    service: {{ .Values.name }}
  name: {{ .Values.name }}
spec: 
  replicas: {{ .Values.replicas | default .Values.global.replicas }}
  selector:
    matchLabels:
      service: {{ .Values.name }}
  template:
    metadata:
      labels:
        service: {{ .Values.name }}
        app: {{ .Values.name }}
      {{- if $.Values.global.prometheus.enabled }}
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/path: {{ $.Values.global.prometheus.path | quote }}
        prometheus.io/port: "9091"
        prometheus.io/scheme: {{ $.Values.global.prometheus.scheme | default "http" | quote }}
        {{- if $.Values.global.prometheus.interval }}
        prometheus.io/interval: {{ $.Values.global.prometheus.interval | quote }}
        {{- end }}
      {{- end }}
    spec: 
      containers:
      {{- with .Values.container }}
      - name: "{{ .name }}"
        image: {{ .dockerRegistry | default $.Values.global.dockerRegistry }}/{{ .image }}:{{ .imageVersion | default $.Values.global.defaultImageVersion }}
        imagePullPolicy: {{ .imagePullPolicy | default $.Values.global.imagePullPolicy }}
        ports:
        {{- range $cport := .ports }}
        - containerPort: {{ $cport.containerPort -}}
        {{ end }} 
        {{- if .env }}
        env:
        {{- range $e := .env}}
        - name: {{ $e.name }}
          value: "{{ (tpl ($e.value | toString) $) }}"
        {{ end -}}
        {{ end -}}
        {{- if .command}}
        command: 
        - {{ .command }}
        {{- end -}}
        {{- if .args}}
        args:
        {{- range $arg := .args}}
        - {{ $arg }}
        {{- end -}}
        {{- end }}
        {{- if .resources }}  
        resources:
          {{ toYaml .resources | nindent 10 | trim }}
        {{- else if hasKey $.Values.global "resources" }}           
        resources:
          {{ toYaml $.Values.global.resources | nindent 10 | trim }}
        {{- end }}  
        {{- if $.Values.configMaps }}        
        volumeMounts: 
        {{- range $configMap := $.Values.configMaps }}
        - name: {{ $.Values.name }}-config
          mountPath: {{ $configMap.mountPath }}
          subPath: {{ $configMap.name }}        
        {{- end }}
        {{- range .volumeMounts }}
        - name: {{ .name }}
          mountPath: {{ .mountPath }}
        {{- end }}
        {{- end }}
      {{- end }}
      {{- if $.Values.global.prometheus.enabled }}
      # Nginx Prometheus Exporter sidecar
      # Scrapes nginx stub_status and exposes as Prometheus metrics on port 9091
      - name: nginx-prometheus-exporter
        image: nginx/nginx-prometheus-exporter:1.1.0
        args:
          - "-nginx.scrape-uri=http://localhost:8080/nginx_status"
          - "-web.listen-address=:9091"
          - "-web.telemetry-path=/metrics"
        ports:
        - containerPort: 9091
          name: metrics
          protocol: TCP
        resources:
          requests:
            cpu: 10m
            memory: 32Mi
          limits:
            cpu: 50m
            memory: 64Mi
        livenessProbe:
          httpGet:
            path: /metrics
            port: 9091
          initialDelaySeconds: 10
          periodSeconds: 15
        readinessProbe:
          httpGet:
            path: /metrics
            port: 9091
          initialDelaySeconds: 5
          periodSeconds: 10
      {{- end }}

      initContainers:
      {{- with .Values.initContainer }}
      - name: "{{ .name }}"
        image: {{ .dockerRegistry | default $.Values.global.dockerRegistry }}/{{ .image }}:{{ .imageVersion | default $.Values.global.defaultImageVersion }}
        imagePullPolicy: {{ .imagePullPolicy | default $.Values.global.imagePullPolicy }}
        {{- if .command}}
        command: 
        - {{ .command }}
        {{- end -}}
        {{- if .resources }}
        resources:
          {{ toYaml .resources | nindent 10 | trim }}
        {{- else if hasKey $.Values.global "resources" }}
        resources:
          {{ toYaml $.Values.global.resources | nindent 10 | trim }}
        {{- end }}
        {{- if .env }}
        env:
        {{- range $e := .env}}
        - name: {{ $e.name }}
          value: "{{ (tpl ($e.value | toString) $) }}"
        {{ end -}}
        {{ end -}}
        {{- if .args}}
        args:
        {{- range $arg := .args}}
        - {{ $arg }}
        {{- end -}}
        {{- end }}
        {{- if .volumeMounts }}        
        volumeMounts: 
        {{- range .volumeMounts }}
        - name: {{ .name }}
          mountPath: {{ .mountPath }}
        {{- end }}
        {{- end }}
      {{- end -}}

      {{- if or $.Values.configMaps $.Values.global.prometheus.enabled }}
      volumes:
      {{- if $.Values.configMaps }}
      - name: {{ $.Values.name }}-config
        configMap:
          name: {{ $.Values.name }}
      {{- range $.Values.volumes }}
      - name: {{ .name }}
        emptyDir: {}
      {{- end }}
      {{- end }}
      {{- if $.Values.global.prometheus.enabled }}
      - name: metrics-script
        configMap:
          name: metrics-exporter-script
          defaultMode: 0755
      {{- end }}
      {{- end }}
      
      {{- if hasKey .Values "topologySpreadConstraints" }}
      topologySpreadConstraints:
        {{ tpl .Values.topologySpreadConstraints . | nindent 6 | trim }}
      {{- else if hasKey $.Values.global  "topologySpreadConstraints" }}
      topologySpreadConstraints:
        {{ tpl $.Values.global.topologySpreadConstraints . | nindent 6 | trim }}
      {{- end }}
      hostname: {{ $.Values.name }}
      restartPolicy: {{ .Values.restartPolicy | default .Values.global.restartPolicy}}

{{ include "socialnetwork.templates.baseHPA" . }}
{{- end}}
