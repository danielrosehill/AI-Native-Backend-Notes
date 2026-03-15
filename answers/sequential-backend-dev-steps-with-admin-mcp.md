# Sequential Order of Backend Development Operations with an Admin MCP Server

This walkthrough defines the logical step-by-step order for building a modern backend, using a **blog application** as a concrete example. The key departure from traditional practice is that the internal admin interface -- historically a web-based admin panel (think Django Admin, Rails Admin, Retool) -- is replaced by a **privileged MCP server** that exposes administrative operations as tools consumable by an AI agent.

---

## The Sequential Steps at a Glance

| Step | Operation | Output |
|------|-----------|--------|
| 1 | Domain modelling and schema definition | ERD, migration files |
| 2 | Database provisioning and migration | Running database with tables |
| 3 | Shared data-access layer | ORM models / query modules |
| 4 | Public API creation | REST or GraphQL endpoints for end users |
| 5 | Admin MCP server creation | MCP tools for privileged internal operations |
| 6 | Security, auth, and audit wiring | JWT/OAuth on API; scoped auth + logging on MCP |
| 7 | Deployment and runtime configuration | Containers, secrets, transport config |

Each step depends on what came before it. The rationale for this ordering is discussed within each section.

---

## Step 1: Domain Modelling and Schema Definition

Everything begins with the data model. Before you write a single line of server code, you need to know what you are storing and how entities relate.

### Blog App Example

For a blog platform, the core entities are:

- **User** -- authors and administrators
- **Post** -- the blog entries themselves
- **Tag** -- categorical labels for posts
- **Comment** -- reader responses on posts

A schema definition using a migration tool like Prisma:

```prisma
// schema.prisma

model User {
  id        Int      @id @default(autoincrement())
  email     String   @unique
  name      String
  role      Role     @default(AUTHOR)
  posts     Post[]
  createdAt DateTime @default(now())
}

enum Role {
  AUTHOR
  EDITOR
  ADMIN
}

model Post {
  id          Int       @id @default(autoincrement())
  title       String
  slug        String    @unique
  body        String
  status      PostStatus @default(DRAFT)
  author      User      @relation(fields: [authorId], references: [id])
  authorId    Int
  tags        Tag[]
  comments    Comment[]
  publishedAt DateTime?
  createdAt   DateTime  @default(now())
  updatedAt   DateTime  @updatedAt
}

enum PostStatus {
  DRAFT
  PUBLISHED
  ARCHIVED
}

model Tag {
  id    Int    @id @default(autoincrement())
  name  String @unique
  posts Post[]
}

model Comment {
  id        Int      @id @default(autoincrement())
  body      String
  authorName String
  post      Post     @relation(fields: [postId], references: [id])
  postId    Int
  approved  Boolean  @default(false)
  createdAt DateTime @default(now())
}
```

### Why This Comes First

The schema is the single source of truth. The public API, the admin MCP server, and all business logic derive from it. Changing the schema later forces changes everywhere downstream, so getting the domain model right (or at least directionally correct) is the highest-leverage early decision.

---

## Step 2: Database Provisioning and Migration

With the schema defined, you create the actual database and apply the schema to it.

```bash
# Provision a PostgreSQL database (local dev example)
createdb blog_app

# Apply the Prisma schema as a migration
npx prisma migrate dev --name init
```

This step produces:

- A running PostgreSQL (or SQLite, MySQL, etc.) instance with all tables created
- A migration history that can be replayed in staging and production
- A generated Prisma Client (or equivalent ORM client) for typed database access

### Why This Comes Second

You cannot write data-access code without a database to access. The migration step also validates that the schema is internally consistent (foreign keys resolve, unique constraints do not conflict, etc.).

---

## Step 3: Shared Data-Access Layer

Before building either the public API or the admin MCP server, you create a shared layer of data-access functions. This is critical because the public API and the admin MCP server both need to read and write the same data, and duplicating query logic across them is a maintenance hazard.

```typescript
// src/data/posts.ts
import { PrismaClient, PostStatus } from "@prisma/client";

const prisma = new PrismaClient();

export async function getPublishedPosts(page: number, pageSize: number) {
  return prisma.post.findMany({
    where: { status: PostStatus.PUBLISHED },
    include: { author: true, tags: true },
    orderBy: { publishedAt: "desc" },
    skip: (page - 1) * pageSize,
    take: pageSize,
  });
}

export async function createPost(data: {
  title: string;
  slug: string;
  body: string;
  authorId: number;
  tagIds?: number[];
}) {
  return prisma.post.create({
    data: {
      title: data.title,
      slug: data.slug,
      body: data.body,
      authorId: data.authorId,
      tags: data.tagIds
        ? { connect: data.tagIds.map((id) => ({ id })) }
        : undefined,
    },
  });
}

export async function bulkUpdatePostStatus(
  postIds: number[],
  status: PostStatus
) {
  return prisma.post.updateMany({
    where: { id: { in: postIds } },
    data: {
      status,
      publishedAt: status === PostStatus.PUBLISHED ? new Date() : undefined,
    },
  });
}

export async function moderateComments(
  commentIds: number[],
  approved: boolean
) {
  return prisma.comment.updateMany({
    where: { id: { in: commentIds } },
    data: { approved },
  });
}

export async function getAdminDashboardStats() {
  const [totalPosts, publishedPosts, pendingComments, totalUsers] =
    await Promise.all([
      prisma.post.count(),
      prisma.post.count({ where: { status: PostStatus.PUBLISHED } }),
      prisma.comment.count({ where: { approved: false } }),
      prisma.user.count(),
    ]);
  return { totalPosts, publishedPosts, pendingComments, totalUsers };
}
```

