import { prisma } from '../../config/database';
import { NotFoundError } from '../../lib/errors';
import { PaginationParams, paginateResults, buildCursorWhere } from '../../lib/pagination';
import { CreateClientInput, UpdateClientInput } from './clients.validators';

export async function list(companyId: string, pagination: PaginationParams) {
  const { cursor, pageSize = 25 } = pagination;

  const clients = await prisma.client.findMany({
    where: { companyId },
    orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
    take: pageSize + 1,
    ...buildCursorWhere(cursor),
  });

  return paginateResults(clients, pageSize);
}

export async function getById(id: string, companyId: string) {
  const client = await prisma.client.findFirst({
    where: { id, companyId },
  });

  if (!client) {
    throw new NotFoundError('Client', id);
  }

  return client;
}

export async function create(companyId: string, data: CreateClientInput) {
  const client = await prisma.client.create({
    data: {
      companyId,
      name: data.name,
      email: data.email ?? null,
      phone: data.phone ?? null,
      address: data.address ?? null,
      city: data.city ?? null,
      state: data.state ?? null,
      zip: data.zip ?? null,
      notes: data.notes ?? null,
    },
  });

  return client;
}

export async function update(id: string, companyId: string, data: UpdateClientInput) {
  // Verify the client belongs to the company
  const existing = await prisma.client.findFirst({
    where: { id, companyId },
  });

  if (!existing) {
    throw new NotFoundError('Client', id);
  }

  const client = await prisma.client.update({
    where: { id },
    data: {
      ...(data.name !== undefined && { name: data.name }),
      ...(data.email !== undefined && { email: data.email }),
      ...(data.phone !== undefined && { phone: data.phone }),
      ...(data.address !== undefined && { address: data.address }),
      ...(data.city !== undefined && { city: data.city }),
      ...(data.state !== undefined && { state: data.state }),
      ...(data.zip !== undefined && { zip: data.zip }),
      ...(data.notes !== undefined && { notes: data.notes }),
    },
  });

  return client;
}

export async function remove(id: string, companyId: string) {
  const existing = await prisma.client.findFirst({
    where: { id, companyId },
  });

  if (!existing) {
    throw new NotFoundError('Client', id);
  }

  await prisma.client.delete({ where: { id } });
}
