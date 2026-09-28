# Examples

Example values files for the `wproofreader` chart. These live outside the chart
directory on purpose: they are references to copy and adapt, not chart defaults,
and they are never part of the packaged chart.

| File | Purpose |
|------|---------|
| `values-dev.yaml` | Local minikube / development setup: DB connection plus db-manager provisioning, pointing at an in-cluster MySQL and the `wproofreader-db-credentials` Secret. Contains only the values that differ from the chart defaults — everything else is inherited from `wproofreader/values.yaml`. |

Usage, from the repository root:

```shell
helm install wproofreader-app ./wproofreader -n <namespace> \
  -f examples/values-dev.yaml \
  --set licenseTicketID=$WPR_LICENSE_TICKET_ID
```

See `manifests/db-credentials-secret.yaml` for the companion Secret.
