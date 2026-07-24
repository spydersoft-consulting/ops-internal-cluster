# dashboard-src

Source JSON for dashboards provisioned via the `grafana_dashboard: "1"` sidecar
ConfigMaps in `../templates/*-dashboards-configmap.yaml`. Files referenced by
a ConfigMap's `.Files.Get` are live; anything else here is staged but not yet
wired up.

**proxmox-via-prometheus.json** (grafana.com ID 10347, "Proxmox via
Prometheus") is wired into `infrastructure-dashboards-configmap.yaml`.
pxdell/pxhp now run node_exporter + prometheus-pve-exporter + Alloy, pushing
to the `internal` Mimir tenant (see the Proxmox monitoring follow-up plan).
The dashboard predated the `datasource` template-variable convention (it
hardcoded `${DS_PROMETHEUS}`, an import-wizard-only placeholder) - rewritten
to hardcode `mimir-internal` instead, same as garage/vault, since Proxmox
hosts aren't part of any K8s cluster and have no production/nonproduction
variant to switch between.

**k8s-views-nodes.json** (dotdc/grafana-dashboards-kubernetes, "Nodes"
/ grafana.com ID 15759) is wired into `kubernetes-dashboards-configmap.yaml`,
unmodified, same as Namespaces/Pods. Added 2026-07-24 once node_exporter
started running on K8s cluster nodes (`cluster-tools/tools/node-exporter`
in ops-argo) - the keep-list in each cluster's `grafana-alloy`
`node_exporter_filter` block was built directly from this dashboard's
actual metric usage, per the `cardinality-cleanup-status.md` methodology
(scrape only what's referenced by a real dashboard/alert, not the full
~500-metric default set).
