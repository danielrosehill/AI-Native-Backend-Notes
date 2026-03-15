---
generated: 2026-03-15
model: claude-opus-4-6
---

# Dual MCP Server Architecture: Public and Admin Access

## The Scenario: CityTransit -- A Public Transit Data Platform

Consider **CityTransit**, a company that aggregates public transportation data for a metropolitan area. They maintain a database of routes, schedules, real-time vehicle positions, service alerts, and fare information. CityTransit wants to expose this data through MCP servers so that AI assistants and agentic applications can query transit information on behalf of users.

They need two MCP servers:

1. **CityTransit Public MCP** -- unauthenticated, read-only access to schedules, routes, and alerts. Any AI assistant can connect and answer questions like "When is the next bus on Route 42?" without credentials.
2. **CityTransit Admin MCP** -- authenticated, privileged access for transit authority staff. Supports creating service alerts, modifying schedules, managing fare rules, and viewing ridership analytics. Only authorized personnel can invoke these tools.

This is a realistic pattern: the underlying data is the same, but the operations and access levels differ dramatically between public consumers and internal administrators.

---

## The Two MCP Servers

### Public MCP Server

The public server exposes **read-only tools and resources**. It has no authentication requirement, making it easy for any MCP client to connect and start querying transit data. The design principle is simple: if the data is already published on the agency's website, it can be served through this MCP.

**Capabilities:**

- Query routes and stops
- Look up schedules and next departures
- Read active service alerts
- Get fare information
- Access real-time vehicle positions

### Admin MCP Server

The admin server exposes **read and write tools** behind OAuth 2.1 authentication. It is intended for internal staff using AI assistants to manage transit operations -- updating schedules after a disruption, publishing service alerts, adjusting fares, and reviewing ridership data.

**Capabilities:**

- All public read capabilities (so admins do not need two connections)
- Create, update, and delete service alerts
- Modify route schedules
- Update fare rules
- View ridership analytics and reports
- Manage stop and route metadata

---

## Tool Definitions

### Public MCP Server Tools

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

const publicServer = new McpServer({
  name: "citytransit-public",
  version: "1.0.0",
});

publicServer.tool(
  "get_next_departures",
  "Get upcoming departures from a specific stop",
  {
    stop_id: z.string().describe("The stop identifier, e.g. 'STOP-1042'"),
    route_id: z.string().optional().describe("Filter by route"),
    limit: z.number().min(1).max(20).default(5).describe("Number of results"),
  },
  async ({ stop_id, route_id, limit }) => {
    const departures = await db.departures.findUpcoming({ stop_id, route_id, limit });
    return {
      content: [{ type: "text", text: JSON.stringify(departures, null, 2) }],
    };
  }
);

publicServer.tool(
  "search_routes",
  "Search for transit routes by name, number, or area",
  {
    query: z.string().describe("Search term for route name or number"),
    transport_type: z.enum(["bus", "rail", "tram", "all"]).default("all"),
  },
  async ({ query, transport_type }) => {
    const routes = await db.routes.search({ query, transport_type });
    return {
      content: [{ type: "text", text: JSON.stringify(routes, null, 2) }],
    };
  }
);

publicServer.tool(
  "get_active_alerts",
  "Get current service alerts and disruptions",
  {
    route_id: z.string().optional().describe("Filter alerts by route"),
    severity: z.enum(["info", "warning", "critical", "all"]).default("all"),
  },
  async ({ route_id, severity }) => {
    const alerts = await db.alerts.findActive({ route_id, severity });
    return {
      content: [{ type: "text", text: JSON.stringify(alerts, null, 2) }],
    };
  }
);

