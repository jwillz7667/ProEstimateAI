import {
  markImagelessCompletedGenerationsFailed,
  markStuckGenerationsFailed,
} from '../../lib/generation-cleanup';
import { ReapGenerationsInput } from './admin.validators';

export interface ReapGenerationsResult {
  dry_run: boolean;
  scope: ReapGenerationsInput['scope'];
  // Count of rows the sweep flipped (or, in dry-run, would flip). `null` means
  // the scope excluded that sweep, distinguishing it from a real zero.
  stuck: number | null;
  imageless: number | null;
}

/**
 * Manually reap orphaned generations. Mirrors the boot-time / periodic sweeps
 * but is operator-triggered through the admin endpoint, so the imageless sweep
 * (which boot only ever dry-runs) can be executed for real after review.
 */
export async function reapGenerations(
  input: ReapGenerationsInput,
): Promise<ReapGenerationsResult> {
  const { dry_run, scope } = input;
  const includeStuck = scope === 'stuck' || scope === 'all';
  const includeImageless = scope === 'imageless' || scope === 'all';

  const stuck = includeStuck
    ? await markStuckGenerationsFailed(undefined, dry_run)
    : null;
  const imageless = includeImageless
    ? await markImagelessCompletedGenerationsFailed(undefined, dry_run)
    : null;

  return { dry_run, scope, stuck, imageless };
}
