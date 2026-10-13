import jwt from "jsonwebtoken";
import { randomUUID } from "node:crypto";
import { env } from "../config/env";

export interface JwtPayload {
  userId: string;
  companyId: string;
}

const ACCESS_TOKEN_EXPIRY = "15m";
const REFRESH_TOKEN_EXPIRY = "30d";

export function signAccessToken(payload: JwtPayload): string {
  return jwt.sign(payload, env.JWT_SECRET, { expiresIn: ACCESS_TOKEN_EXPIRY });
}

export function signRefreshToken(payload: JwtPayload): string {
  // jti makes every token unique. HS256 signing is deterministic, so two
  // tokens minted for the same user within the same iat second are
  // byte-identical — colliding on RefreshToken.token's unique index
  // (login 500s) and defeating rotation (the "new" token equals the old).
  return jwt.sign(payload, env.JWT_REFRESH_SECRET, {
    expiresIn: REFRESH_TOKEN_EXPIRY,
    jwtid: randomUUID(),
  });
}

export function verifyAccessToken(token: string): JwtPayload {
  return verifyPayload(token, env.JWT_SECRET);
}

export function verifyRefreshToken(token: string): JwtPayload {
  return verifyPayload(token, env.JWT_REFRESH_SECRET);
}

function verifyPayload(token: string, secret: string): JwtPayload {
  const payload = jwt.verify(token, secret, { algorithms: ["HS256"] });
  if (
    typeof payload === "string" ||
    typeof payload.userId !== "string" ||
    !payload.userId ||
    typeof payload.companyId !== "string" ||
    !payload.companyId
  ) {
    throw new Error("Invalid token payload");
  }
  return { userId: payload.userId, companyId: payload.companyId };
}
