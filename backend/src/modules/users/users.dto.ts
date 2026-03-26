import { User } from '@prisma/client';

export interface UserDto {
  id: string;
  company_id: string;
  email: string;
  full_name: string;
  role: string;
  avatar_url: string | null;
  phone: string | null;
  is_active: boolean;
  created_at: string;
}

export function toUserDto(user: User): UserDto {
  return {
    id: user.id,
    company_id: user.companyId,
    email: user.email,
    full_name: user.fullName,
    role: user.role.toLowerCase(),
    avatar_url: user.avatarUrl,
    phone: user.phone,
    is_active: user.isActive,
    created_at: user.createdAt.toISOString(),
  };
}