publicServer.tool(
  "get_fare_info",
  "Look up fare pricing for a journey",
  {
    origin_stop: z.string().describe("Origin stop ID"),
    destination_stop: z.string().describe("Destination stop ID"),
    passenger_type: z.enum(["adult", "child", "senior", "student"]).default("adult"),
  },
  async ({ origin_stop, destination_stop, passenger_type }) => {
    const fare = await db.fares.calculate({ origin_stop, destination_stop, passenger_type });
    return {
      content: [{ type: "text", text: JSON.stringify(fare, null, 2) }],
    };
  }
);
```

### Admin MCP Server Tools

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

const adminServer = new McpServer({
  name: "citytransit-admin",
  version: "1.0.0",
});

// Re-export all public tools (imported from shared module)
registerPublicTools(adminServer);

// --- Write operations (admin only) ---

adminServer.tool(
  "create_service_alert",
  "Publish a new service alert for riders",
  {
    title: z.string().min(5).max(200).describe("Alert headline"),
    description: z.string().min(10).max(2000).describe("Full alert text"),
    severity: z.enum(["info", "warning", "critical"]),
    affected_routes: z.array(z.string()).min(1).describe("Route IDs affected"),
    start_time: z.string().datetime().describe("Alert start time (ISO 8601)"),
    end_time: z.string().datetime().optional().describe("Alert end time, if known"),
  },
  async ({ title, description, severity, affected_routes, start_time, end_time }, context) => {
    const user = context.authInfo.user; // from validated OAuth token
    await auditLog.record("create_alert", user, { title, severity });

    const alert = await db.alerts.create({
      title, description, severity, affected_routes,
      start_time, end_time,
      created_by: user.id,
    });
    return {
      content: [{ type: "text", text: `Alert created: ${alert.id} -- "${title}"` }],
    };
  }
);

adminServer.tool(
  "update_schedule",
  "Modify departure times for a route on a specific date",
  {
    route_id: z.string(),
    effective_date: z.string().date().describe("Date the change applies (YYYY-MM-DD)"),
    modifications: z.array(z.object({
      stop_id: z.string(),
      old_time: z.string().describe("Current departure time (HH:MM)"),
      new_time: z.string().describe("Updated departure time (HH:MM)"),
    })),
    reason: z.string().min(5).describe("Reason for modification"),
  },
  async ({ route_id, effective_date, modifications, reason }, context) => {
    const user = context.authInfo.user;
    if (!user.roles.includes("schedule_manager")) {
      throw new Error("Insufficient permissions: schedule_manager role required");
    }

    await auditLog.record("update_schedule", user, { route_id, effective_date, reason });
    const result = await db.schedules.batchUpdate({ route_id, effective_date, modifications });
    return {
      content: [{ type: "text", text: `Updated ${result.modifiedCount} departures on route ${route_id}` }],
    };
  }
);

adminServer.tool(
  "get_ridership_analytics",
  "Retrieve ridership statistics for a route or time period",
  {
    route_id: z.string().optional(),
    start_date: z.string().date(),
    end_date: z.string().date(),
    granularity: z.enum(["hourly", "daily", "weekly"]).default("daily"),
  },
  async ({ route_id, start_date, end_date, granularity }, context) => {
    const user = context.authInfo.user;
    if (!user.roles.includes("analytics_viewer")) {
      throw new Error("Insufficient permissions: analytics_viewer role required");
    }

    const stats = await db.analytics.query({ route_id, start_date, end_date, granularity });
    return {
      content: [{ type: "text", text: JSON.stringify(stats, null, 2) }],
    };
  }
);
```

---

## Development Approach

### Shared Schema and Data Layer

Both servers read from the same database. The team should build a **shared data access layer** as an internal package:

```
packages/
  citytransit-data/        # Shared: DB models, queries, validation
    src/
      models/              # Route, Stop, Alert, Schedule, Fare
      queries/             # Parameterized queries with row-level filtering
      validation/          # Zod schemas reused across both servers
servers/
  public-mcp/             # Public server: imports from citytransit-data
  admin-mcp/              # Admin server: imports from citytransit-data
```

This monorepo structure ensures that both servers share the same data models and query logic. Schema changes propagate to both servers through the shared package, preventing drift.

### Separate Tool Registrations

Tools are defined in a shared module where possible, then selectively registered on each server:

- **Public tools** are defined once and registered on both servers. The public server imports them directly; the admin server re-registers them so that admins have full read access without needing a second connection.
- **Admin tools** are defined only in the admin server package. They are never importable by the public server -- enforced at the package level, not just at runtime.

This separation means that even a misconfigured public server cannot accidentally expose admin tools because the code for those tools does not exist in its dependency tree.

### Database Access Patterns

The shared data layer should enforce read-only access for public queries at the connection level:

