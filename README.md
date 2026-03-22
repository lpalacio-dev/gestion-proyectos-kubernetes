# 🚀 Aprendiendo Kubernetes con Gestión de Proyectos

Guía paso a paso para desplegar tu API ASP.NET Core + PostgreSQL en Kubernetes
y agregar monitoreo con Prometheus + Grafana + Loki.

> ✅ Guía probada en **Docker Desktop con Kubernetes** en Windows.
> Incluye soluciones a los problemas reales encontrados durante el proceso.

---

## 📁 Estructura de archivos

```
k8s/
├── namespace.yaml                  # Agrupa todos tus recursos
├── ingress.yaml                    # Punto de entrada único al cluster
├── postgres/
│   ├── secret.yaml                 # Credenciales de BD (base64)
│   ├── pvc.yaml                    # Volumen persistente para datos
│   └── deployment.yaml             # PostgreSQL + Service ClusterIP
├── api/
│   ├── configmap.yaml              # Config no sensible (URLs, entorno)
│   ├── secret.yaml                 # JWT Key, AWS credentials
│   ├── deployment.yaml             # Tu API + Service ClusterIP
│   ├── hpa.yaml                    # Autoscaler (2-5 réplicas)
│   └── servicemonitor.yaml         # Conecta Prometheus con tu API
└── monitoring/
    └── install-monitoring.sh       # Comandos Helm para todo el stack
```

---

## ⚙️ Requisitos previos

- Docker Desktop con Kubernetes habilitado (Settings → Kubernetes → Enable)
- `kubectl` instalado: https://kubernetes.io/docs/tasks/tools/
- `helm` instalado: https://helm.sh/docs/intro/install/
- `k9s` (opcional pero muy recomendado): https://k9scli.io/

---

## 🎓 Semana 1 — Conceptos y PostgreSQL

### Paso 1: Crear el namespace

```bash
kubectl apply -f k8s/namespace.yaml

# Verificar
kubectl get namespaces
```

> **Concepto aprendido:** Un Namespace es como una carpeta que agrupa
> tus recursos y los aísla de otros proyectos en el mismo cluster.

### Paso 2: Desplegar PostgreSQL

```bash
# En orden: secret → pvc → deployment
kubectl apply -f k8s/postgres/secret.yaml
kubectl apply -f k8s/postgres/pvc.yaml
kubectl apply -f k8s/postgres/deployment.yaml

# Esperar a que esté Running antes de continuar
kubectl get pods -n gestion-proyectos -w
# Ctrl+C cuando veas postgres en Running
```

> **Conceptos aprendidos:**
> - **Secret**: almacena datos sensibles codificados en base64
> - **PersistentVolumeClaim**: reserva espacio en disco que sobrevive al pod
> - **Deployment**: describe el estado deseado (1 réplica de postgres)
> - **Service ClusterIP**: DNS interno del cluster → `postgres-service:5432`

### Paso 3: Verificar que PostgreSQL responde

```bash
# Ver los logs del pod
kubectl logs -n gestion-proyectos deployment/postgres

# Entrar al pod interactivamente
kubectl exec -it -n gestion-proyectos deployment/postgres -- psql -U postgres

# Dentro de psql:
\l          # listar bases de datos
\q          # salir
```

---

## 🎓 Semana 2 — Tu API en Kubernetes

### Paso 4: Agregar métricas Prometheus a tu API

Antes de construir la imagen, agrega el paquete NuGet:

```bash
dotnet add package prometheus-net.AspNetCore
```

En `Program.cs` antes de `app.Run()`:

```csharp
using Prometheus;

app.UseMetricServer();   // Expone GET /metrics
app.UseHttpMetrics();    // Métricas HTTP automáticas (latencia, requests, errores)
```

### Paso 5: Construir la imagen Docker

```bash
# Construir la imagen localmente
docker build -t gestion-proyectos-api:latest .

# Verificar que existe
docker images | grep gestion-proyectos-api
```

> El `deployment.yaml` usa `imagePullPolicy: Never` para que Kubernetes
> use la imagen local sin intentar descargarla de ningún registry.

### Paso 6: Desplegar la API

```bash
kubectl apply -f k8s/api/configmap.yaml
kubectl apply -f k8s/api/secret.yaml
kubectl apply -f k8s/api/deployment.yaml

# Verificar
kubectl get pods -n gestion-proyectos
kubectl get services -n gestion-proyectos
```

> **Conceptos aprendidos:**
> - **ConfigMap**: variables de entorno no sensibles
> - **ClusterIP**: Service solo accesible dentro del cluster (no LoadBalancer)
> - **readinessProbe**: K8s verifica /healthz antes de enviar tráfico al pod
> - **livenessProbe**: K8s reinicia el pod si /healthz falla
> - **RollingUpdate**: actualización sin downtime

### Paso 7: Instalar el Ingress Controller y exponer la API

El Service es ClusterIP — solo el Ingress Controller lo expone al exterior.

