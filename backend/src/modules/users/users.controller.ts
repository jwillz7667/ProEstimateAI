import { Request, Response } from 'express';
import { sendSuccess } from '../../lib/envelope';
import { getMe } from './users.service';
import { toUserDto } from './users.dto';

export async function getMeHandler(req: Request, res: Response) {
  const user = await getMe(req.userId!);
  sendSuccess(res, toUserDto(user));
}
