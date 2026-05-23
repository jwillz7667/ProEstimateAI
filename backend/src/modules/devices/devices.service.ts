import { prisma } from "../../config/database";

/**
 * Register or refresh an APNs token for a user.
 *
 * Apple guarantees that a given device's APNs token is unique per
 * (device, app), but the same physical device can authenticate as
 * different users over its lifetime. We treat the `token` column as
 * globally unique (Apple's contract) and re-bind it to whichever
 * user is currently authed when the iOS client posts it.
 *
 * The `lastSeenAt` bump on every register lets a future cleanup
 * sweep prune rows that have gone silent for a long time (e.g. user
 * uninstalled the app — Apple would also start returning 410 on those
 * tokens, but the lastSeenAt is the cheaper signal).
 */
export async function registerApnsToken(
  userId: string,
  token: string,
  bundleId: string,
) {
  const now = new Date();
  return prisma.deviceToken.upsert({
    where: { token },
    create: {
      userId,
      token,
      platform: "APNS",
      bundleId,
    },
    update: {
      userId,
      bundleId,
      lastSeenAt: now,
    },
  });
}

/**
 * Remove a token. Idempotent — missing rows are not an error since the
 * iOS client's deregister-on-sign-out fires opportunistically.
 */
export async function deregisterApnsToken(userId: string, token: string) {
  await prisma.deviceToken
    .deleteMany({ where: { token, userId } })
    .catch(() => {
      /* swallow — idempotent */
    });
}
