# Monitoring, alerting & metrics

Covers spec §26: API latency, error rate, and payment/webhook failures, plus a
liveness uptime check. Everything is defined as code in `monitoring/*.json` and
applied with `scripts/setup-monitoring.sh`. No secrets live here — the project,
host, and notification channel are substituted at apply time.

## What gets created

| File | What it watches | Fires when |
| --- | --- | --- |
| `monitoring/uptime-check.json` | `GET /api/v1/health/live` from 3 regions | — |
| `monitoring/alert-uptime.json` | the uptime check | < 50% checks pass for 2 min |
| `monitoring/alert-error-rate.json` | Cloud Run `request_count` 5xx | 5xx rate sustained 5 min |
| `monitoring/alert-latency.json` | Cloud Run `request_latencies` | p95 > 1500 ms for 5 min |
| `monitoring/log-metric-payment-failures.json` | error logs (payment/webhook/refund) | (defines the metric) |
| `monitoring/alert-payment-failures.json` | that log metric | any failure logged |

The liveness probe deliberately checks no dependencies (a failing DB must not
restart a healthy container); readiness (`/api/v1/health/ready`) verifies the DB
round-trip and is what the load balancer drains on.

## Apply

```bash
# 1. Create a notification channel once (email shown; Slack/PagerDuty similar):
gcloud beta monitoring channels create \
  --project "$PROJECT_ID" \
  --display-name "Ops email" \
  --type email \
  --channel-labels email_address=ops@example.com
gcloud beta monitoring channels list --project "$PROJECT_ID" --format='value(name)'

# 2. Apply everything:
PROJECT_ID=rami-broast \
API_HOST=rami-api-xxxx-ww.a.run.app \
NOTIFICATION_CHANNEL=projects/rami-broast/notificationChannels/123 \
./scripts/setup-monitoring.sh
```

## Tuning the payment-failure metric

`log-metric-payment-failures.json` matches `severity>=ERROR` logs mentioning
payment/webhook/refund. The backend uses **pino** structured logs with a
redaction list (secrets never appear), so before relying on this alert, run one
real failure in staging and confirm the filter matches the actual log shape —
adjust `jsonPayload.context` / `textPayload` to the real fields. This is the one
policy whose filter depends on log content rather than a platform metric.

## Dashboards

Cloud Run ships built-in dashboards (request count, latency, instance count,
CPU/memory). Add a custom dashboard combining those with the uptime check and
the payment-failure metric via **Monitoring → Dashboards → Create**, or export
one to `monitoring/dashboard.json` and apply with
`gcloud monitoring dashboards create --config-from-file=...` once the team
settles the layout.

## Thresholds

Starting points, not gospel — revisit after the first week of real traffic:
error rate > ~5%, p95 > 1.5 s. Payment/webhook failures alert on the **first**
occurrence: money paths are idempotent and low-volume, so a failure is worth a
look, not a page-storm (`autoClose` 1 h).
