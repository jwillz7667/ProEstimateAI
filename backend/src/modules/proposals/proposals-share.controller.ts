import { Request, Response } from 'express';
import { sendSuccess } from '../../lib/envelope';
import { param } from '../../lib/params';
import * as proposalsService from './proposals.service';
import { toSharedProposalDto } from './proposals.share-dto';

export async function getSharedProposal(req: Request, res: Response) {
  const shareToken = param(req.params.shareToken);
  const proposal = await proposalsService.getByShareToken(shareToken);
  sendSuccess(res, toSharedProposalDto(proposal));
}

export async function respondToSharedProposal(req: Request, res: Response) {
  const shareToken = param(req.params.shareToken);
  const updated = await proposalsService.respondToProposal(shareToken, req.body);
  sendSuccess(res, toSharedProposalDto(updated));
}
