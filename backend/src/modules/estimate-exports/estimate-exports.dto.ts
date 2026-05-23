import { env } from '../../config/env';

export interface EstimateExportDto {
  id: string;
  estimate_id: string;
  project_id: string;
  file_name: string;
  content_type: string;
  file_size: number;
  download_url: string;
  created_at: string;
}

interface EstimateExportRecord {
  id: string;
  estimateId: string;
  projectId: string;
  fileName: string;
  contentType: string;
  fileSize: number;
  createdAt: Date;
}

export function toEstimateExportDto(record: EstimateExportRecord): EstimateExportDto {
  return {
    id: record.id,
    estimate_id: record.estimateId,
    project_id: record.projectId,
    file_name: record.fileName,
    content_type: record.contentType,
    file_size: record.fileSize,
    download_url: `${env.API_BASE_URL}/v1/estimate-exports/${record.id}/file`,
    created_at: record.createdAt.toISOString(),
  };
}
