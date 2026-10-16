# Optional: Datadog telemetry (OTLP → in-pod Datadog Agent sidecar) — AKS

Ported from the EKS add-on (originally from a working `cicd-k8s-ai-gw/eks/datadog`
deployment). The `airs-gw` gateway pushes OTLP (APM traces + aggregated analytics +
AI/LLM Observability) to a **Datadog Agent sidecar** in the same pod, which forwards to
Datadog. Off by default; enable with `enable_datadog_otel = true` and re-apply stage
`40-aigateway`.

## Why a sidecar

The gateway pushes to `http://localhost:4318` — the pod's shared loopback — so the
collector **must** run as a container in the **same pod** (a node DaemonSet isn't
reachable at `localhost`). It's model-agnostic: the GenAI spans capture whatever provider
the gateway calls, i.e. **Azure AI Foundry** on AKS.

## How it wires up (what stage 40 renders when enabled)

```
gateway ──OTLP/JSON http://localhost:4318──▶ datadog-agent sidecar ──▶ Datadog (DD_SITE)
```

- **Gateway `extraEnv`** — two exporters:
  - `OTEL_PUSH_ENABLED=true` + `OTEL_ENDPOINT` + `OTEL_SERVICE_NAME` → **aggregated
    analytics only**.
  - `EXPERIMENTAL_GEN_AI_OTEL_TRACES_ENABLED=true` +
    `EXPERIMENTAL_GEN_AI_OTEL_EXPORTER_OTLP_ENDPOINT` (base URL; gateway appends
    `/v1/traces`) → **per-request GenAI spans** (APM + AI Observability). `DD_API_KEY`
    (from the Secret) + `EXPERIMENTAL_GEN_AI_OTEL_EXPORTER_OTLP_HEADERS=dd-api-key=$(DD_API_KEY)`
    are kept but inert through the sidecar (the Agent uses its own key).
  - `EXPERIMENTAL_GEN_AI_OTEL_RESOURCE_ATTRIBUTES` carries the `env` tag.
- **SSRF allowlist** — `environment.data.TRUSTED_CUSTOM_HOSTS` **must include `localhost`**
  (+ `127.0.0.1,::1`), or the gateway's SSRF guard blocks the loopback push
  (`TypeError: fetch failed`). Host-only match **replaces** the built-ins, so
  `otel_trusted_custom_hosts` must list every host you need. (Public Foundry calls are
  unaffected — the guard only blocks loopback/private ranges.)
- **Sidecar (`sidecars[]`)** — `gcr.io/datadoghq/agent:7`, OTLP receivers on `:4318`/`:4317`,
  `DD_SITE`, `DD_SERVICE`, `DD_ENV`, `DD_APM_ENABLED=true`, `DD_HOSTNAME` from the pod name,
  `DD_API_KEY` from the Secret. `securityContext.allowPrivilegeEscalation=false`.

### One service name

The gateway bundle hardcodes `service.name=portkey` (first-wins through the Agent), so set
`otel_service_name = "portkey"` (default) and don't put `service.name` in the resource
attributes — everything lands under one Datadog service, `portkey`.

## Enable it

1. Copy the values from [`datadog.tfvars.example`](datadog.tfvars.example) into your
   gitignored `AKS/terraform/terraform.tfvars` and set the key.
2. `terraform apply -var-file=../terraform.tfvars` in `40-aigateway` (the gateway rolls
   with the sidecar added).

## The API key

Set `datadog_api_key` in the gitignored `terraform.tfvars`; Terraform creates the
`datadog-otel` cluster Secret (key `dd_api_key`) that both the gateway and sidecar read
via `secretKeyRef`. The key is never rendered into the Deployment or committed.

## Variables

| var | default | purpose |
|---|---|---|
| `enable_datadog_otel` | `false` | turn the sidecar + OTEL env on |
| `otel_endpoint` | `http://localhost:4318` | gateway → sidecar (leave as-is) |
| `otel_service_name` | `portkey` | single Datadog service (match the bundle hardcode) |
| `datadog_site` | `datadoghq.com` | your Datadog region (US1 = app.datadoghq.com) |
| `datadog_service` | `airs-gw` | `DD_SERVICE` on the sidecar |
| `datadog_env` | `azure` | `DD_ENV` + `deployment.environment` tag |
| `otel_trusted_custom_hosts` | `localhost,127.0.0.1,::1` | SSRF allowlist (must keep loopback) |
| `datadog_secret_name` | `datadog-otel` | Secret name (key `dd_api_key`) |
| `datadog_api_key` | `""` (sensitive) | the API key → cluster Secret |
| `datadog_agent_image` | `gcr.io/datadoghq/agent:7` | Datadog Agent image |

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

Identical hooks (`extraEnv` + `sidecars[]`) to the EKS add-on; only `datadog_env` defaults
differ (`azure` vs `aws`). GKE could be mirrored the same way.
