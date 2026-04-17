## RDS Blue-Green Upgrade Guidelines

Multi-step infra process across multiple cycles. Track progress in task metadata + summary. Each cycle picks up where the last left off.

### Overview

RDS EOL upgrades use blue-green deployments in app-interface. Stage needs 5 MRs, prod needs 6 (extra status page MR). Three phases: Preparation, Execution (maintenance window, strict order), Post-upgrade cleanup.

### MR Sequence — Stage

1. **Create blue-green deployment** — add `blue_green` section to RDS config
2. **Switchover** — update namespace `targetRevision` to point to green instance
3. **Replication slot check** — SQL query to verify no active replication slots
4. **Execute switchover** — trigger the blue-green cutover
5. **Cleanup** — remove blue-green config after successful switchover

### MR Sequence — Prod (same + status page)

1. **Status page maintenance** — create maintenance incident before window
2. **Create blue-green deployment**
3. **Switchover**
4. **Replication slot check**
5. **Execute switchover**
6. **Cleanup** — remove blue-green config + close status page incident

### Multi-Cycle Workflow

This is NOT a single-cycle task. Each MR may need review + merge before the next can be opened.

Track in `task_update` metadata:
```json
{
  "last_step": "stage_mr1_opened",
  "next_step": "wait_for_mr1_merge_then_open_mr2",
  "environment": "stage",
  "mrs_opened": [{"mr_number": 123, "phase": "blue_green_create", "status": "open"}],
  "mrs_remaining": ["switchover", "replication_check", "execute", "cleanup"]
}
```

Cycle behavior:
- **First cycle**: Read ticket comments for process details. Open first MR (blue-green create). Update task.
- **Subsequent cycles**: Check previous MR status. If merged → open next MR in sequence. If review feedback → address it. Update task metadata with progress.
- **Between phases**: Stage must complete before prod starts. Track `environment` in metadata.

### MR Content

Each MR modifies YAML files in `data/services/insights/` or related paths in app-interface. Follow existing patterns — find similar completed RDS upgrades via `git log` for reference.

Use conventional commits: `fix(app-interface): RDS blue-green create for <service> stage`

### Do NOT Skip These Tickets

RDS upgrade tickets are well-defined multi-step processes, not ambiguous infra work. The bot CAN handle them — each individual MR is a simple YAML change. The complexity is in sequencing, which task tracking handles.
