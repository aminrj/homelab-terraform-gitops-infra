# modules/cnpg-cluster/cluster.yaml.tpl

apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: ${pg_cluster_name}
  namespace: ${pg_namespace}
spec:
  enableSuperuserAccess: true
  instances: ${pg_instance_count}

  imageName: ghcr.io/cloudnative-pg/postgresql:15

  storage:
    size: ${pg_storage_size}
    storageClass: ${pg_storage_class}

  superuserSecret:
    name: ${pg_superuser_secret}

  monitoring:
    enablePodMonitor: ${pg_monitoring_enabled}
    grafanaDashboard:
      create: true
      labels:
        grafana_dashboard: "1"

  bootstrap:
    initdb:
      database: app
      owner: app
      secret:
        name: ${pg_app_secret}
