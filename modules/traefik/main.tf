# Traefik: the cluster's ingress controller (replaces ingress-nginx, retired upstream in
# March 2026). Serves standard Ingress resources; IngressClass `traefik` is the default, so
# an Ingress without ingressClassName lands here too. HTTP redirects to HTTPS for everything.
# The LoadBalancer IP is the ingress VIP from the homelab-foundation inventory
# (kubernetes.ingress_vip), which OPNsense's split DNS points *.lab.aminrj.com at.
resource "helm_release" "traefik" {
  name             = "traefik"
  namespace        = "traefik"
  create_namespace = true
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = var.chart_version
  wait             = true
  timeout          = 600

  values = [yamlencode({
    ingressClass = { enabled = true, isDefaultClass = true, name = "traefik" }
    providers = {
      kubernetesCRD     = { enabled = true }
      # allowExternalNameServices: Ingresses to VMs outside k8s (Home Assistant), through a DNS
      # name; Argo CD 3 does not manage hand-written EndpointSlices.
      kubernetesIngress = { enabled = true, publishedService = { enabled = true }, allowExternalNameServices = true }
    }
    ports = {
      web = {
        http = { redirections = { entryPoint = { to = "websecure", scheme = "https", permanent = true } } }
      }
      websecure = { http = { tls = { enabled = true } } }
    }
    service = {
      type        = "LoadBalancer"
      annotations = { "metallb.io/loadBalancerIPs" = var.load_balancer_ip }
    }
    accessLog = { enabled = true }
  })]
}
