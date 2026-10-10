import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

// Linux-runnable source contracts for the iOS client. Device/simulator tests
// with URLProtocol-controlled response ordering remain required for runtime QA.
const root = '../ProEstimate AI';
const client = readFileSync(`${root}/Core/Networking/APIClient.swift`, 'utf8');
const store = readFileSync(`${root}/Core/Networking/TokenStore.swift`, 'utf8');
const endpoint = readFileSync(`${root}/Core/Networking/APIEndpoint.swift`, 'utf8');
const state = readFileSync(`${root}/App/AppState.swift`, 'utf8');
const app = readFileSync(`${root}/ProEstimate_AIApp.swift`, 'utf8');
const gate = readFileSync(`${root}/Features/Auth/Views/AuthGateView.swift`, 'utf8');

function between(source: string, start: string, end: string): string {
  const from = source.indexOf(start);
  const to = source.indexOf(end, from + start.length);
  expect(from).toBeGreaterThanOrEqual(0);
  expect(to).toBeGreaterThan(from);
  return source.slice(from, to);
}

describe('iOS authentication lifecycle contract', () => {
  it('revokes the captured refresh token without depending on a cleared bearer', () => {
    expect(endpoint).toContain('case authLogout(refreshToken: String)');
    expect(endpoint).toContain('case let .authRefreshToken(refreshToken), let .authLogout(refreshToken):');
    const auth = between(endpoint, 'var requiresAuth:', 'var queryItems:');
    expect(auth).toContain('.authRefreshToken, .authLogout, .authForgotPassword:');
    expect(state).toContain('let refreshToken = TokenStore.shared.clearTokens()');
    expect(state).toContain('.authLogout(refreshToken: refreshToken)');
    expect(state.indexOf('clearTokens()')).toBeLessThan(state.indexOf('.authLogout(refreshToken:'));
  });

  it('atomically guards refreshed credentials against logout or account replacement', () => {
    expect(store).toContain('OSAllocatedUnfairLock(initialState: UUID())');
    const replace = between(store, 'func replaceTokens(', 'func clearTokens(');
    expect(replace).toContain('sessionLock.withLock');
    expect(replace).toContain('guard id == session.id,');
    expect(replace).toContain('read(key: AppConstants.keychainRefreshTokenKey) == session.refreshToken');
    expect(replace.indexOf('guard id ==')).toBeLessThan(replace.indexOf('save(key:'));
    expect(between(store, 'func storeTokens(', 'func replaceTokens(')).toContain('id = UUID()');
    expect(between(store, 'func clearTokens(', 'var hasTokens:')).toContain('id = UUID()');
    // Token rotation is part of the same login session.
    expect(replace).not.toContain('id = UUID()');
  });

  it('scopes refresh single-flight work and request retries to the original session', () => {
    expect(client).toContain('private var inFlight: [UUID: Task<Void, Error>]');
    expect(client).toContain('refresh(sessionID: originalSession.id)');
    const request = between(client, 'private func performRequest(', 'private func execute(');
    expect(request).toContain('let originalSession = tokenStore.sessionSnapshot');
    expect(request).toContain('accessToken: originalSession.accessToken');
    expect(request).toContain('guard retrySession.id == originalSession.id');
    expect(request.match(/tokenStore.sessionIdentifier == originalSession.id/g)).toHaveLength(2);
  });

  it('keeps transient refresh failures retryable and only expires definitively rejected sessions', () => {
    const refresh = between(client, 'private func performRefresh(', '// MARK: - Refresh Coordinator');
    expect(refresh).toContain('httpResponse.statusCode == 401 || httpResponse.statusCode == 403');
    expect(refresh).toContain('_ = try handleHTTPResponse(httpResponse, data: data)');
    expect(refresh).not.toContain('catch {');
    expect(client).not.toContain('async -> Bool');
    expect(client).not.toContain('let didRefresh =');
  });

  it('reuses an already-rotated access token and revokes a stale refresh result', () => {
    const refresh = between(client, 'private func performRefresh(', '// MARK: - Refresh Coordinator');
    expect(refresh.indexOf('current.accessToken != originalSession.accessToken')).toBeLessThan(refresh.indexOf('try await execute(request)'));
    expect(refresh).toContain('tokenStore.replaceTokens(');
    expect(refresh).toContain('.authLogout(refreshToken: tokenResponse.refreshToken)');
    expect(refresh).not.toContain('tokenStore.storeTokens(');
  });

  it('does not let a delayed unauthorized callback sign out a newer account', () => {
    const handler = app.slice(app.indexOf('APIClient.shared.onUnauthorized ='));
    expect(handler.indexOf('guard TokenStore.shared.sessionIdentifier == sessionID')).toBeLessThan(handler.indexOf('appState.signOut('));
  });

  it('retains cold-start credentials on timeout/network failure and offers retry', () => {
    expect(gate).toContain('case failure(isUnauthorized: Bool)');
    expect(gate).toContain('if isUnauthorized {\n                    TokenStore.shared.clearTokens()');
    expect(gate).toContain('hasRestoreError = true');
    expect(gate).toContain('RetryStateView(message: String(localized: "auth.restore.error"))');
    expect(gate).toContain('Task { await restoreSession() }');
    expect(gate).toContain('Button("Sign Out", role: .destructive)');
    expect(gate).toContain('appState.signOut(');
    expect(gate).toContain('guard TokenStore.shared.sessionIdentifier == sessionID');
    const catalog = JSON.parse(readFileSync(`${root}/Resources/Localizable.xcstrings`, 'utf8'));
    expect(catalog.strings['auth.restore.error'].localizations.en.stringUnit.value).toBeTruthy();
    expect(catalog.strings['auth.restore.error'].localizations.es.stringUnit.value).toBeTruthy();
  });
});
