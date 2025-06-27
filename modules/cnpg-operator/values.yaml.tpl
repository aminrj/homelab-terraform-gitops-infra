installCRDs: ${enable_crds}

pgAdmin:
  enabled: true
  image:
    repository: dpage/pgadmin4
    tag: "8.2"
  service:
    type: ClusterIP  # or LoadBalancer if you want it accessible externally
  ingress:
    enabled: false   # or true if you plan to expose it via ingress-nginx
  env:
    email: "admin@example.com"
    password: "supersecret"
  persistentVolume:
    enabled: false   # you can set true and configure pvc if you want persistence

monitoring:
  podMonitorEnabled: true
  prometheusRuleEnabled: true
  grafanaDashboard:
    create: true
    labels:
      grafana_dashboard: "1"
