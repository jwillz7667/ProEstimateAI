import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { updateCompanySchema } from './companies.validators';

// These cross-client contract checks run on Linux. They do not replace an
// Xcode build or native ViewModel tests with a controllable SettingsService.
const settingsRoot = '../ProEstimate AI/Features/Settings';
const viewModel = readFileSync(`${settingsRoot}/ViewModels/SettingsViewModel.swift`, 'utf8');
const service = readFileSync(`${settingsRoot}/Services/LiveSettingsService.swift`, 'utf8');

function method(name: string): string {
  const start = viewModel.indexOf(`func ${name}(`);
  expect(start).toBeGreaterThanOrEqual(0);
  const rest = viewModel.slice(start);
  const next = rest.slice(1).search(/^ {4}(?:(?:private|static) )?func /m);
  return next < 0 ? rest : rest.slice(0, next + 1);
}

describe('iOS settings PATCH contract', () => {
  const nullableContacts = ['phone', 'email', 'address', 'city', 'state', 'zip', 'website_url'];

  it('distinguishes clearing nullable contacts from leaving them untouched', () => {
    for (const field of nullableContacts) {
      expect(updateCompanySchema.parse({ [field]: null })).toEqual({ [field]: null });
      expect(updateCompanySchema.parse({ name: 'Updated name' })).not.toHaveProperty(field);
    }
    expect(updateCompanySchema.safeParse({ email: '' }).success).toBe(false);
    expect(updateCompanySchema.safeParse({ website_url: '' }).success).toBe(false);
  });

  it('explicitly encodes cleared branding contacts as null instead of omitting them', () => {
    const body = service.slice(service.indexOf('private struct CompanyBrandingBody'), service.indexOf('private struct TaxSettingsBody'));
    for (const field of ['phone', 'email', 'address', 'city', 'state', 'zip', 'websiteUrl']) {
      expect(body).toContain(`try container.encode(${field}, forKey: .${field})`);
      expect(body).not.toContain(`encodeIfPresent(${field},`);
    }
    expect(body).toContain('encodeIfPresent(primaryColor,');
    expect(body).toContain('encodeIfPresent(secondaryColor,');
  });

  it('keeps confirmed company/app state without replacing editable drafts on PATCH responses', () => {
    const apply = method('apply');
    expect(apply).toContain('company = updated');
    expect(apply).toContain('syncAppState(from: updated)');
    for (const field of ['selectedLanguage', 'laborMarkupPercent', 'laborMarkupText', 'defaultAiPreviewEnabled']) {
      expect(apply).not.toMatch(new RegExp(`\\b${field}\\s*=`));
    }
    expect(apply).not.toContain('populateFields');
    expect(apply).not.toContain('appearanceStore');
  });

  it('serializes every company mutation, including immediate choices and logos', () => {
    for (const name of ['commitBranding', 'commitTax', 'commitLabor', 'commitNumbering', 'saveLanguageImmediately', 'saveAppearanceImmediately', 'saveDefaultAiPreviewImmediately', 'uploadCompanyLogo', 'removeCompanyLogo']) {
      expect(method(name)).toContain('await enqueueCompanySave(');
    }
    const queue = method('enqueueCompanySave');
    expect(queue).toContain('let precedingTask = companySaveTask');
    expect(queue.indexOf('await precedingTask?.value')).toBeLessThan(queue.indexOf('try await operation()'));
    expect(queue).toContain('companySaveTask = task');
    expect(queue).toContain('await task.value');
    expect(viewModel).not.toContain('companySaveTask?.cancel()');
  });

  it('cancels only debounce tasks and ignores superseded queued saves and failures', () => {
    for (const section of ['Branding', 'Tax', 'Labor', 'Numbering']) {
      const schedule = method(`scheduleSave${section}`);
      expect(schedule).toContain(`let revision = beginSave(.${section.toLowerCase()})`);
      expect(schedule).toContain(`self.${section.toLowerCase()}SaveTask = nil`);
      expect(schedule).toContain(`await self.commit${section}(revision: revision)`);
    }
    const queue = method('enqueueCompanySave');
    expect(queue.indexOf('guard saveRevisions[section] == revision')).toBeLessThan(queue.indexOf('try await operation()'));
    const failure = queue.slice(queue.indexOf('} catch {'));
    expect(failure.indexOf('saveRevisions[section] == revision')).toBeLessThan(failure.indexOf('onFailure()'));
    expect(method('saveDefaultAiPreviewImmediately')).toContain('self.company?.defaultAiPreviewEnabled ?? !desired');
  });

  it('does not advertise saved while another section is pending or has failed', () => {
    const status = method('updateSaveStatus');
    expect(status.indexOf('saveFailures.values.first')).toBeLessThan(status.indexOf('.saved(at:'));
    expect(status.indexOf('!pendingSaveSections.isEmpty')).toBeLessThan(status.indexOf('.saved(at:'));
    const load = method('loadSettings');
    expect(load).toContain('pendingSaveSections.isEmpty, saveFailures.isEmpty');
    expect(load).toContain('saveRevisions == revisionsAtLoad');
  });

  it('updates local language immediately and prevents queued writes crossing accounts', () => {
    const language = method('saveLanguageImmediately');
    expect(language.indexOf('appearanceStore?.setLanguage(desired)')).toBeLessThan(language.indexOf('await enqueueCompanySave'));
    expect(language).not.toContain('Task.sleep');
    const queue = method('enqueueCompanySave');
    expect(queue.indexOf('guard appState?.currentCompany?.id == accountID')).toBeLessThan(queue.indexOf('try await operation()'));
    expect(queue.slice(queue.indexOf('try await operation()'))).toContain('guard appState?.currentCompany?.id == accountID');
  });
});
