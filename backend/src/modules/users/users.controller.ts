import { Request, Response } from 'express';
import { sendSuccess } from '../../lib/envelope';
import * as usersService from './users.service';
import { toUserDto } from './users.dto';

export async function getMeHandler(req: Request, res: Response) {
  const user = await usersService.getMe(req.userId!);
  sendSuccess(res, toUserDto(user));
}

export async function updateMeHandler(req: Request, res: Response) {
  const user = await usersService.updateMe(req.userId!, req.body);
  sendSuccess(res, toUserDto(user));
}
