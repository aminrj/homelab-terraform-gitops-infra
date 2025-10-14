# Future Hardening Ideas

These are follow-up resilience tasks we paused while focusing on alerting:

- Add PodDisruptionBudgets for each production workload (commafeed, listmonk, wallabag, n8n, ingress, MetalLB speakers) to keep at least one pod running during node drains.
- Introduce namespace-level `LimitRange` and `ResourceQuota` objects so optional apps cannot starve critical services.
- Increase replica counts for ingress and user-facing apps where capacity allows, to survive a single-node outage.
- Expand Prometheus alert coverage (database lag, MetalLB speaker status, ingress 5xx).
- Schedule a recurring CNPG restore drill to validate backups.

Revisit this list after alerting is in place.
