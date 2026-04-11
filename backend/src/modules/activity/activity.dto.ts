import { ActivityLogEntry } from '@prisma/client';

export interface ActivityDto {
  id: string;
  project_id: string | null;
  user_id: string | null;
  company_id: string | null;
  action: string;
  description: string;
  entity_type: string | null;
  entity_id: string | null;
  created_at: string;
}

export function toActivityDto(entry: ActivityLogEntry): ActivityDto {
  return {
    id: entry.id,
    project_id: entry.projectId,
    user_id: entry.userId,
    company_id: entry.companyId,
    action: entry.action.toLowerCase(),
    description: entry.description,
    entity_type: entry.entityType,
    entity_id: entry.entityId,
    created_at: entry.createdAt.toISOString(),
  };
}