```bash
# Instalar nginx Ingress Controller (una sola vez)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/cloud/deploy.yaml

# Esperar a que esté listo
kubectl get pods -n ingress-nginx -w
# Ctrl+C cuando veas Running

# Aplicar las reglas de enrutamiento
kubectl apply -f k8s/ingress.yaml

# Verificar — ADDRESS debe mostrar localhost
kubectl get ingress -n gestion-proyectos
```

### Paso 8: Probar la API

```bash
curl http://localhost/healthz
# → Healthy

curl http://localhost/swagger/index.html
# → HTML del Swagger UI
```

> **⚠️ Diferencia importante con LoadBalancer:**
> Con `type: LoadBalancer` Docker Desktop asignaba localhost directamente.
> Con `type: ClusterIP` + Ingress, el tráfico entra por el Ingress Controller
> y se enruta internamente. ClusterIP es la práctica correcta en producción.

---

## 🎓 Semana 3 — Escalado y Monitoreo

### Paso 9: Activar el Autoscaler

```bash
kubectl apply -f k8s/api/hpa.yaml

# Ver el HPA en acción
kubectl get hpa -n gestion-proyectos -w

# Generar carga para ver cómo escala
hey -n 10000 -c 50 http://localhost/healthz
```

> **Concepto aprendido:** El HPA y el tipo de Service son completamente
> independientes. El Service encuentra pods por labels, el HPA los escala
> por métricas. Cambiar ClusterIP/LoadBalancer no afecta el autoscaling.

### Paso 10: Instalar Prometheus + Grafana

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
kubectl create namespace monitoring

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
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

# Esperar a que todos los pods estén Ready
kubectl get pods -n monitoring -w
```

> **⚠️ node-exporter deshabilitado:** En Docker Desktop el node-exporter
> falla con CrashLoopBackOff porque necesita acceso al filesystem del host
> que la VM de Docker Desktop no permite. No afecta nada importante.

> **⚠️ NodePort en lugar de LoadBalancer:** Docker Desktop a veces no
> asigna EXTERNAL-IP a los Services LoadBalancer del namespace monitoring.
> NodePort con puertos fijos es más confiable localmente.

**URLs de acceso:**
| Herramienta | URL |
|---|---|
| Grafana | http://localhost:32000 (admin / admin123!) |
| Prometheus | http://localhost:32001 |
| Alertmanager | http://localhost:32002 |

### Paso 11: Conectar Prometheus con tu API

El Service necesita labels para que el ServiceMonitor lo encuentre:

```bash
# Verificar que el Service tiene labels
kubectl get svc api-service -n gestion-proyectos --show-labels
# Debe mostrar: app=gestion-proyectos-api

# Aplicar el ServiceMonitor
kubectl apply -f k8s/api/servicemonitor.yaml

# Verificar en Prometheus → Status → Targets
# Debe aparecer: serviceMonitor/gestion-proyectos/api-monitor/0  1/1 up
```

> **⚠️ Problema frecuente:** Si el Service no tiene labels (`<none>`),
> el ServiceMonitor no encuentra nada y Prometheus muestra "No targets".
> Solución: agregar `labels: app: gestion-proyectos-api` en el metadata
> del Service dentro de deployment.yaml.

> **⚠️ Job name:** Prometheus asigna automáticamente `job="api-service"`
> tomando el nombre del Service. Los dashboards de la comunidad pueden
> esperar un job diferente. Verificar siempre con: `up{namespace="gestion-proyectos"}`

### Paso 12: Dashboards en Grafana

Grafana → **Dashboards → New → Import** → escribe el ID → Load → selecciona **Prometheus** → Import.

| ID | Dashboard | Notas |
|---|---|---|
| `15760` | Kubernetes All-in-one | Estado completo del cluster |
| `10915` | ASP.NET Core (prometheus-net) | Para tu API — ver nota abajo |
| `17346` | PostgreSQL | Queries y conexiones |

> **⚠️ Dashboard 10915 — problema de data source:**
> Este dashboard fue creado con un data source llamado `PROMETHEUS_MEDIUM`
> que no existe en tu instalación. Después de importar aparece el error:
> `Datasource ${DS_PROMETHEUS_MEDIUM} was not found`
>
> **Solución:** Dashboard → ⚙️ Settings → JSON Model → Ctrl+A → copiar
> todo el JSON → pegar en un editor de texto → buscar y reemplazar
> TODAS las ocurrencias de `${DS_PROMETHEUS_MEDIUM}` por `Prometheus`
> → copiar el JSON corregido → pegarlo de vuelta en Grafana → Save.
>
> **⚠️ Los cambios son solo locales** — si el pod de Grafana se reinicia,
> se pierden. Para hacerlos persistentes exporta el dashboard como JSON
> y guárdalo como ConfigMap con el label `grafana_dashboard=1`.

---

## 🎓 Semana 4 — Logs con Loki

### Paso 13: Instalar Loki v3 + Promtail

> **⚠️ No usar `loki-stack`:** El chart `loki-stack` instala Loki v2.9
> que es incompatible con las versiones recientes de Grafana.
> Usar el chart `loki` directamente para obtener v3.

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Instalar Loki v3 en modo single binary
helm install loki grafana/loki \
  --namespace monitoring \
  --set loki.auth_enabled=false \
  --set deploymentMode=SingleBinary \
  --set singleBinary.replicas=1 \
  --set loki.commonConfig.replication_factor=1 \
  --set loki.storage.type=filesystem \
  --set loki.useTestSchema=true \
  --set minio.enabled=false \
  --set backend.replicas=0 \
  --set read.replicas=0 \
  --set write.replicas=0

# Instalar Promtail apuntando al gateway de Loki v3
helm install promtail grafana/promtail \
  --namespace monitoring \
  --set config.clients[0].url=http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push

# Verificar
kubectl get pods -n monitoring | grep -E "loki|promtail"
# loki-0           1/1   Running
# promtail-xxxxx   1/1   Running
```

