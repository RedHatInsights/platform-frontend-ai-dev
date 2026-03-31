# Dev Bot (Rehor)

An autonomous developer agent that picks groomed Jira tickets, implements them, opens PRs, and maintains them through review — all without human intervention. It runs in a polling loop using Claude CLI and integrates with Jira, GitHub, and a persistent memory system.

## How it works

The bot operates in **cycles**. Each cycle, it evaluates all of its tracked work and acts on exactly one item, following a strict priority order. This ensures human feedback is never ignored and incomplete work is always finished before new work is started.

### Priority 0: Respond to feedback and finish incomplete work

The bot starts every cycle by checking its tracked tasks for anything that needs immediate attention:

1. **New feedback** — PR review comments, Jira comments, failing CI, or merge conflicts since the bot last addressed a task. Human feedback is always the highest priority.
2. **Interrupted work** — if the bot ran out of turns mid-implementation (branch created but no PR yet), it picks up where it left off using progress metadata it saved to its task tracker.
3. **Unfinished investigations** — investigation tickets where the analysis hasn't been posted to Jira yet.

### Priority 1: Maintain existing PRs

For each open PR, the bot checks (in order):
- **CI failures** — reads the failing check, fixes the code, pushes.
- **Merge conflicts** — rebases on the default branch and force-pushes.
- **Review feedback** — reads new GitHub review comments and PR comments, addresses each one, pushes, and replies.
- **Jira comments** — checks for stakeholder feedback on the linked ticket.
- **Merged PRs** — closes out the task, transitions the Jira ticket to Done, and saves what it learned to memory.

### Priority 1.5: Check assigned Jira tickets

Scans tickets assigned to the bot for merged PRs it hasn't noticed or new Jira comments that need a response.

### Priority 2: Pick new work

Only when everything is clean — no pending feedback, no interrupted work, all PRs green — the bot looks for new tickets:

1. Checks capacity (hard cap of 5 concurrent active tasks)
2. Searches memory for relevant past learnings
3. Queries Jira for unassigned, groomed tickets
4. Claims the ticket, creates a branch, implements, tests, opens a PR
5. Reports back on Jira

## Jira integration

Tickets must be explicitly groomed for the bot. The bot never picks random backlog items.

**Required labels:**
- A **primary label** (e.g. `hcc-ai-framework`, `hcc-ai-ui`) — marks the ticket as bot-eligible for a specific team. The bot is started with `--label <primary-label>` and only picks up tickets with that label.
- `repo:<name>` — identifies the target repo (must match a key in `project-repos.json`)

**Optional labels:**
- `needs-investigation` — bot investigates and reports findings instead of implementing
- `platform-experience-ui` — routes the ticket to the UI sprint instead of the framework sprint

The bot assigns itself, transitions the ticket to "In Progress", adds it to the active sprint, and moves it to "Code Review" when the PR is opened. When the PR merges, it moves the ticket to "Done".

### Grooming a ticket

There's an interactive grooming prompt that walks you through preparing a ticket for the bot. Run it from this repo:

```bash
claude --prompt-file prompts/groom.md
```

It will ask about the problem, help identify the right repos, suggest labels, and produce a ready-to-create ticket with a proper title, description, and acceptance criteria.

## Memory system

The bot has a persistent memory server (`memory-server/`) that provides two capabilities via MCP:

**Task tracking** — structured records of active work with status, PR links, branch names, and progress metadata. When the bot is interrupted mid-cycle (runs out of turns), it saves its progress (`last_step`, `next_step`, `files_changed`) so the next cycle can resume seamlessly.

**RAG memory** — a vector-searchable knowledge base where the bot stores learnings from completed tickets, PR review feedback, and codebase patterns. Before starting any new ticket, it searches this memory for relevant past experience. This means the bot gets better over time — it won't repeat the same mistakes or miss patterns it has already learned.

The memory server includes a web dashboard at `http://localhost:8080` with:
- Task and memory browsing with detail panels
- Semantic search over stored memories
- 3D embedding visualization (PCA-projected)
- Live WebSocket updates with toast notifications when the bot modifies data

## Personas

Each repo is assigned a persona (`frontend`, `backend`, `operator`, `config`, `cve`) that provides repo-specific guidelines. Personas live in `personas/<type>/prompt.md` and may include MCP server configs for specialized tools (e.g. PatternFly component docs for frontend repos).

## Visual verification

For UI changes, the bot starts the dev server, navigates to the affected page using chrome-devtools MCP, and takes before/after screenshots. Screenshots are never committed to the repo — they are base64-encoded and embedded as `<img>` tags in the PR description.

## Structure

```
dev-bot/
  run.sh                 # Polling loop — launches Claude CLI each cycle
  init.sh                # Installs LSP, starts memory server
  config.json            # Model, polling intervals, Jira config
  project-repos.json     # repo label -> git URL + persona mapping
  CLAUDE.md              # Full agent instructions (the bot's brain)
  .mcp.json              # MCP server connections (Jira, memory, browser)
  costs.sh               # Cost report script
  costs.jsonl            # Per-cycle cost records (auto-generated)
  bot.log                # Full cycle output log
  memory-server/         # Persistent memory + task tracking (Docker)
    src/
      server.py          # FastMCP + Starlette + WebSocket
      tools/             # MCP tools (task_*, memory_*)
      api.py             # REST API for the dashboard
      static/            # Dashboard UI (HTML/CSS/JS + Three.js)
    docker-compose.yml   # PostgreSQL (pgvector) + memory server
  personas/
    frontend/            # React/TS/PatternFly guidelines + MCP
    backend/             # Go/Node backend guidelines
    operator/            # Kubernetes operator guidelines
    config/              # Config repo guidelines
    cve/                 # CVE remediation guidelines
  repos/                 # Cloned target repos (created on demand by the bot)
```

