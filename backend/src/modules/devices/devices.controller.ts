import { Request, Response } from "express";
import { sendSuccess } from "../../lib/envelope";
import * as devicesService from "./devices.service";
import {
  RegisterApnsTokenInput,
  DeregisterApnsTokenInput,
} from "./devices.validators";

export async function registerApnsTokenHandler(req: Request, res: Response) {
  const { token, bundle_id } = req.body as RegisterApnsTokenInput;
  await devicesService.registerApnsToken(req.userId!, token, bundle_id);
  sendSuccess(res, { registered: true });
}

export async function deregisterApnsTokenHandler(req: Request, res: Response) {
  const { token } = req.body as DeregisterApnsTokenInput;
  await devicesService.deregisterApnsToken(req.userId!, token);
  sendSuccess(res, { deregistered: true });
}
