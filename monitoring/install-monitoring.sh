# =============================================================================
# MONITORING — Prometheus + Grafana con Helm
# =============================================================================
# Este archivo documenta los comandos exactos para instalar el stack completo.
# No es un manifiesto YAML ejecutable directamente con kubectl.
# =============================================================================

# 1. Agregar el repo de Helm de Prometheus Community
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 2. Crear namespace para monitoring
kubectl create namespace monitoring

# 3. Instalar kube-prometheus-stack (incluye Prometheus + Grafana + Alertmanager)
helm upgrade kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.adminPassword="admin123!" \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort=32000 \
  --set prometheus.service.type=NodePort \
  --set prometheus.service.nodePort=32001 \
  --set alertmanager.service.type=NodePort \
  --set alertmanager.service.nodePort=32002 \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set nodeExporter.enabled=false

# 4. Verificar que todo está corriendo
kubectl get pods -n monitoring

# 5. Acceder a Grafana (en local con Docker Desktop)
#    Obtener la IP/puerto del service de Grafana:
kubectl get svc -n monitoring kube-prometheus-stack-grafana

#    Si usas minikube:
minikube service kube-prometheus-stack-grafana -n monitoring

# 6. Credenciales de Grafana por defecto:
#    Usuario: admin
#    Password: admin123! (la que pusiste en el paso 3)

# =============================================================================
# LOKI — Logs centralizados (Semana 4)
# =============================================================================

# Agregar repo de Grafana
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Instalar Loki stack 
helm install loki grafana/loki `
  --namespace monitoring `
  --set loki.auth_enabled=false `
  --set deploymentMode=SingleBinary `
  --set singleBinary.replicas=1 `
  --set loki.commonConfig.replication_factor=1 `
  --set loki.storage.type=filesystem `
  --set loki.useTestSchema=true `
  --set minio.enabled=false `
  --set backend.replicas=0 `
  --set read.replicas=0 `
  --set write.replicas=0

# Promtail recolecta automáticamente los logs de todos tus pods
# y los envía a Loki. Luego los ves en Grafana con la fuente "Loki".
helm install promtail grafana/promtail `
  --namespace monitoring `
  --set config.clients[0].url=http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push

# =============================================================================
# MÉTRICAS DE TU API ASP.NET Core
# =============================================================================
# Agrega este paquete NuGet a tu proyecto para exponer /metrics:
#
#   dotnet add package prometheus-net.AspNetCore
#
# Y en Program.cs agrega ANTES de app.Run():
#
#   using Prometheus;
#   app.UseMetricServer();   // expone /metrics
#   app.UseHttpMetrics();    // métricas HTTP automáticas
#
# Luego reconstruye tu imagen Docker y Prometheus las recolectará
# automáticamente gracias a las anotaciones en deployment.yaml

# Con kubectl top pods -n gestion-proyectos dice esto error: Metrics API not available
## 1. Agregar el repositorio oficial
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/

## 2. Actualizar repositorios
helm repo update

## 3. Instalar (o reinstalar) el servidor de métricas
## Nota: Usamos --set args={--kubelet-insecure-tls} porque Docker Desktop usa certificados locales
helm install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set args="{--kubelet-insecure-tls}"