## Prerequisites

- [Claude Code](https://claude.ai/code) installed and authenticated
- `gh` CLI authenticated with GitHub
- `glab` CLI authenticated with GitLab (for GitLab repos like app-interface)
- SSH access to target repos
- Docker (for the memory server)
- Jira MCP server configured (`mcp-atlassian`)
- Node.js + npm (for TypeScript LSP)
- `jq`

## Setup

```bash
# Initialize (installs LSP, starts memory server)
./init.sh

# Run the bot for a specific team
./run.sh --label hcc-ai-framework
```

## Adding a new repo

1. Add to `project-repos.json`:
   ```json
   "my-repo": {
     "url": "git@github.com:RedHatInsights/my-repo.git",
     "persona": "frontend"
   }
   ```
2. Add a `repo:my-repo` label to the Jira ticket

The bot will clone the repo automatically when it picks up a ticket with that label.

### Fork repos

If the bot doesn't have push access to the upstream repo, use a fork. Set `url` to the fork and add an `upstream` field pointing to the original:

```json
"app-interface": {
  "url": "git@gitlab.cee.redhat.com:mmarosi/app-interface.git",
  "upstream": "git@gitlab.cee.redhat.com:service/app-interface.git",
  "persona": "config",
  "host": "gitlab"
}
```

The bot will clone from the fork, sync from upstream, push branches to the fork, and open MRs targeting the upstream repo.

## Running everything

### 1. Memory server + dashboard

The memory server runs as two Docker containers (PostgreSQL + Python app). `init.sh` starts them automatically, but you can also manage them directly:

```bash
cd memory-server

# Start (builds if needed)
docker compose up -d --build

# Check logs
docker compose logs -f memory-server

# Stop
docker compose down

# Reset database (wipe all data)
docker compose down -v && docker compose up -d --build
```

Dashboard is at **http://localhost:8080**. It shows tasks, memories, semantic search, and a 3D embedding map. Live updates via WebSocket — you'll see toast notifications when the bot creates or updates entries.

To seed the database with example data from past work:

```bash
cd memory-server
docker compose exec memory-server uv run python seed_from_json.py
```

### 2. Browser for visual verification

The bot uses chrome-devtools MCP to take screenshots of UI changes. Start a Chromium/Chrome instance with remote debugging enabled:

```bash
./start-chromium.sh
```

This launches Chrome on port 9222 with a separate profile (won't interfere with your normal browser). The `.mcp.json` is already configured to connect to it:

```json
"chrome-devtools": {
  "command": "npx",
  "args": ["chrome-devtools-mcp@latest", "--browserUrl", "http://127.0.0.1:9222"]
}
```

If you're using Chromium instead of Chrome, edit `start-chromium.sh` and replace `google-chrome` with `chromium` or `chromium-browser`.

### 3. Run the bot

```bash
# Full init first (installs LSP, starts memory server)
./init.sh

# Start the polling loop for a specific team
./run.sh --label hcc-ai-framework
```

The bot logs to `bot.log` and stdout. Each cycle it:
1. Launches Claude CLI with the full tool set (Jira, GitHub, memory, browser, LSP)
2. Claude reads `CLAUDE.md` and follows the workflow
3. When the cycle completes, it sleeps for 5 minutes (or 1 hour if no work was found)

To run a single cycle manually (useful for testing):

```bash
claude --print \
  --max-turns 100 \
  --model claude-opus-4-6 \
  --allowedTools "Edit" "Write" "Read" "Glob" "Grep" "Bash" "LSP" \
    "mcp__mcp-atlassian__jira_*" \
    "mcp__chrome-devtools__*" \
    "mcp__bot-memory__*" \
  -- "Your primary label is: hcc-ai-framework. Follow the instructions in CLAUDE.md."
```

### 4. Configuration

`config.json` controls the bot's behavior:

```json
{
  "claude": {
    "maxTurns": 100,        // Max tool calls per cycle
    "model": "claude-opus-4-6"
  },
  "polling": {
    "intervalSeconds": 300,     // 5 min between cycles when there's work
    "idleIntervalSeconds": 3600 // 1 hour when no work is found
  }
}
```

MCP servers are configured in `.mcp.json` (project-level) and `personas/*/mcp.json` (per-persona tools like PatternFly docs).

## Cost tracking

Each bot cycle records its cost to `costs.jsonl` — tokens used, duration, model, and USD cost extracted from Claude CLI's stream-json output.

```bash
# View all recorded cycles
./costs.sh

# Today's cycles only
./costs.sh today

# Specific date
./costs.sh 2026-03-31

# Last 7 days
./costs.sh week

# Backfill from bot.log (if costs.jsonl is missing or you want to import historical data)
./costs.sh backfill
```

Each entry in `costs.jsonl` is a JSON object:

```json
{
  "timestamp": "2026-03-31T12:00:00+00:00",
  "label": "hcc-ai-framework",
  "session_id": "...",
  "num_turns": 28,
  "duration_ms": 179225,
  "cost_usd": 1.38,
  "input_tokens": 40,
  "output_tokens": 5074,
  "cache_read_tokens": 1579336,
  "cache_write_tokens": 74519,
  "model": "claude-opus-4-6",
  "is_error": false,
  "no_work": false
}
```

## Example

- Jira ticket: [RHCLOUD-46011](https://redhat.atlassian.net/browse/RHCLOUD-46011)
- PR created by the bot: [astro-virtual-assistant-frontend#368](https://github.com/RedHatInsights/astro-virtual-assistant-frontend/pull/368)