### Why This Comes Third

Both the API (Step 4) and the MCP server (Step 5) import from this layer. Building it before either consumer prevents logic duplication and ensures consistent behavior. This is the same principle Plural applies in production: their MCP servers "reuse existing business logic and database connections rather than duplicating functionality in separate admin interfaces."

---

## Step 4: Public API Creation

The public API serves external consumers: the blog frontend, mobile apps, third-party integrations. It exposes only the operations and data that unauthenticated or reader-authenticated users should access.

```typescript
// src/api/server.ts
import express from "express";
import { getPublishedPosts } from "../data/posts.js";
import { getPostBySlug, getPostComments } from "../data/posts.js";

const app = express();
app.use(express.json());

// Public: list published posts
app.get("/api/posts", async (req, res) => {
  const page = parseInt(req.query.page as string) || 1;
  const posts = await getPublishedPosts(page, 20);
  res.json({ posts, page });
});

// Public: get a single post by slug
app.get("/api/posts/:slug", async (req, res) => {
  const post = await getPostBySlug(req.params.slug);
  if (!post || post.status !== "PUBLISHED") {
    return res.status(404).json({ error: "Not found" });
  }
  res.json(post);
});

// Public: get approved comments for a post
app.get("/api/posts/:slug/comments", async (req, res) => {
  const comments = await getPostComments(req.params.slug, true);
  res.json(comments);
});

// Authenticated: submit a comment (rate-limited, validated)
app.post("/api/posts/:slug/comments", async (req, res) => {
  // Validation and rate limiting omitted for brevity
  const comment = await createComment({
    postSlug: req.params.slug,
    authorName: req.body.authorName,
    body: req.body.body,
  });
  res.status(201).json(comment);
});

app.listen(3000);
```

### What the Public API Does NOT Include

The public API deliberately excludes:

- Bulk post status changes (publish, archive, unpublish)
- Comment moderation (approve/reject)
- User management (role changes, account creation)
- Dashboard statistics
- Direct database queries or schema inspection

These are admin operations. In a traditional stack, you would build a separate admin panel (a web UI with its own routes, controllers, and frontend) to handle them. In the AI-native approach, the admin MCP server handles them instead.

### Why This Comes Fourth

The public API depends on the data-access layer (Step 3) and the database (Step 2). It does not depend on the admin MCP server, so it can be built and deployed independently.

---

## Step 5: Admin MCP Server Creation

This is the step that replaces the traditional admin backend. Instead of building an admin web panel with its own UI, routes, and controllers, you define an MCP server that exposes administrative operations as **tools** and administrative data as **resources**.

An AI agent (Claude, or any MCP-compatible client) can then invoke these tools via natural language, subject to authorization.

