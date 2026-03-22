# Instalar herramientas necesarias

```bash
## Usando Chocolatey (Recomendado)
choco install kubernetes-helm k9s

## O usando Winget (Nativo de Windows)
winget install Helm.Helm
winget install Derailed.K9s
```

# Instalar GO
Tuve que descargar GO para hacer la prueba de estres y autoescalado. Decidí descargar GO porque puedo instalar más cosas escritas en GO. GO organiza los archivos por mi.

```bash
go install github.com/rakyll/hey@latest
```
# Con kubectl top pods -n gestion-proyectos dice esto error: Metrics API not available
```bash
## 1. Agregar el repositorio oficial
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/

## 2. Actualizar repositorios
helm repo update

## 3. Instalar (o reinstalar) el servidor de métricas
## Nota: Usamos --set args={--kubelet-insecure-tls} porque Docker Desktop usa certificados locales
helm install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set args="{--kubelet-insecure-tls}"
```

# Instalar Prometheus + Grafana
Comandos adaptados para powershell
```bash
# 1. Crear el namespace para monitoreo
kubectl create namespace monitoring

# 2. Agregar el repositorio de Prometheus (si no lo has hecho)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 3. Instalar la pila de monitoreo (Kube-Prometheus-Stack)
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack `
  --namespace monitoring `
  --set grafana.adminPassword="admin123!" `
  --set grafana.service.type=LoadBalancer

#El último flag es importante — le dice a Prometheus que descubra métricas de todos los namespaces, no solo del que instaló Helm
helm install kube-prometheus-stack `
  prometheus-community/kube-prometheus-stack `
  --namespace monitoring `
  --set grafana.adminPassword="admin123!" `
  --set grafana.service.type=LoadBalancer `
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false

# deshabilitar node-exporter
helm upgrade kube-prometheus-stack `
  prometheus-community/kube-prometheus-stack `
  --namespace monitoring `
  --set grafana.adminPassword="admin123!" `
  --set grafana.service.type=LoadBalancer `
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false `
  --set nodeExporter.enabled=false

# Si quieres evitar el port-forward cada vez, actualiza el Service con Helm
helm upgrade kube-prometheus-stack `
  prometheus-community/kube-prometheus-stack `
  --namespace monitoring `
  --set grafana.adminPassword="admin123!" `
  --set grafana.service.type=NodePort `
  --set grafana.service.nodePort=32000 `
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false `
  --set nodeExporter.enabled=false

# Asignando puertos a grafana, prometheus, alertmanager
helm upgrade kube-prometheus-stack `
  prometheus-community/kube-prometheus-stack `
  --namespace monitoring `
  --set grafana.adminPassword="admin123!" `
  --set grafana.service.type=NodePort `
  --set grafana.service.nodePort=32000 `
  --set prometheus.service.type=NodePort `
  --set prometheus.service.nodePort=32001 `
  --set alertmanager.service.type=NodePort `
  --set alertmanager.service.nodePort=32002 `
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false `
  --set nodeExporter.enabled=false
```
## Errores en kube-prometheus-stack
**node-exporter crashloop**
El node-exporter necesita acceso al sistema de archivos del nodo host para leer métricas de CPU y RAM, pero Docker Desktop corre Kubernetes dentro de una VM ligera en lugar de directamente en tu sistema operativo — eso hace que el montaje de /proc y /sys falle.
La buena noticia: no afecta nada importante para aprender. Prometheus, Grafana, Alertmanager y kube-state-metrics están todos Running. El node-exporter solo aporta métricas del hardware físico del nodo, que en un entorno local de aprendizaje no necesitas.

**Por qué pasa esto en Docker Desktop**
En Linux nativo o en un cloud real (EKS, GKE) el node-exporter funciona perfectamente porque tiene acceso directo al kernel. Docker Desktop en macOS y Windows corre una VM intermedia (LinuxKit) y los montajes de /proc del host no están disponibles para los contenedores de Kubernetes. Es una limitación del entorno local, no un error tuyo.

# Acceso a grafana
Tuve un error al intentar acceder a grafana para empezar EXTERNAL-IP queda en pending. No pude acceder desde localhost:80 ni localhost:31753.

¿Qué buscar?: En la columna PORT(S), deberías ver algo como 80:31753/TCP.

El problema: Si en EXTERNAL-IP sigue apareciendo <pending> y localhost:80 no carga, es posible que otro programa en tu Windows (como Skype, IIS o un servidor web local) ya esté usando el puerto 80.

## El "Salvavidas": Port-Forward
Esto conecta un puerto de tu terminal de Windows directamente con el Pod de Grafana, saltándose cualquier problema de red o de LoadBalancer.
Ejecuta este comando y no cierres la terminal:
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```
### Paso 11: Instalar Loki para logs
```bash
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

# Si ya instalaste promtail antes, desinstálalo primero
helm uninstall promtail -n monitoring

# Instalar apuntando al gateway de Loki v3
helm install promtail grafana/promtail `
  --namespace monitoring `
  --set config.clients[0].url=http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push
```
