# 🚀 Aprendiendo Kubernetes con Gestión de Proyectos

Guía paso a paso para desplegar tu API ASP.NET Core + PostgreSQL en Kubernetes
y agregar monitoreo con Prometheus + Grafana.

---

## 📁 Estructura de archivos

```
k8s/
├── namespace.yaml                  # Agrupa todos tus recursos
├── postgres/
│   ├── secret.yaml                 # Credenciales de BD (base64)
│   ├── pvc.yaml                    # Volumen persistente para datos
│   └── deployment.yaml             # PostgreSQL + Service interno
├── api/
│   ├── configmap.yaml              # Config no sensible (URLs, entorno)
│   ├── secret.yaml                 # JWT Key, AWS credentials
│   ├── deployment.yaml             # Tu API + Service expuesto
│   └── hpa.yaml                    # Autoscaler (2-5 réplicas)
└── monitoring/
    └── install-monitoring.sh       # Comandos Helm para Prometheus+Grafana
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
# Primero el Secret (credenciales)
kubectl apply -f k8s/postgres/secret.yaml

# Luego el volumen persistente
kubectl apply -f k8s/postgres/pvc.yaml

# Finalmente el Deployment y Service
kubectl apply -f k8s/postgres/deployment.yaml

# Verificar que el pod está corriendo
kubectl get pods -n gestion-proyectos
kubectl get pvc -n gestion-proyectos
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

### Paso 4: Construir y publicar tu imagen Docker

```bash
# Construir tu imagen
docker build -t tu-usuario/gestion-proyectos-api:latest .

# Opción A — Docker Hub
docker push tu-usuario/gestion-proyectos-api:latest

# Opción B — Solo local (sin push, para aprender)
# Cambia imagePullPolicy: Never en deployment.yaml
```

### Paso 5: Agregar métricas Prometheus a tu API

Agrega el paquete NuGet:
```bash
dotnet add package prometheus-net.AspNetCore
```

En `Program.cs` (antes de `app.Run()`):
```csharp
using Prometheus;

app.UseMetricServer();   // Expone /metrics
app.UseHttpMetrics();    // Métricas HTTP automáticas (latencia, requests, errores)
```

### Paso 6: Desplegar tu API

```bash
# IMPORTANTE: edita k8s/api/secret.yaml con tus valores reales en base64
# echo -n "tu-jwt-key-de-minimo-32-chars" | base64

kubectl apply -f k8s/api/configmap.yaml
kubectl apply -f k8s/api/secret.yaml
kubectl apply -f k8s/api/deployment.yaml

# Verificar
kubectl get pods -n gestion-proyectos
kubectl get services -n gestion-proyectos
```

### Paso 7: Probar tu API

```bash
# Obtener la IP externa del LoadBalancer
kubectl get svc api-service -n gestion-proyectos

# En Docker Desktop la EXTERNAL-IP será localhost o 127.0.0.1
# Prueba:
curl http://localhost/healthz
curl http://localhost/swagger
```

> **Conceptos aprendidos:**
> - **ConfigMap**: variables de entorno no sensibles
> - **readinessProbe**: K8s verifica /healthz antes de enviar tráfico al pod
> - **livenessProbe**: K8s reinicia el pod si /healthz falla
> - **RollingUpdate**: actualización sin downtime

---

## 🎓 Semana 3 — Escalado y Monitoreo

### Paso 8: Activar el Autoscaler

```bash
kubectl apply -f k8s/api/hpa.yaml

# Ver el HPA en acción
kubectl get hpa -n gestion-proyectos -w

# Generar carga para ver cómo escala (instala hey o k6)
hey -n 10000 -c 50 http://localhost/healthz
```

### Paso 9: Instalar Prometheus + Grafana

```bash
# Seguir los pasos en k8s/monitoring/install-monitoring.sh
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
kubectl create namespace monitoring

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.adminPassword="admin123!" \
  --set grafana.service.type=LoadBalancer

# Esperar a que todos los pods estén Ready
kubectl get pods -n monitoring -w
```

### Paso 10: Explorar Grafana

```bash
# Obtener la URL de Grafana
kubectl get svc -n monitoring kube-prometheus-stack-grafana
# → Accede a http://EXTERNAL-IP:80
# Usuario: admin | Password: admin123!
```

**Dashboards recomendados para importar en Grafana (ID):**
- `1860` — Node Exporter Full (métricas del servidor)
- `6417` — Kubernetes Cluster (estado del cluster)
- `10427` — ASP.NET Core metrics (métricas de tu API)

---

## 🎓 Semana 4 — Logs y CI/CD

### Paso 11: Instalar Loki para logs

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack \
  --namespace monitoring \
  --set grafana.enabled=false \
  --set promtail.enabled=true
```

En Grafana → Data Sources → Add → Loki → URL: `http://loki:3100`

### Paso 12: GitHub Actions para CI/CD

Crea `.github/workflows/deploy-k8s.yml`:

```yaml
name: Deploy to Kubernetes

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build Docker image
        run: docker build -t ${{ secrets.DOCKERHUB_USERNAME }}/gestion-proyectos-api:${{ github.sha }} .

      - name: Push to Docker Hub
        run: |
          echo ${{ secrets.DOCKERHUB_TOKEN }} | docker login -u ${{ secrets.DOCKERHUB_USERNAME }} --password-stdin
          docker push ${{ secrets.DOCKERHUB_USERNAME }}/gestion-proyectos-api:${{ github.sha }}

      - name: Update deployment
        run: |
          kubectl set image deployment/gestion-proyectos-api \
            api=${{ secrets.DOCKERHUB_USERNAME }}/gestion-proyectos-api:${{ github.sha }} \
            -n gestion-proyectos
```

---

## 🛠️ Comandos kubectl más usados

```bash
# Ver todo en tu namespace
kubectl get all -n gestion-proyectos

# Ver logs en tiempo real
kubectl logs -f -n gestion-proyectos deployment/gestion-proyectos-api

# Entrar a un pod
kubectl exec -it -n gestion-proyectos deployment/gestion-proyectos-api -- /bin/bash

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
```

---

## 💡 Tips de aprendizaje

1. **Usa k9s** — visualiza todo el cluster en tiempo real con una UI en terminal
2. **Rompe cosas a propósito** — elimina pods y observa cómo K8s los recrea
3. **Lee los eventos** — `kubectl describe` siempre te dice qué falló
4. **Un concepto a la vez** — no saltes a Helm sin entender los YAMLs primero

---

*Proyecto: Gestión de Proyectos — Backend ASP.NET Core 8 + PostgreSQL*