```typescript
// src/admin-mcp/server.ts
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import {
  bulkUpdatePostStatus,
  moderateComments,
  getAdminDashboardStats,
  createPost,
} from "../data/posts.js";
import { listUsers, updateUserRole } from "../data/users.js";

const server = new McpServer({
  name: "blog-admin",
  version: "1.0.0",
});

// --- RESOURCES (read-only data the agent can inspect) ---

server.resource("dashboard-stats", "admin://dashboard/stats", async (uri) => ({
  contents: [
    {
      uri: uri.href,
      mimeType: "application/json",
      text: JSON.stringify(await getAdminDashboardStats()),
    },
  ],
}));

server.resource("all-users", "admin://users", async (uri) => ({
  contents: [
    {
      uri: uri.href,
      mimeType: "application/json",
      text: JSON.stringify(await listUsers()),
    },
  ],
}));

// --- TOOLS (actions the agent can perform) ---

server.tool(
  "publish-posts",
  "Publish one or more draft posts by their IDs",
  { postIds: z.array(z.number()).min(1) },
  async ({ postIds }) => {
    const result = await bulkUpdatePostStatus(postIds, "PUBLISHED");
    return {
      content: [
        {
          type: "text",
          text: `Published ${result.count} post(s).`,
        },
      ],
    };
  }
);

server.tool(
  "archive-posts",
  "Archive one or more posts by their IDs",
  { postIds: z.array(z.number()).min(1) },
  async ({ postIds }) => {
    const result = await bulkUpdatePostStatus(postIds, "ARCHIVED");
    return {
      content: [
        {
          type: "text",
          text: `Archived ${result.count} post(s).`,
        },
      ],
    };
  }
);

server.tool(
  "moderate-comments",
  "Approve or reject comments by their IDs",
  {
    commentIds: z.array(z.number()).min(1),
    approved: z.boolean(),
  },
  async ({ commentIds, approved }) => {
    const result = await moderateComments(commentIds, approved);
    return {
      content: [
        {
          type: "text",
          text: `${approved ? "Approved" : "Rejected"} ${result.count} comment(s).`,
        },
      ],
    };
  }
);

server.tool(
  "change-user-role",
  "Change a user's role (AUTHOR, EDITOR, ADMIN)",
  {
    userId: z.number(),
    role: z.enum(["AUTHOR", "EDITOR", "ADMIN"]),
  },
  async ({ userId, role }) => {
    const user = await updateUserRole(userId, role);
    return {
      content: [
        {
          type: "text",
          text: `Updated ${user.name} to role ${role}.`,
        },
      ],
    };
  }
);

server.tool(
  "create-post",
  "Create a new blog post as a draft",
  {
    title: z.string(),
    slug: z.string(),
    body: z.string(),
    authorId: z.number(),
    tagIds: z.array(z.number()).optional(),
  },
  async (args) => {
    const post = await createPost(args);
    return {
      content: [
        {
          type: "text",
          text: `Created draft post "${post.title}" (ID: ${post.id}).`,
        },
      ],
    };
  }
);

// --- START ---
const transport = new StdioServerTransport();
await server.connect(transport);
```

### MCP Client Configuration

The admin MCP server is registered in the AI client's configuration. For Claude Code, this would go in the project's `.mcp.json`:

```json
{
  "mcpServers": {
    "blog-admin": {
      "command": "node",
      "args": ["src/admin-mcp/server.js"],
      "env": {
        "DATABASE_URL": "postgresql://admin:secret@localhost:5432/blog_app"
      }
    }
  }
}
```

### What This Replaces

In a traditional stack, the admin panel for this blog would require:

- A separate frontend (React/Vue admin dashboard, or a framework-provided admin like Django Admin)
- Admin-specific API routes (`/admin/posts`, `/admin/users`, `/admin/comments`)
- Admin controllers and middleware
- Admin authentication flows (separate login page, session management)
- UI components for tables, forms, bulk actions, dashboards

The MCP server eliminates all of that. An authorized operator opens their AI client and says:

> "Show me the dashboard stats, then approve all pending comments on post 42, and publish posts 15, 16, and 17."

The agent reads the `dashboard-stats` resource, then calls `moderate-comments` and `publish-posts` in sequence. No admin UI was built, maintained, or deployed.

### Why This Comes Fifth

The MCP server depends on the same data-access layer as the public API (Step 3). It is logically separate from the public API -- different consumers, different authorization model, different transport. Building it after the public API ensures the shared data layer is already battle-tested. However, there is no hard dependency between Steps 4 and 5; they could be built in parallel since both depend only on Steps 1-3.

---

## Step 6: Security, Authorization, and Audit Logging

Security is applied to both the public API and the admin MCP server, but with different models appropriate to each.

### Public API Security

Standard web API security: JWT or session-based auth for authenticated routes, rate limiting, input validation, CORS.

### Admin MCP Server Security

The MCP server requires a different, typically stricter, security model:

**Authentication:** JWT tokens with short lifespans (Plural uses ES256 JWTs with 15-minute expiry). The token contains the operator's identity and group memberships. The MCP server validates the token before executing any tool.

**Authorization:** Role-based or attribute-based access control on each tool. For example, only users with the `ADMIN` role can call `change-user-role`, while `EDITOR` can call `publish-posts` and `moderate-comments`.

```typescript
// Middleware-style authorization check within a tool handler
server.tool(
  "change-user-role",
  "Change a user's role",
  { userId: z.number(), role: z.enum(["AUTHOR", "EDITOR", "ADMIN"]) },
  async (args, context) => {
    const caller = await validateJwt(context.meta?.authToken);
    if (caller.role !== "ADMIN") {
      return {
        content: [{ type: "text", text: "Denied: ADMIN role required." }],
        isError: true,
      };
    }
    // proceed with operation...
  }
);
```

**Audit logging:** Every tool invocation is logged with the caller's identity, the tool name, the arguments, the result, and a timestamp. This is non-negotiable for a privileged server.

