import { Prisma } from "@prisma/client";
import { prisma } from "../../config/database";
import { NotFoundError } from "../../lib/errors";
import {
  PaginationParams,
  paginateResults,
  buildCursorWhere,
} from "../../lib/pagination";
import { CreateClientInput, UpdateClientInput } from "./clients.validators";

const ENTITY_TYPE = "Client";

export async function list(companyId: string, pagination: PaginationParams) {
  const { cursor, pageSize = 25 } = pagination;

  const clients = await prisma.client.findMany({
    where: { companyId },
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
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
    throw new NotFoundError("Client", id);
  }

  return client;
}

export async function create(
  companyId: string,
  userId: string,
  data: CreateClientInput,
) {
  return prisma.$transaction(async (tx) => {
    const client = await tx.client.create({
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

    await tx.activityLogEntry.create({
      data: {
        companyId,
        userId,
        action: "CREATED",
        description: `Client ${client.name} created`,
        entityType: ENTITY_TYPE,
        entityId: client.id,
      },
    });

    return client;
  });
}

export async function update(
  id: string,
  companyId: string,
  userId: string,
  data: UpdateClientInput,
) {
  return prisma.$transaction(async (tx) => {
    const existing = await tx.client.findFirst({ where: { id, companyId } });
    if (!existing) {
      throw new NotFoundError("Client", id);
    }

    const updateData: Prisma.ClientUpdateInput = {};
    const changed: string[] = [];

    if (data.name !== undefined && data.name !== existing.name) {
      updateData.name = data.name;
      changed.push("name");
    }
    if (data.email !== undefined && data.email !== existing.email) {
      updateData.email = data.email;
      changed.push("email");
    }
    if (data.phone !== undefined && data.phone !== existing.phone) {
      updateData.phone = data.phone;
      changed.push("phone");
    }
    if (data.address !== undefined && data.address !== existing.address) {
      updateData.address = data.address;
      changed.push("address");
    }
    if (data.city !== undefined && data.city !== existing.city) {
      updateData.city = data.city;
      changed.push("city");
    }
    if (data.state !== undefined && data.state !== existing.state) {
      updateData.state = data.state;
      changed.push("state");
    }
    if (data.zip !== undefined && data.zip !== existing.zip) {
      updateData.zip = data.zip;
      changed.push("zip");
    }
    if (data.notes !== undefined && data.notes !== existing.notes) {
      updateData.notes = data.notes;
      changed.push("notes");
    }

    if (changed.length === 0) {
      return existing;
    }

    const client = await tx.client.update({
      where: { id },
      data: updateData,
    });

    await tx.activityLogEntry.create({
      data: {
        companyId,
        userId,
        action: "UPDATED",
        description: `Client ${client.name} updated (${changed.join(", ")})`,
        entityType: ENTITY_TYPE,
        entityId: client.id,
        metadataJson: { changed_fields: changed },
      },
    });

    return client;
  });
}

export async function remove(id: string, companyId: string, userId: string) {
  return prisma.$transaction(async (tx) => {
    const existing = await tx.client.findFirst({ where: { id, companyId } });
    if (!existing) {
      throw new NotFoundError("Client", id);
    }

    await tx.client.delete({ where: { id } });

    await tx.activityLogEntry.create({
      data: {
        companyId,
        userId,
        action: "UPDATED",
        description: `Client ${existing.name} deleted`,
        entityType: ENTITY_TYPE,
        entityId: existing.id,
        metadataJson: { operation: "delete" },
      },
    });
  });
}
