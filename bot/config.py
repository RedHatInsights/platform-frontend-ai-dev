"""Configuration loading for the dev bot."""

import json
import os
import re
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Config:
    model: str
    max_turns: int
    interval: int
    idle_interval: int
    board_key: str


def load_config(script_dir: Path) -> Config:
    """Load bot configuration from config.json."""
    with open(script_dir / "config.json") as f:
        raw = json.load(f)
    return Config(
        model=raw["claude"]["model"],
        max_turns=raw["claude"]["maxTurns"],
        interval=raw["polling"]["intervalSeconds"],
        idle_interval=raw["polling"].get("idleIntervalSeconds", 3600),
        board_key=raw["jira"]["boardKey"],
    )


def load_mcp_servers(script_dir: Path) -> dict:
    """Load and merge MCP servers from bot and persona configs.

    The root .mcp.json (bot-memory, chrome-devtools) is loaded automatically
    by the SDK via setting_sources=["project"]. This function loads additional
    servers: bot-specific (bot/mcp.json for mcp-atlassian) and per-persona.
    """
    servers: dict = {}

    # Bot-specific MCP servers (e.g. mcp-atlassian — kept separate from
    # .mcp.json so it doesn't interfere with local dev sessions)
    bot_mcp = script_dir / "bot" / "mcp.json"
    if bot_mcp.exists():
        with open(bot_mcp) as f:
            data = json.load(f)
        for name, cfg in data.get("mcpServers", {}).items():
            servers[name] = _resolve_env_vars(cfg)

    for mcp_file in sorted(script_dir.glob("personas/*/mcp.json")):
        with open(mcp_file) as f:
            data = json.load(f)
        for name, cfg in data.get("mcpServers", {}).items():
            servers[name] = _resolve_env_vars(cfg)
    return servers


def _resolve_env_vars(obj):
    """Recursively resolve ${VAR} references in MCP server configs.

    This lets us remove secrets from os.environ before starting the agent
    while still passing them to MCP servers via resolved literal values.
    """
    if isinstance(obj, str):
        return re.sub(
            r"\$\{(\w+)\}",
            lambda m: os.environ.get(m.group(1), ""),
            obj,
        )
    if isinstance(obj, dict):
        return {k: _resolve_env_vars(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_resolve_env_vars(v) for v in obj]
    return obj


# Env vars that contain secrets and must be removed before starting
# the agent. MCP servers get resolved values; gh/glab use config files.
SECRET_ENV_VARS = [
    "JIRA_API_TOKEN",
    "GH_TOKEN",
    "GITHUB_TOKEN",
    "GITLAB_TOKEN",
    "SSH_PRIVATE_KEY_B64",
    "GPG_PRIVATE_KEY_B64",
    "GOOGLE_SA_KEY_B64",
    "BOT_SSH_KEY",
    "GITLAB_SSH_KEY",
    "GITLAB_SSH_KEY_B64",
    "GPG_SIGNING_KEY",
]


def sanitize_env() -> None:
    """Remove secret env vars so Bash subprocesses can't leak them.

    Call this AFTER load_mcp_servers() (which resolves ${VAR} references)
    and after gh/glab auth setup (which writes tokens to config files).
    """
    for var in SECRET_ENV_VARS:
        os.environ.pop(var, None)


ALLOWED_TOOLS = [
    # Built-in tools
    "Edit", "Write", "Read", "Glob", "Grep", "Bash", "LSP",
    # Jira MCP tools
    "mcp__mcp-atlassian__jira_search",
    "mcp__mcp-atlassian__jira_get_issue",
    "mcp__mcp-atlassian__jira_add_comment",
    "mcp__mcp-atlassian__jira_update_issue",
    "mcp__mcp-atlassian__jira_get_transitions",
    "mcp__mcp-atlassian__jira_transition_issue",
    "mcp__mcp-atlassian__jira_get_user_profile",
    "mcp__mcp-atlassian__jira_download_attachments",
    "mcp__mcp-atlassian__jira_get_agile_boards",
    "mcp__mcp-atlassian__jira_get_sprints_from_board",
    "mcp__mcp-atlassian__jira_add_issues_to_sprint",
    "mcp__mcp-atlassian__jira_create_issue",
    "mcp__mcp-atlassian__jira_create_issue_link",
    "mcp__mcp-atlassian__jira_get_field_options",
    # Wildcard MCP tools
    "mcp__hcc-patternfly-data-view__*",
    "mcp__chrome-devtools__*",
    "mcp__bot-memory__*",
]
