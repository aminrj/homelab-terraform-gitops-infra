terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.19.0"
    }
  }
}

resource "kubectl_manifest" "infra_priority_class" {
  yaml_body = <<YAML
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: infra-critical
value: 1000000000
globalDefault: false
preemptionPolicy: PreemptLowerPriority
description: "Priority for critical infrastructure workloads"
YAML
}
