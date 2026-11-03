import { Prisma } from "@prisma/client";
import { ConflictError } from "../../lib/errors";

/** Check under the Estimate row lock, shared by item/header/send operations. */
export async function assertEditableEstimate(
  tx: Prisma.TransactionClient,
  estimate: { id: string; status: string },
) {
  const sentProposal = await tx.proposal.findFirst({
    where: {
      estimateId: estimate.id,
      OR: [
        { status: { not: "DRAFT" } }, { sentAt: { not: null } },
        { respondedAt: { not: null } }, { sentSnapshot: { not: Prisma.DbNull } },
      ],
    },
    select: { id: true },
  });
  if (estimate.status !== "DRAFT" || sentProposal) {
    throw new ConflictError("Only draft estimates can be edited. Create a new estimate revision for changes.");
  }
}
