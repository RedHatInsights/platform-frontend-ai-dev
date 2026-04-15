export interface SlackNotification {
  event_type: string;
  message: string;
  sent_at: string;
}

export interface Task {
  id: number;
  jira_key: string;
  status: 'in_progress' | 'pr_open' | 'pr_changes' | 'paused' | 'done';
  repo: string;
  branch: string;
  pr_number: number | null;
  pr_url: string | null;
  title: string | null;
  summary: string | null;
  created_at: string;
  last_addressed: string;
  paused_reason: string | null;
  metadata: Record<string, any>;
  slack_notification?: SlackNotification;
}

export interface Memory {
  id: number;
  category: string;
  repo: string;
  jira_key: string | null;
  title: string;
  content: string;
  tags: string[];
  created_at: string;
  metadata: Record<string, any>;
  similarity?: number;
}

export interface BotStatus {
  state: 'working' | 'idle' | 'error' | 'unknown';
  message: string;
  jira_key: string | null;
  repo: string | null;
  cycle_start: string | null;
  updated_at: string;
}

export interface CycleEntry {
  id: number;
  timestamp: string;
  label: string;
  session_id: string;
  num_turns: number;
  duration_ms: number;
  cost_usd: number;
  input_tokens: number;
  output_tokens: number;
  cache_read_tokens: number;
  cache_write_tokens: number;
  model: string;
  is_error: boolean;
  no_work: boolean;
  jira_key: string | null;
  repo: string | null;
  work_type: string | null;
  summary: string | null;
}

export interface DailyAggregate {
  day: string;
  cycles: number;
  total_cost: number;
  input_tokens: number;
  output_tokens: number;
  cache_read: number;
  cache_write: number;
  total_duration: number;
  total_turns: number;
  idle_cycles: number;
  error_cycles: number;
}

export interface EmbeddingPoint {
  id: number;
  title: string;
  content: string;
  category: string;
  repo: string;
  tags: string[];
  x: number;
  y: number;
  z: number;
}

export interface WSEvent {
  type: string;
  data: any;
  timestamp: number;
}

export interface AnalyticsSummary {
  total_cycles: number;
  work_cycles: number;
  idle_cycles: number;
  error_cycles: number;
  unique_tickets: number;
  total_cost: number;
  avg_cost_per_work_cycle: number;
  avg_turns: number;
  avg_duration_ms: number;
  repos_touched: number;
  tickets_resolved: number;
}

export interface WorkTypeEntry {
  category: string;
  cycles: number;
  total_cost: number;
  avg_cost: number;
  avg_turns: number;
  avg_duration_ms: number;
}

export interface RepoEntry {
  repo: string;
  tickets: number;
  cycles: number;
  total_cost: number;
  avg_turns: number;
}

export interface TicketEntry {
  jira_key: string;
  title: string | null;
  status: string | null;
  repo: string | null;
  total_cycles: number;
  impl_cycles: number;
  review_cycles: number;
  total_cost: number;
  hours_span: number;
}

export interface FeedbackStats {
  avg_review_rounds: number;
  zero_review: number;
  one_review: number;
  multi_review: number;
}

export interface AnalyticsData {
  summary: AnalyticsSummary;
  work_types: WorkTypeEntry[];
  repos: RepoEntry[];
  tickets: TicketEntry[];
  feedback: FeedbackStats;
}
