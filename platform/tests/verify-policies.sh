#!/usr/bin/env bash
# Prove the Kyverno policies (o2c-app ADR-017): every manifest in this directory must be
# REJECTED in o2c-dev, and every rendered dev service must be ADMITTED (signature,
# registry, digest, non-root, limits). Server-side dry run: nothing is created.
#
#   platform/tests/verify-policies.sh      (needs the kind cluster with the platform,
#                                           and ../o2c-infra for the chart)
set -uo pipefail
CONTEXT="${CONTEXT:-kind-o2c}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITOPS="$(cd "$HERE/../.." && pwd)"
CHART="${CHART:-$GITOPS/../o2c-infra/helm/o2c-service}"
failed=0

for manifest in "$HERE"/*.yaml; do
  name="$(basename "$manifest")"
  if output=$(kubectl --context "$CONTEXT" apply --dry-run=server -f "$manifest" 2>&1); then
    echo "FAIL  $name was admitted"
    failed=1
  elif grep -q "blocked due to the following policies" <<< "$output"; then
    echo "ok    $name rejected by: $(grep -oE '^o2c-[a-z-]+' <<< "$output" | sort -u | tr '\n' ' ')"
  else
    echo "FAIL  $name failed for another reason: $output"
    failed=1
  fi
done

for values in "$GITOPS"/envs/dev/*.yaml; do
  service="$(basename "$values" .yaml)"
  if output=$(helm template "$service" "$CHART" --namespace o2c-dev --values "$values" \
    | kubectl --context "$CONTEXT" apply --dry-run=server --namespace o2c-dev -f - 2>&1); then
    echo "ok    dev/$service admitted"
  else
    echo "FAIL  dev/$service rejected: $output"
    failed=1
  fi
done

if [ "$failed" -eq 0 ]; then echo "PASS"; else echo "FAIL"; fi
exit "$failed"
