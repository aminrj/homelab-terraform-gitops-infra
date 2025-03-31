apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lb-addresses
  namespace: metallb-system
spec:
  addresses:
    - "${address_range}"
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: lb-addresses
  namespace: metallb-system
spec:
  ipAddressPools:
    - lb-addresses