```typescript
// citytransit-data/src/connections.ts
export const readPool = new Pool({
  connectionString: process.env.DATABASE_URL_READONLY,
  // Uses a PostgreSQL role with SELECT-only grants
});

export const writePool = new Pool({
  connectionString: process.env.DATABASE_URL_READWRITE,
  // Uses a PostgreSQL role with SELECT, INSERT, UPDATE, DELETE grants
});
```

The public server only has access to `readPool` in its environment. The admin server has both. This is defense in depth: even if a bug in a public tool somehow tried to execute a write query, the database connection would reject it.

---

## Security Considerations

### Authentication

The public server requires no authentication. The admin server uses **OAuth 2.1** following the MCP specification's guidance that MCP servers act as OAuth 2.0 Resource Servers:

- The admin server publishes a `/.well-known/oauth-protected-resource` metadata document, identifying the authorization server and required scopes.
- MCP clients obtain tokens from the organization's identity provider (e.g., Okta, Auth0, or an internal IdP).
- The admin server validates access tokens on every request, checking signature, expiry, audience, and the `resource` indicator per RFC 8707.
- Tokens are short-lived (15-minute access tokens with refresh tokens for longer sessions).

### Authorization (Role-Based)

Authentication tells you *who* is calling; authorization tells you *what they can do*. The admin server enforces role-based access control internally:

| Role | Permissions |
|------|------------|
| `alert_publisher` | Create and update service alerts |
| `schedule_manager` | Modify route schedules |
| `fare_admin` | Update fare rules |
| `analytics_viewer` | Access ridership reports |
| `super_admin` | All of the above |

Roles are encoded as claims in the OAuth token or looked up from an internal directory. Each admin tool checks the caller's roles before executing.

### Rate Limiting

Even though the public server has no authentication, it must protect itself from abuse:

- **Per-IP rate limiting** on the public server (e.g., 100 requests per minute per IP).
- **Per-token rate limiting** on the admin server (e.g., 500 requests per minute per token).
- Rate limit headers returned on every response so clients can self-throttle.
- Graduated backoff: soft limits return 429 with a `Retry-After` header; hard limits (10x the soft limit) result in temporary IP/token bans.

### Input Validation

Both servers use **Zod schemas** (as shown in the tool definitions) to validate all inputs before they reach the data layer. This is the first line of defense against injection attacks and malformed data.

Additional validation at the data layer:

- Parameterized queries only -- no string interpolation in SQL.
- Date range queries capped to prevent resource exhaustion (e.g., max 90-day window for analytics).
- String length limits on all text fields.
- Enumerated values enforced at the schema level (severity, transport type, passenger type).

### Audit Logging

Every write operation on the admin server is recorded in an append-only audit log:

```typescript
interface AuditEntry {
  timestamp: string;      // ISO 8601
  user_id: string;        // From OAuth token
  action: string;         // Tool name
  parameters: object;     // Sanitized input (no secrets)
  result: "success" | "failure";
  ip_address: string;
  token_jti: string;      // JWT ID for traceability
}
```

Audit logs are stored separately from the application database and are immutable. They enable post-incident investigation and compliance reporting.

### Transport Security

- Both servers communicate over HTTPS only. The MCP SDK automatically upgrades HTTP to HTTPS.
- The admin server additionally supports mutual TLS (mTLS) for machine-to-machine integrations where an AI agent operates on behalf of a service account rather than a human.

---

## Deployment and Operational Concerns

### Separate Deployments

The two servers should be deployed as **independent services** with separate scaling, monitoring, and failure domains:

```
                    +------------------+
  Public clients -->| Load Balancer    |
                    | (no auth check)  |
                    +--------+---------+
                             |
                    +--------v---------+
                    | citytransit-     |
                    | public-mcp       |
                    | (read-only DB)   |
                    +--------+---------+
                             |
                    +--------v---------+
                    |   PostgreSQL     |
                    |   (read replica) |
                    +------------------+

                    +------------------+
  Admin clients --->| Load Balancer    |
                    | (OAuth token     |
                    |  pre-validation) |
                    +--------+---------+
                             |
                    +--------v---------+
                    | citytransit-     |
                    | admin-mcp        |
                    | (read/write DB)  |
                    +--------+---------+
                             |
                    +--------v---------+
                    |   PostgreSQL     |
                    |   (primary)      |
                    +------------------+
```

Key deployment decisions:

