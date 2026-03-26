import { ActivityLogEntry } from '@prisma/client';

export interface ActivityDto {
  id: string;
  project_id: string;
  user_id: string | null;
  action: string;
  description: string;
  created_at: string;
}

export function toActivityDto(entry: ActivityLogEntry): ActivityDto {
  return {
    id: entry.id,
    project_id: entry.projectId,
    user_id: entry.userId,
    action: entry.action.toLowerCase(),
    description: entry.description,
    created_at: entry.createdAt.toISOString(),
  };
}
