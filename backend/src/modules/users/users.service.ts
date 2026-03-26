import { prisma } from '../../config/database';
import { NotFoundError } from '../../lib/errors';

export async function getMe(userId: string) {
  const user = await prisma.user.findUnique({
    where: { id: userId },
  });

  if (!user) {
    throw new NotFoundError('User', userId);
  }

  return user;
}