- **Public server** connects to a **read replica** of the database, providing natural isolation. Heavy public query traffic cannot degrade write performance for admins.
- **Admin server** connects to the **primary** database for write operations and can also read from it directly (or from a replica for analytics queries that tolerate slight lag).
- Each server has its own container image, scaling policy, and health checks.
- The public server can scale horizontally without limit since it is stateless and read-only. The admin server scales more conservatively because write operations must be serialized at the database level.

### Environment Isolation

```
Environment     Public MCP              Admin MCP
-----------     ----------              ---------
Production      public.mcp.citytransit  admin.mcp.citytransit
Staging         public.stg.citytransit  admin.stg.citytransit
Development     localhost:3100          localhost:3200
```

Staging environments use a separate database snapshot, refreshed nightly. Developers run both servers locally against a Docker-composed PostgreSQL instance with seed data.

### Monitoring and Alerting

Both servers emit structured logs and metrics:

- **Public server metrics**: request rate, latency percentiles (p50/p95/p99), error rate, cache hit ratio, rate-limit rejections per minute.
- **Admin server metrics**: all of the above plus write operation counts by type, authentication failures, authorization denials, audit log volume.
- Alert on: error rate exceeding 1% over 5 minutes, p99 latency exceeding 2 seconds, any authorization denial spike (possible credential compromise), audit log write failures.

### Versioning and Backwards Compatibility

Both servers follow semantic versioning. The `name` and `version` fields in the MCP server metadata allow clients to detect capabilities:

- Public server versions increment independently of the admin server.
- When a breaking change is needed (removing a tool, changing a parameter), the old version runs in parallel for a deprecation period.
- The shared data package version is pinned in both servers' dependencies, and updates are coordinated.

### Secret Management

Following MCP security best practices, credentials are never stored in code or configuration files:

- Database connection strings are injected via environment variables from a secrets manager (e.g., AWS Secrets Manager, HashiCorp Vault).
- OAuth signing keys are rotated automatically.
- The public server has minimal secrets (just the read-only database URL). The admin server has more (read-write database URL, audit log credentials, IdP configuration), so its deployment pipeline has stricter access controls.

---

## Summary

The dual MCP server pattern -- one public, one admin -- is a natural fit for data-backed applications where the same underlying data needs both broad read access and controlled write access. The key architectural principles are:

1. **Share the data layer, separate the tool surfaces.** Both servers use the same models and queries, but admin tools exist only in the admin server's codebase.
2. **Enforce access boundaries at multiple levels.** Database connection roles, OAuth token validation, and role-based tool-level checks all reinforce each other.
3. **Deploy independently.** Separate scaling, separate failure domains, separate database connections (read replica vs. primary).
4. **Audit everything on the write path.** Every admin action is logged with the actor, action, parameters, and outcome.
5. **Validate all inputs regardless of trust level.** Zod schemas on every tool, parameterized queries in the data layer, and rate limiting on both servers.

This approach lets the transit authority confidently expose their data to the broader AI ecosystem through the public MCP while maintaining tight control over operational changes through the admin MCP.

---

*Sources:*
- [MCP Authorization Specification](https://modelcontextprotocol.io/docs/tutorials/security/authorization)
- [MCP Authentication and Authorization Guide (Stytch)](https://stytch.com/blog/MCP-authentication-and-authorization-guide/)
- [MCP Spec Updates from June 2025 (Auth0)](https://auth0.com/blog/mcp-specs-update-all-about-auth/)
- [OWASP Practical Guide for Secure MCP Server Development](https://genai.owasp.org/resource/a-practical-guide-for-secure-mcp-server-development/)
- [MCP Authorization with Fine-Grained Access Control (Cerbos)](https://www.cerbos.dev/blog/mcp-authorization)
- [Authorization for MCP: OAuth 2.1 and Best Practices (Oso)](https://www.osohq.com/learn/authorization-for-ai-agents-mcp-oauth-21)
- [MCP Server Best Practices for 2026 (CData)](https://www.cdata.com/blog/mcp-server-best-practices-2026)
- [TypeScript MCP SDK (GitHub)](https://github.com/modelcontextprotocol/typescript-sdk)
- [Best Practices for Securing Credentials in MCP Servers](https://securityboulevard.com/2026/03/best-practices-for-securing-credentials-in-mcp-servers/)
