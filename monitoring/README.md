# Monitoring — Prometheus & Grafana

Deployed via the `kube-prometheus-stack` Helm chart (Prometheus, Grafana,
Alertmanager, node-exporter, kube-state-metrics).

## Install

    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    helm install monitoring prometheus-community/kube-prometheus-stack \
      --namespace monitoring --create-namespace

## Access Grafana

    kubectl get secret -n monitoring monitoring-grafana \
      -o jsonpath='{.data.admin-password}' | base64 -d ; echo
    kubectl port-forward -n monitoring svc/monitoring-grafana 3001:80
    # open http://localhost:3001  (user: admin)

## Dashboards (JSON exports in ./dashboards/)
- k8s-compute-cluster.json  — cluster-wide CPU/memory
- k8s-namespace-pods.json   — per-pod metrics (filter namespace = expensy)
- node-exporter-nodes.json  — node-level infrastructure metrics

## Alerting
34 pre-configured Prometheus alert rule groups (pod health, node pressure,
resource saturation) ship with the stack, routed via Alertmanager.
Verify: kubectl get prometheusrules -n monitoring
