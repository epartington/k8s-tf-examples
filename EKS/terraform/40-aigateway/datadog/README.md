# Optional: Datadog telemetry (OTLP → in-pod Datadog Agent sidecar) — EKS

Ported from a **working EKS deployment** (`cicd-k8s-ai-gw/eks/datadog`). The `airs-gw`
gateway pushes OTLP (APM traces + aggregated analytics + AI/LLM Observability) to a
**Datadog Agent sidecar** in the same pod, which forwards to Datadog. Off by default;
enable with `enable_datadog_otel = true` and re-apply stage `40-aigateway`.

## Why a sidecar (and why it mirrors ECS Fargate)

The gateway pushes to `http://localhost:4318` — the pod's shared loopback — so the
collector **must** be a container in the **same pod**. This is the only option on
**ECS Fargate** (serverless; no nodes/DaemonSet), where the DD Agent runs as a
**per-task sidecar**. An EKS pod sidecar is a 1:1 rehearsal:

| | ECS Fargate (real) | EKS pod (this POV) |
|---|---|---|
| Unit | task | pod |
| DD Agent | extra `containerDefinition` | chart `sidecars[]` entry |
| App → agent | `localhost:4318` | `localhost:4318` |
| API key | Secrets Manager / SSM task secret | K8s Secret `datadog-otel` (key `dd_api_key`) |
| Hostname | `DD_ECS_FARGATE=true` | `DD_HOSTNAME` ← pod name |

## How it wires up (what stage 40 renders when enabled)

```
gateway ──OTLP/JSON http://localhost:4318──▶ datadog-agent sidecar ──▶ Datadog (DD_SITE)
```

- **Gateway `extraEnv`** — two exporters:
  - `OTEL_PUSH_ENABLED=true` + `OTEL_ENDPOINT` + `OTEL_SERVICE_NAME` → **aggregated
    analytics only** (not per-request spans).
  - `EXPERIMENTAL_GEN_AI_OTEL_TRACES_ENABLED=true` +
    `EXPERIMENTAL_GEN_AI_OTEL_EXPORTER_OTLP_ENDPOINT` (base URL; gateway appends
    `/v1/traces`) → **per-request GenAI spans** (APM + AI Observability). `DD_API_KEY`
    (from the Secret) + `EXPERIMENTAL_GEN_AI_OTEL_EXPORTER_OTLP_HEADERS=dd-api-key=$(DD_API_KEY)`
    are kept but inert through the sidecar (the Agent uses its own key); they let you
    later flip the endpoint to Datadog's direct intake without re-plumbing.
  - `EXPERIMENTAL_GEN_AI_OTEL_RESOURCE_ATTRIBUTES` carries the `env` tag.
- **SSRF allowlist** — `environment.data.TRUSTED_CUSTOM_HOSTS` **must include `localhost`**
  (+ `127.0.0.1,::1`). The gateway's SSRF guard blocks loopback by default, so without
  it the push to `localhost:4318` fails with `TypeError: fetch failed` /
  "Failed to push analytics objects to OTel collector". Host-only match **replaces** the
  built-ins, so `otel_trusted_custom_hosts` must list every host you need.
- **Sidecar (`sidecars[]`)** — `gcr.io/datadoghq/agent:7`, OTLP receivers on `:4318`/`:4317`
  (`DD_OTLP_CONFIG_RECEIVER_PROTOCOLS_*`), `DD_SITE`, `DD_SERVICE`, `DD_ENV`,
  `DD_APM_ENABLED=true`, `DD_HOSTNAME` from the pod name, `DD_API_KEY` from the Secret.
  `securityContext.allowPrivilegeEscalation=false` (the chart's `readOnlyRootFilesystem`
  applies to the gateway container only; the Agent keeps a writable rootfs).

### One service name

The gateway bundle hardcodes `service.name=portkey` as the **first** resource attribute
on GenAI spans, and through the Agent the **first** duplicate wins. So set
`otel_service_name = "portkey"` (default) and do **not** put `service.name` in the
resource attributes — everything then lands under a single Datadog service, `portkey`.
(`DD_SERVICE` on the sidecar is separate — it tags the agent/analytics stream.)

## Enable it

1. Copy the values from [`datadog.tfvars.example`](datadog.tfvars.example) into your
   gitignored `EKS/terraform/terraform.tfvars` and set the key.
2. `terraform apply -var-file=../terraform.tfvars` in `40-aigateway`.

## The API key

Set `datadog_api_key` in the gitignored `terraform.tfvars`; Terraform creates the
`datadog-otel` cluster Secret (key `dd_api_key`) that both the gateway and the sidecar
read via `secretKeyRef`. The key is never rendered into the Deployment or committed.
(On ECS Fargate this becomes a task secret from Secrets Manager / SSM.)

## Variables

| var | default | purpose |
|---|---|---|
| `enable_datadog_otel` | `false` | turn the sidecar + OTEL env on |
| `otel_endpoint` | `http://localhost:4318` | gateway → sidecar (leave as-is) |
| `otel_service_name` | `portkey` | single Datadog service (match the bundle hardcode) |
| `datadog_site` | `datadoghq.com` | your Datadog region (US1 = app.datadoghq.com) |
| `datadog_service` | `airs-gw` | `DD_SERVICE` on the sidecar |
| `datadog_env` | `aws` | `DD_ENV` + `deployment.environment` tag |
| `otel_trusted_custom_hosts` | `localhost,127.0.0.1,::1` | SSRF allowlist (must keep loopback) |
| `datadog_secret_name` | `datadog-otel` | Secret name (key `dd_api_key`) |
| `datadog_api_key` | `""` (sensitive) | the API key → cluster Secret |
| `datadog_agent_image` | `gcr.io/datadoghq/agent:7` | match your Fargate task image |

## Verify

The gateway emits **OTLP trace signals** → look in **Datadog → APM → Traces** (service
`portkey`, GenAI spans under scope `custom.genai.instrumentation`) and **LLM
Observability**, not Datadog Logs.

```sh
NS=airs-gw
POD=$(kubectl get pod -n $NS -l app.kubernetes.io/name=airs-gw -o name | grep -v redis | head -1)
kubectl get $POD -n $NS -o jsonpath='{.spec.containers[*].name}'; echo   # expect: airs-gw datadog-agent
# no SSRF/push error after a request:
kubectl logs -n $NS $POD -c airs-gw --tail=100 | grep -i "push analytics objects to OTel" || echo "no push errors"
# agent OTLP receiver up:
kubectl exec -n $NS $POD -c datadog-agent -- agent status otlp
```

> See [EXTERNAL-SETUP.md](EXTERNAL-SETUP.md) for the vendor-neutral deep-dive (the four
> gotchas, why not the direct public intake, single-service-name).

## Parity note

EKS-only today (the real target is ECS Fargate). The same gated toggle can be mirrored
into `AKS/`/`GKE/` `40-aigateway` — the `extraEnv` + `sidecars[]` chart hooks are identical.
