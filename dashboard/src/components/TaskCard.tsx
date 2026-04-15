import type { Task } from '../types';
import { timeAgo, JIRA_BASE } from '../utils';

interface Props {
  task: Task;
  selected?: boolean;
  onClick?: () => void;
}

const statusLabels: Record<string, string> = {
  in_progress: 'In Progress',
  pr_open: 'PR Open',
  pr_changes: 'Changes Requested',
  done: 'Done',
  paused: 'Paused',
  archived: 'Archived',
};

export default function TaskCard({ task, selected, onClick }: Props) {
  const step = task.metadata?.last_step;

  return (
    <div
      className={`task-card status-${task.status}${selected ? ' selected' : ''}`}
      onClick={onClick}
    >
      <div className="task-card-header">
        <a
          href={JIRA_BASE + task.jira_key}
          target="_blank"
          rel="noopener noreferrer"
          className="task-jira-key"
          onClick={(e) => e.stopPropagation()}
        >
          {task.jira_key}
        </a>
        <span className={`status-badge ${task.status}`}>
          {statusLabels[task.status] || task.status}
        </span>
      </div>
      {task.title && <div className="task-card-title">{task.title}</div>}
      <div className="task-card-meta">
        <span className="task-repo">{task.repo}</span>
        {task.pr_number && (
          <a
            href={task.pr_url || '#'}
            target="_blank"
            rel="noopener noreferrer"
            className="task-pr"
            onClick={(e) => e.stopPropagation()}
          >
            PR #{task.pr_number}
          </a>
        )}
        <span className="task-created" title={task.created_at}>
          {timeAgo(task.created_at)}
        </span>
        {task.last_addressed && (
          <span className="task-activity" title={task.last_addressed}>
            active {timeAgo(task.last_addressed)}
          </span>
        )}
      </div>
      {step && <div className="task-step">Step: {step}</div>}
      {task.paused_reason && (
        <div className="task-paused-reason">{task.paused_reason}</div>
      )}
      {task.slack_notification && (
        <div className="task-slack-notif" title={`${task.slack_notification.event_type}: ${task.slack_notification.message}`}>
          <span className="slack-icon">🔔</span>
          <span className="slack-event">{task.slack_notification.event_type.replace(/_/g, ' ')}</span>
          <span className="slack-time">{timeAgo(task.slack_notification.sent_at)}</span>
        </div>
      )}
    </div>
  );
}