**Human-in-the-loop for destructive operations:** For actions like deleting a user or purging all comments, the MCP server should require explicit confirmation. MCP clients like Claude Code already support this pattern by prompting the user before executing tools.

### Why This Comes Sixth

Security is applied on top of working functionality. You need the API and MCP server to exist before you can wire authentication and authorization into them. In practice, you would design the security model earlier (during Step 1), but the implementation happens here.

---

## Step 7: Deployment and Runtime Configuration

The final step is deploying the system. The public API and the admin MCP server have different deployment characteristics.

### Public API

Deployed as a standard web service -- containerized, behind a load balancer, with horizontal scaling. Nothing unusual here.

### Admin MCP Server

The MCP server can be deployed in several ways depending on the transport:

- **Stdio transport (local):** The MCP server runs as a subprocess of the AI client. This is the simplest model and works well when the admin operator is a developer running Claude Code on their machine. The server has direct access to the database via the `DATABASE_URL` environment variable.

- **SSE or Streamable HTTP transport (remote):** The MCP server runs as a web service, accessible over HTTPS. This allows remote administration and is better suited for team environments. It requires the full authentication stack from Step 6.

```yaml
# docker-compose.yml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: blog_app
      POSTGRES_PASSWORD: secret
    volumes:
      - pgdata:/var/lib/postgresql/data

  api:
    build: .
    command: node src/api/server.js
    ports:
      - "3000:3000"
    environment:
      DATABASE_URL: postgresql://postgres:secret@postgres:5432/blog_app

  admin-mcp:
    build: .
    command: node src/admin-mcp/server.js
    ports:
      - "3001:3001"
    environment:
      DATABASE_URL: postgresql://postgres:secret@postgres:5432/blog_app
      MCP_TRANSPORT: sse
      AUTH_JWT_SECRET: ${JWT_SECRET}

volumes:
  pgdata:
```

---

## Summary: The Dependency Chain

```
Step 1: Schema Definition
   |
   v
Step 2: Database Provisioning + Migration
   |
   v
Step 3: Shared Data-Access Layer
   |
   +-----------+-----------+
   |                       |
   v                       v
Step 4: Public API    Step 5: Admin MCP Server
   |                       |
   +-----------+-----------+
               |
               v
      Step 6: Security + Audit
               |
               v
      Step 7: Deployment
```

Steps 4 and 5 are independent of each other and can be built in parallel. Everything else is strictly sequential. The critical insight is that Step 5 -- the admin MCP server -- occupies the same architectural position that a traditional admin panel would, but produces a fundamentally different artifact: a set of tool and resource definitions rather than a web UI. The admin's "interface" becomes whatever AI client the operator uses.

---

## Why Replace the Admin Panel with an MCP Server?

The practical benefits are significant:

1. **No frontend to build or maintain.** Admin panels are notoriously tedious to build and quick to become stale. The MCP server is pure backend logic with tool descriptions.

2. **Natural language as the interface.** Instead of navigating a dashboard to find the comment moderation page, filtering by status, selecting comments, and clicking "Approve," the operator says: "Approve all pending comments from the last 24 hours." The agent figures out the filtering and calls the tool.

3. **Composability.** An agent can chain multiple admin operations in a single conversation: "Show me posts with fewer than 100 views that are still published, archive them, and send me a summary." This would require custom UI work in a traditional admin panel.

4. **Audit logging is natural.** Every tool invocation is a discrete, logged event with structured parameters. Traditional admin panels often have patchy audit trails because logging must be manually added to each controller action.

5. **Reduced attack surface.** The MCP server can run on a private network or as a local subprocess, never exposed to the public internet. A web-based admin panel needs to be web-accessible, which means it needs its own authentication, CSRF protection, and hardening.

The tradeoff is that this approach requires operators who are comfortable interacting with AI agents rather than clicking through a GUI. For engineering teams and technical operators, this is increasingly the default mode of work.

---

## Sources

- [Plural: Replacing Admin Tools with AI Chat Interfaces via MCP](https://www.plural.sh/blog/how-plural-uses-mcp-replacing-admin-tools-with-ai-chat-interfaces/)
- [MCP Authorization: Securing MCP Servers with Fine-Grained Access Control (Cerbos)](https://www.cerbos.dev/blog/mcp-authorization)
- [Understanding Authorization in MCP (Official Docs)](https://modelcontextprotocol.io/docs/tutorials/security/authorization)
- [MCP TypeScript SDK (GitHub)](https://github.com/modelcontextprotocol/typescript-sdk)
- [How to Build a To-Do List MCP Server Using TypeScript (freeCodeCamp)](https://www.freecodecamp.org/news/how-to-build-a-to-do-list-mcp-server-using-typescript/)
- [MCP Security Risks and Mitigations (Red Hat)](https://www.redhat.com/en/blog/model-context-protocol-mcp-understanding-security-risks-and-controls)
