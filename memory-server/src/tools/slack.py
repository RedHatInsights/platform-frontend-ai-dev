import json
import logging
import os
from datetime import datetime, timezone, timedelta
from typing import Optional

import httpx
from fastmcp import FastMCP

from ..db import get_pool
from ..events import Event, bus

logger = logging.getLogger(__name__)

COOLDOWN_HOURS = 48  # Don't re-notify same task+event_type within this window


def register_slack_tools(mcp: FastMCP):

    @mcp.tool()
    async def slack_notify(
        jira_key: str,
        event_type: str,
        message: str,
    ) -> dict:
        """Send a Slack notification. Deduplicates by jira_key + event_type (48h cooldown).

        event_type: 'pr_created', 'release_pending', 'needs_help', 'infra_error', 'review_reminder'.
        message: Human-readable message to post. Keep it concise (1-2 sentences + links).

        Returns {"sent": true/false, "reason": "..."}.
        Skipped silently if cooldown active or webhook not configured."""
        pool = get_pool()
        webhook_url = os.environ.get("SLACK_WEBHOOK_URL")

        if not webhook_url:
            return {"sent": False, "reason": "SLACK_WEBHOOK_URL not configured"}

        # Check cooldown — same jira_key + event_type within 48h
        cutoff = datetime.now(timezone.utc) - timedelta(hours=COOLDOWN_HOURS)
        recent = await pool.fetchrow(
            """
            SELECT id, sent_at FROM slack_notifications
            WHERE jira_key = $1 AND event_type = $2 AND sent_at > $3
            ORDER BY sent_at DESC LIMIT 1
            """,
            jira_key, event_type, cutoff,
        )

        if recent:
            return {
                "sent": False,
                "reason": f"Cooldown active — last {event_type} for {jira_key} sent {recent['sent_at'].isoformat()}",
            }

        # Send to Slack
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                resp = await client.post(webhook_url, json={"msg": message})
                resp.raise_for_status()
        except Exception as e:
            logger.error("Slack webhook failed: %s", e)
            return {"sent": False, "reason": f"Webhook error: {e}"}

        # Record notification
        await pool.execute(
            """
            INSERT INTO slack_notifications (jira_key, event_type, message)
            VALUES ($1, $2, $3)
            """,
            jira_key, event_type, message,
        )

        await bus.publish(Event("slack_notification", {
            "jira_key": jira_key,
            "event_type": event_type,
            "message": message,
        }))

        return {"sent": True, "reason": "ok"}
