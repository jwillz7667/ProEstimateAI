import { Asset } from '@prisma/client';

export interface AssetDto {
  id: string;
  project_id: string;
  url: string;
  thumbnail_url: string | null;
  asset_type: string;
  sort_order: number;
  created_at: string;
}

export function toAssetDto(asset: Asset): AssetDto {
  return {
    id: asset.id,
    project_id: asset.projectId,
    url: asset.url,
    thumbnail_url: asset.thumbnailUrl,
    asset_type: asset.assetType.toLowerCase(),
    sort_order: asset.sortOrder,
    created_at: asset.createdAt.toISOString(),
  };
}
