# Datadog Telemetry for a Self-Hosted Portkey airs-gw Gateway

A vendor-neutral, repeatable guide to getting full Datadog observability out of a self-hosted
Portkey `airs-gw` gateway: **APM traces**, **APM inferred services**, and **AI (LLM) Observability**,
all under **one service name**.

> This is the generic write-up. For how it is wired in *this* repo (Terraform `extraEnv` +
> `sidecars[]` on stage `40-aigateway`, the `datadog-otel` cluster Secret), see [README.md](README.md).

---

## Goal

Emit from the closed gateway bundle, into Datadog, with no OTel Collector and no protobuf
re-encoding:

- APM traces (per-request GenAI spans)
- APM **inferred services** (orchestrator, downstream providers, etc.)
- **AI / LLM Observability**
- everything under a **single service name**

## Architecture

The gateway bundle's GenAI OTLP exporter is hardcoded to **HTTP/JSON**. Datadog's *direct public
intake* converts spans to LLM Observability only from `http/protobuf`, so the direct intake is a dead
end for LLM Obs. The supported path is an **in-pod Datadog Agent sidecar**:

```
gateway container ──OTLP/JSON over localhost:4318──▶ datadog-agent sidecar ──▶ Datadog
```

The Agent converts the JSON GenAI spans into AI Observability itself **and** computes APM inferred
services. No Collector, no protobuf hop.

## Prerequisites

- A Kubernetes Secret holding the Datadog API key (e.g. `datadog-otel`, key `dd_api_key`).
  **Never** put the key in a manifest or in Git.

---

## Gateway container env

```yaml
# 1) SSRF guard — the gateway rejects loopback by default. Allowlist localhost or the OTLP push to
#    localhost:4318 fails with "fetch failed". APPEND to any existing hosts; do not overwrite them.
TRUSTED_CUSTOM_HOSTS: "<existing-hosts>,localhost,127.0.0.1,::1"

# 2) Aggregated-analytics push + the service name for the whole deployment.
- { name: OTEL_PUSH_ENABLED,           value: "true" }
- { name: OTEL_ENDPOINT,               value: "http://localhost:4318" }   # the sidecar
- { name: OTEL_SERVICE_NAME,           value: "portkey" }                 # see "One service name"
- { name: OTEL_EXPORTER_OTLP_PROTOCOL, value: "http/json" }               # affects the analytics push only

# 3) Per-request GenAI spans (the real traces). The OTEL_PUSH_* pair above does NOT emit these.
- { name: EXPERIMENTAL_GEN_AI_OTEL_TRACES_ENABLED,         value: "true" }
- { name: EXPERIMENTAL_GEN_AI_OTEL_EXPORTER_OTLP_ENDPOINT, value: "http://localhost:4318" }  # BASE url; gateway appends /v1/traces

# DD_API_KEY must exist in THIS container (for the header) and be declared BEFORE the header var
# so k8s $(DD_API_KEY) interpolation resolves.
- name: DD_API_KEY
  valueFrom:
    secretKeyRef: { name: datadog-otel, key: dd_api_key }

# NO dd-otlp-source=llmobs header — see "Why no llmobs header".
- { name: EXPERIMENTAL_GEN_AI_OTEL_EXPORTER_OTLP_HEADERS,  value: "dd-api-key=$(DD_API_KEY)" }

# env tags only — NO service.name here (see "One service name"). Send both forms; Datadog maps the
# deprecated deployment.environment to `env` most reliably.
- { name: EXPERIMENTAL_GEN_AI_OTEL_RESOURCE_ATTRIBUTES,    value: "deployment.environment.name=<env>,deployment.environment=<env>" }
```

## Sidecar container

```yaml
- name: datadog-agent
  image: gcr.io/datadoghq/agent:7
  ports:
    - { containerPort: 4318 }   # OTLP/HTTP
    - { containerPort: 4317 }   # OTLP/gRPC
  env:
    - name: DD_API_KEY
      valueFrom:
        secretKeyRef: { name: datadog-otel, key: dd_api_key }
    - { name: DD_SITE,        value: "datadoghq.com" }   # your Datadog site
    - { name: DD_SERVICE,     value: "airs-gw" }
    - { name: DD_ENV,         value: "<env>" }           # env tag for the analytics push
    - { name: DD_APM_ENABLED, value: "true" }
    # Enable the OTLP receivers the gateway pushes to:
    - { name: DD_OTLP_CONFIG_RECEIVER_PROTOCOLS_HTTP_ENDPOINT, value: "0.0.0.0:4318" }
    - { name: DD_OTLP_CONFIG_RECEIVER_PROTOCOLS_GRPC_ENDPOINT, value: "0.0.0.0:4317" }
    - name: DD_HOSTNAME
      valueFrom:
        fieldRef: { fieldPath: metadata.name }
  securityContext:
    allowPrivilegeEscalation: false
```

> If the gateway container runs with `readOnlyRootFilesystem`, that applies only to the gateway
> container. The injected sidecar inherits pod-level settings and needs a writable rootfs (the
> default), so the Agent starts fine.

---

## Four things that trip people up

1. **SSRF guard blocks the loopback push.** Symptom: `TypeError: fetch failed` /
   "Failed to push analytics objects to OTel collector." Fix: add `localhost` to
   `TRUSTED_CUSTOM_HOSTS` (append — don't clobber existing entries).
2. **`OTEL_PUSH_*` ≠ traces.** That pair exports only aggregated analytics. Per-request GenAI spans
   require the `EXPERIMENTAL_GEN_AI_OTEL_*` vars.
3. **Endpoint is a base URL.** The gateway appends `/v1/traces`. If you add it yourself you get
   `/v1/traces/v1/traces` → 404.
4. **Why no `dd-otlp-source=llmobs` header.** That header is only for Datadog's *direct public
   intake*. Sent *through the Agent*, it routes spans to LLM-Obs-only and **starves the APM
   inferred-services pipeline**. Omit it and the Agent gives you all three: APM traces, inferred
   services, **and** AI Observability.

## One service name

The bundle hardcodes `service.name=portkey` as the **first** resource attribute on GenAI spans, and
through the Agent the **first** duplicate wins (the opposite of the direct intake's last-wins).
`DD_APM_SERVICE_MAPPING` does **not** apply to OTLP-ingested traces, so you cannot rename at the
Agent. To land everything under one service:

- Set `OTEL_SERVICE_NAME=portkey` (folds the analytics + `server.request` streams in).
- Do **not** set `service.name` in `EXPERIMENTAL_GEN_AI_OTEL_RESOURCE_ATTRIBUTES` — it is a dead
  no-op.

Everything then resolves to **`portkey`**. (The name must match the GenAI hardcode's winner; in
practice, use `portkey`.)

## Verify

- Gateway log: no `push analytics objects to OTel` / SSRF errors.
- `kubectl exec <pod> -c datadog-agent -- agent status` → traces received.
- Datadog **APM** → a single service (`portkey`) with `env:<env>` and inferred services present.
- Datadog **LLM Observability** → application populated.

---

## Why not the direct public intake?

The gateway's GenAI exporter is hardcoded to HTTP/JSON and ignores `OTEL_EXPORTER_OTLP_PROTOCOL`.
Datadog's direct public OTLP intake needs `http/protobuf` to convert spans to LLM Observability, so
the direct path accepts the JSON (HTTP 200), files it as a plain APM trace, and never produces an LLM
Obs span. The in-pod Agent does the JSON→LLM-Obs conversion itself, which is why this guide uses the
sidecar. (Upstream fix tracked separately: make the GenAI exporter honor protobuf.)
