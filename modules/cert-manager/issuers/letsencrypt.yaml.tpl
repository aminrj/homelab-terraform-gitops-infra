# Let's Encrypt via DNS-01 on Cloudflare: works for names that only resolve inside the lab
# (split DNS on OPNsense), nothing has to be reachable from the internet.
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ${name}
spec:
  acme:
    server: ${server}
    email: ${email}
    privateKeySecretRef:
      name: ${name}-key
    solvers:
      - selector:
          dnsZones: ["${zone}"]
        dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: api-token
