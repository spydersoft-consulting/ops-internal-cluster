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
