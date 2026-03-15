# Tooling for Unified API and MCP Tool Development with Visibility

## The Problem

Today's common pattern is to build a REST API first, then bolt on an MCP server as a separate layer that wraps those endpoints. This creates a maintenance burden: two codebases to keep in sync, no single view of what is exposed where, and easy drift between the API surface and the tool surface. The ideal is a single development workflow where you define your business logic once and declaratively control whether each operation is exposed as an API endpoint, an MCP tool, or both -- with a dashboard or manifest that makes this mapping visible at a glance.

No single tool fully solves this end-to-end today, but a strong ecosystem is rapidly forming. The approaches fall into three tiers: framework-level libraries, code-generation platforms, and gateway/registry infrastructure.

---

## Tier 1: Framework-Level Libraries (Define Once, Expose Both)

These let you write your backend logic once and serve it simultaneously as REST and MCP from the same process.

### FastAPI-MCP (tadata-org)

[FastAPI-MCP](https://github.com/tadata-org/fastapi_mcp) is the most direct answer to the unification question for Python shops. You mount an MCP server directly onto your FastAPI application with zero configuration, and every route automatically becomes an MCP tool. Crucially, it supports selective exposure through four filtering mechanisms:

- `include_operations` / `exclude_operations` -- whitelist or blacklist by operation ID
- `include_tags` / `exclude_tags` -- filter by OpenAPI tag

This means you can tag a route as `"api-only"` or `"mcp-only"` and get precise control. The operation ID from your FastAPI route becomes the MCP tool name, and request/response schemas are preserved from OpenAPI. Authentication flows through your existing FastAPI dependency injection, so there is no separate auth layer for MCP.

```python
from fastapi import FastAPI
from fastapi_mcp import FastApiMCP

app = FastAPI()

# Your normal routes
@app.get("/users/{user_id}", tags=["api-and-mcp"])
async def get_user(user_id: int): ...

@app.post("/internal/migrate", tags=["api-only"])
async def migrate_db(): ...

# Mount MCP -- expose only routes tagged for MCP
mcp = FastApiMCP(app, exclude_tags=["api-only"])
mcp.mount()
```

**Visibility**: You can inspect `mcp.tools` at runtime or write a startup hook that prints a table of which routes are API-only, MCP-only, or both. There is no built-in visual dashboard, but the tag-based system makes it straightforward to build one or generate a static manifest.

### FastMCP (Prefect/jlowin)

[FastMCP](https://gofastmcp.com/) takes the opposite entry point: you start from an MCP server and can import existing OpenAPI specs or FastAPI apps into it. Its `route_map_fn` callback gives you per-route control over whether an endpoint becomes a TOOL, RESOURCE, RESOURCE_TEMPLATE, or is EXCLUDED entirely.

```python
from fastmcp import FastMCP

mcp = FastMCP.from_openapi(
    url="https://api.example.com/openapi.json",
    route_map_fn=lambda route: "TOOL" if route.method == "POST" else "RESOURCE"
)
```

FastMCP 3.0 added server composition, allowing you to merge multiple MCP servers (or API specs) into a single unified server. This is useful for organizations with many microservices that want a single MCP surface.

**Visibility**: The `route_map_fn` pattern is inherently explicit -- you can log every routing decision and produce a mapping table at startup.

---

## Tier 2: Code Generation Platforms (OpenAPI as Single Source of Truth)

These tools take your OpenAPI specification and generate a fully functional MCP server alongside (or instead of) traditional SDKs. The OpenAPI spec becomes the canonical definition, and both REST and MCP surfaces are derived from it.

### Speakeasy

[Speakeasy](https://www.speakeasy.com/product/mcp-server) generates production-ready, self-hostable MCP server code (TypeScript) from your OpenAPI spec. The generated server is real code you own and can customize, not a hosted proxy. Notable features:

- Generates one tool per API endpoint by default, or a dynamic mode with meta-tools (`list_api_endpoints`, `get_api_endpoint_schema`, `invoke_api_endpoint`) that let the LLM discover endpoints at runtime
- Full OAuth 2.1 support, API keys, bearer tokens
- JQ-based response transforms to shape data for optimal LLM consumption
- Deployment to Cloudflare Workers, Docker, or any infrastructure

**Visibility**: Because the OpenAPI spec is the source of truth, you always know exactly which endpoints exist. The generated code makes the mapping explicit -- each tool maps to a named operation.

### Stainless

[Stainless](https://www.stainless.com/blog/generate-mcp-servers-from-openapi-specs) generates MCP servers alongside SDKs from OpenAPI specs, for free. Their architecture is distinctive: instead of one tool per endpoint, they generate a code execution tool and a docs search tool. The LLM writes SDK code that the MCP server executes, which is more token-efficient for large APIs.

They also support a `--tools=dynamic` mode that exposes three meta-tools for endpoint discovery and invocation, and handle client-specific quirks (Cursor's 40-tool limit, OpenAI's lack of root `anyOf` support).

### AWS OpenAPI MCP Server

[AWS's OpenAPI MCP Server](https://awslabs.github.io/mcp/servers/openapi-mcp-server/) dynamically creates MCP tools from OpenAPI specifications at runtime. No code generation step -- you point it at a spec and it creates tools on the fly.

### openapi-mcp-generator

[openapi-mcp-generator](https://github.com/harsha-iiiv/openapi-mcp-generator) is a CLI tool that generates MCP servers that proxy to existing REST APIs. Simpler than Speakeasy or Stainless, useful for quick prototyping.

---

## Tier 3: Gateway and Registry Infrastructure (Centralized Visibility)

This is where the "visualization" part of the question gets the most direct answer. Gateways sit in front of your APIs and MCP servers, providing a unified registry, dashboard, and governance layer.

### IBM ContextForge

[ContextForge](https://ibm.github.io/mcp-context-forge/) is the most feature-complete open-source option for centralized visibility. It is a gateway, registry, and proxy that federates MCP servers, A2A servers, and REST/gRPC APIs behind a single endpoint. Key capabilities:

- **Admin Dashboard** (`/admin`) with a web UI for managing servers and tools, including search, filtering, and pagination
- **Tool Registry** with bulk import (up to 200 tools per request) and per-tool metadata
- **MCP Inspector** for browsing tools, prompts, and resources in real time and invoking tools with JSON params
- **Protocol conversion** between stdio, SSE, and Streamable HTTP
- Converts REST API endpoints to MCP directly within the gateway

This is the closest thing to the "see which routes are API endpoints, which are MCP tools, and which are both" dashboard described in the question.

### Azure API Management

[Azure API Management](https://learn.microsoft.com/en-us/azure/api-management/export-rest-mcp-server) offers one-click conversion of managed REST APIs into MCP servers, plus the ability to proxy existing MCP servers behind the same API gateway. Combined with Azure API Center, you get a unified catalog of traditional APIs, AI model APIs, MCP servers, and agent APIs -- all in one registry with governance controls.

This is the enterprise-grade answer: if you already manage your APIs through Azure APIM, you can expose any of them as MCP tools without writing code, and the portal gives you full visibility into what is exposed where.

### Microsoft MCP Gateway (Kubernetes)

[Microsoft's MCP Gateway](https://github.com/microsoft/mcp-gateway) is a reverse proxy and management layer for MCP servers in Kubernetes environments, handling session-aware routing and lifecycle management. More infrastructure-focused than ContextForge, but useful for production deployments at scale.

### Portkey, MintMCP, and Other Commercial Gateways

Commercial MCP gateways like [Portkey](https://portkey.ai/) and [MintMCP](https://www.mintmcp.com/) provide managed dashboards with authentication, rate limiting, observability (Prometheus metrics, OpenTelemetry tracing), and tool registries. These are "unified LLM and tool gateways" that show all your MCP tools and API endpoints from a single pane of glass.

---

## Emerging Patterns

### The "OpenAPI-as-Contract" Pattern

The strongest emerging pattern is using OpenAPI as the single source of truth for both REST and MCP surfaces. You write your OpenAPI spec (or generate it from framework annotations), then derive both the REST server and the MCP server from it. Tools like Speakeasy, Stainless, FastMCP, and AWS's MCP server all support this. The benefit is that your API and MCP tool surfaces can never drift -- they are both generated from the same document.

### Decorator-Based Dual Exposure

FastAPI-MCP and FastMCP demonstrate a pattern where decorators or tags on your route handlers control exposure. This is the most developer-friendly approach for greenfield projects:

```python
@app.post("/send-email", tags=["mcp-tool", "api"])
async def send_email(to: str, subject: str, body: str): ...

@app.get("/health", tags=["api-only"])
async def health_check(): ...
```

The tags serve as the "visualization" -- you can grep your codebase or generate a report.

### Gateway-Level Unification

For organizations with existing APIs that cannot be refactored, gateways like ContextForge and Azure APIM provide unification at the infrastructure layer. You register your APIs and MCP servers in the gateway, and its admin UI becomes the single source of truth for what is exposed where.

### Dynamic Tool Discovery

Stainless and Speakeasy's "dynamic" modes (meta-tools that let the LLM discover and invoke endpoints at runtime) represent a shift away from static tool registration. This avoids the tool-count explosion problem and works well for large APIs, but makes the "visibility" question more nuanced since the available tools depend on runtime queries.

---

## Practical Recommendations

1. **For new Python projects**: Start with **FastAPI-MCP**. Define your routes with tags that explicitly mark exposure mode (`api-only`, `mcp-only`, `both`). Write a startup hook or CLI command that prints a table of all routes with their exposure status.

2. **For existing APIs with OpenAPI specs**: Use **Speakeasy** or **FastMCP's OpenAPI integration** to generate MCP servers from your spec. The spec itself becomes your visibility tool -- annotate it with `x-mcp-expose: true/false` extension fields if you need fine-grained control.

3. **For enterprise environments with many services**: Deploy **IBM ContextForge** or **Azure API Management** as a gateway. Register all your APIs and MCP servers in it and use the admin dashboard for visibility.

4. **For a custom visualization dashboard**: None of the current tools provide a purpose-built "API vs MCP mapping" UI. Build a lightweight one by:
   - Parsing your OpenAPI spec for all endpoints
   - Querying your MCP server's `tools/list` endpoint
   - Cross-referencing the two lists to produce a matrix of endpoint, API-exposed, MCP-exposed, auth-required

5. **For future-proofing**: Adopt the OpenAPI-as-contract pattern regardless of which framework you choose. This keeps your options open as the tooling matures and ensures that API and MCP surfaces stay in sync by construction.

---

## Summary Table

| Tool | Type | Language | Selective Exposure | Visual Dashboard | Open Source |
|------|------|----------|-------------------|-----------------|-------------|
| FastAPI-MCP | Framework library | Python | Yes (tags, operation IDs) | No (programmatic) | Yes |
| FastMCP | Framework library | Python | Yes (route_map_fn) | No (programmatic) | Yes |
| Speakeasy | Code generator | TypeScript | Yes (OpenAPI filtering) | No | No (commercial) |
| Stainless | Code generator | TypeScript | Yes (dynamic tools) | No | Free tier |
| IBM ContextForge | Gateway/Registry | Python | Yes (per-tool config) | Yes (Admin UI) | Yes |
| Azure API Management | Gateway/Registry | N/A (managed) | Yes (portal config) | Yes (Azure Portal) | No (cloud service) |
| AWS OpenAPI MCP | Runtime generator | TypeScript | Partial | No | Yes |

The tooling gap that remains is a unified development experience where you annotate your business logic once with exposure metadata and get a live, interactive dashboard showing the full API/MCP mapping. FastAPI-MCP with ContextForge comes closest to this today, but a truly integrated solution -- a framework with a built-in dev dashboard showing the dual surface -- has not yet emerged.
