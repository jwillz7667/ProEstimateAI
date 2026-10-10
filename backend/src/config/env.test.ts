import { readFileSync } from 'node:fs';
import { afterEach, describe, expect, it, vi } from 'vitest';

const ACTIVE_API = 'https://proestimate-api-production-75e5.up.railway.app';

afterEach(() => {
  vi.unstubAllEnvs();
  vi.resetModules();
});

describe('public API origin', () => {
  async function load(origin: string | undefined) {
    vi.resetModules();
    vi.stubEnv('DATABASE_URL', 'postgresql://test:test@localhost:5432/test');
    vi.stubEnv('JWT_SECRET', 'test-secret-test-secret-test-secret-aaaaa');
    vi.stubEnv('JWT_REFRESH_SECRET', 'test-refresh-test-refresh-test-refresh-aaa');
    vi.stubEnv('API_BASE_URL', origin);
    return (await import('./env')).env;
  }

  it('defaults generated links to the active Railway API', async () => {
    expect((await load(undefined)).API_BASE_URL).toBe(ACTIVE_API);
  });

  it('preserves an explicitly configured API origin', async () => {
    expect((await load('https://api.example.test')).API_BASE_URL).toBe('https://api.example.test');
  });

  it('keeps active client and setup URLs aligned with generated links', () => {
    for (const file of [
      '../ProEstimate AI/App/AppConstants.swift',
      '../web/src/lib/api.ts',
      '.env.example',
      '../SUBMISSION_CHECKLIST.md',
    ]) {
      const contents = readFileSync(file, 'utf8');
      expect(contents).toContain(ACTIVE_API);
      expect(contents).not.toContain(ACTIVE_API.replace('-75e5', ''));
    }
  });
});
