import { prisma } from '../../config/database';
import { NotFoundError } from '../../lib/errors';
import { UpdateUserInput } from './users.validators';

export async function getMe(userId: string) {
  const user = await prisma.user.findUnique({
    where: { id: userId },
  });

  if (!user) {
    throw new NotFoundError('User', userId);
  }

  return user;
}

export async function updateMe(userId: string, data: UpdateUserInput) {
  const existing = await prisma.user.findUnique({ where: { id: userId } });
  if (!existing) throw new NotFoundError('User', userId);

  const updateData: Record<string, unknown> = {};
  if (data.full_name !== undefined) updateData.fullName = data.full_name;
  if (data.phone !== undefined) updateData.phone = data.phone;
  if (data.avatar_url !== undefined) updateData.avatarUrl = data.avatar_url;

  return prisma.user.update({ where: { id: userId }, data: updateData });
}
