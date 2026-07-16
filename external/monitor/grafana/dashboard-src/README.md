# dashboard-src

Source JSON for dashboards provisioned via the `grafana_dashboard: "1"` sidecar
ConfigMaps in `../templates/*-dashboards-configmap.yaml`. Files referenced by
a ConfigMap's `.Files.Get` are live; anything else here is staged but not yet
wired up.

## Staged, not yet wired up

- **proxmox-via-prometheus.json** (grafana.com ID 10347, "Proxmox via
  Prometheus") - staged ahead of the Proxmox monitoring follow-up
  (node_exporter + prometheus-pve-exporter on pxdell/pxhp, see the
  observability plan). Not referenced by any ConfigMap yet because there's no
  data source for it: nothing scrapes those hosts today. Before wiring it up:
  1. Deploy the exporters (follow-up task, needs host access).
  2. Point an Alloy scrape job at them, routed to the `internal` tenant.
  3. This dashboard predates the `datasource` template-variable convention
     used by the other dashboards here (no `templating.list` datasource var
     at all - it hardcodes a datasource reference). Add one the same way the
     Linkerd dashboards were adapted (see the comment in
     `linkerd-dashboards-configmap.yaml`) so it can target
     Mimir-internal/production/nonproduction like everything else.
