#!/usr/bin/env bash
# One-off before an ESO upgrade that drops an API version: rewrite every stored ESO object
# in the CRD's current storage version, then record that only this version is stored. Then
# nothing in etcd depends on the dropped version.
#
#   scripts/eso-storage-migrate.sh          # check: stored versions, what would be rewritten
#   scripts/eso-storage-migrate.sh --yes    # rewrite and update status.storedVersions
set -euo pipefail
K="kubectl --kubeconfig ${HOMELAB_KUBECONFIG:-$HOME/.kube/homelab} --context homelab"
YES=0; [ "${1:-}" = --yes ] && YES=1
for crd in $($K get crd -o name | sed 's|.*/||' | grep '\.external-secrets\.io$'); do
  storage=$($K get crd "$crd" -o jsonpath='{range .spec.versions[?(@.storage==true)]}{.name}{end}')
  stored=$($K get crd "$crd" -o jsonpath='{.status.storedVersions}')
  n=$($K get "$crd" -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
  printf '%-48s storage=%-8s stored=%-22s objects=%s\n' "$crd" "$storage" "$stored" "$n"
  [ $YES = 1 ] || continue
  if [ "$n" -gt 0 ]; then
    $K get "$crd" -A -o json | $K replace -f - >/dev/null
  fi
  $K patch crd "$crd" --subresource=status --type=json \
    -p "[{\"op\":\"replace\",\"path\":\"/status/storedVersions\",\"value\":[\"$storage\"]}]" >/dev/null
  echo "  -> rewritten, storedVersions=[$storage]"
done
[ $YES = 1 ] || echo "Nothing was changed. To apply: $0 --yes"