### Paso 14: Conectar Loki a Grafana

En Grafana → **Connections → Data Sources → Add → Loki**

```
URL: http://loki-gateway.monitoring.svc.cluster.local/
```

> **⚠️ URLs que NO funcionan en Docker Desktop con Loki v3:**
> - `http://loki:3100` — el gateway nginx de v3 cambia la URL
> - `http://loki.monitoring.svc.cluster.local:3100` — mismo problema
> - `http://<CLUSTER-IP>:3100` — aunque el pod responda /ready,
>   Grafana falla el Save & Test por el modo multi-tenant de v3
>
> La URL correcta es siempre la del **gateway**:
> `http://loki-gateway.monitoring.svc.cluster.local/`

Clic en **Save & Test** → debe aparecer mensaje verde.

### Paso 15: Explorar logs en Grafana

Grafana → **Explore → Loki** y ejecuta estas queries:

```logql
# Todos los logs de tu namespace
{namespace="gestion-proyectos"}

# Solo tu API
{namespace="gestion-proyectos", container="api"}

# Errores
{namespace="gestion-proyectos", container="api"} |= "error"

# Errores HTTP 500
{namespace="gestion-proyectos", container="api"} |= "500"

# Logs de postgres
{namespace="gestion-proyectos", container="postgres"}
```

---

## 🛠️ Comandos kubectl más usados

```bash
# Ver todo en tu namespace
kubectl get all -n gestion-proyectos

# Ver logs en tiempo real
kubectl logs -f -n gestion-proyectos deployment/gestion-proyectos-api

# Entrar a un pod
kubectl exec -it -n gestion-proyectos deployment/gestion-proyectos-api -- /bin/sh

# Describir un pod (ver eventos, errores)
kubectl describe pod -n gestion-proyectos <nombre-del-pod>

# Reiniciar un deployment
kubectl rollout restart deployment/gestion-proyectos-api -n gestion-proyectos

# Ver historial de cambios
kubectl rollout history deployment/gestion-proyectos-api -n gestion-proyectos

# Hacer rollback al deploy anterior
kubectl rollout undo deployment/gestion-proyectos-api -n gestion-proyectos

# Escalar manualmente
kubectl scale deployment/gestion-proyectos-api --replicas=3 -n gestion-proyectos

# Ver el HPA en tiempo real
kubectl get hpa -n gestion-proyectos -w

# Ver todos los Services con sus labels
kubectl get svc -n gestion-proyectos --show-labels
```

---

## ⚠️ Problemas frecuentes y soluciones

| Problema | Causa | Solución |
|---|---|---|
| `node-exporter` en CrashLoopBackOff | Docker Desktop no permite acceso al filesystem del host | `--set nodeExporter.enabled=false` en helm upgrade |
| Grafana `EXTERNAL-IP: <pending>` | Docker Desktop no asigna IP a LoadBalancer en namespace monitoring | Cambiar a NodePort con puerto fijo |
| Prometheus `No targets` en ServiceMonitor | Service sin labels o puerto sin nombre | Agregar `labels` en metadata del Service y `name: http` en el puerto |
| Dashboard con `No data` | Variable `job` no coincide con el job real | Verificar job con `up{namespace="gestion-proyectos"}` en Prometheus |
| Dashboard con `DS_PROMETHEUS_MEDIUM not found` | Dashboard de comunidad con data source hardcodeado | Reemplazar en JSON Model por `Prometheus` |
| Loki `Unable to connect` con loki-stack | Incompatibilidad loki v2 con Grafana reciente | Instalar chart `grafana/loki` v3 directamente |
| Loki URL no conecta con IP o DNS simple | Loki v3 usa gateway nginx por defecto | Usar `http://loki-gateway.monitoring.svc.cluster.local/` |

---

## 💡 Tips de aprendizaje

1. **Usa k9s** — visualiza todo el cluster en tiempo real con una UI en terminal
2. **Rompe cosas a propósito** — elimina pods y observa cómo K8s los recrea
3. **Lee los eventos** — `kubectl describe` siempre te dice qué falló
4. **Un concepto a la vez** — no saltes a Helm sin entender los YAMLs primero
5. **Los labels son todo** — la mayoría de problemas de conectividad en K8s son por labels que no coinciden

---

*Proyecto: Gestión de Proyectos — Backend ASP.NET Core 8 + PostgreSQL*
*Entorno: Docker Desktop + Kubernetes en Windows*
