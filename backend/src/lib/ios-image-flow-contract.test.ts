import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

// Source-level regressions supplement, but do not replace, simulator tests.
const swift = (path: string) => readFileSync(resolve(process.cwd(), "../ProEstimate AI", path), "utf8");
describe("iOS generation flow safety contracts", () => {
  it("blocks duplicate detail generation requests before async work", () => {
    const source = swift("Features/Projects/Detail/ViewModels/ProjectDetailViewModel.swift");
    expect(source).toContain("guard !isGenerating, let project else { return }");
    expect(source.indexOf("guard !isGenerating")).toBeLessThan(source.indexOf("generationService.startGeneration("));
  });
  it("keeps text-only completions out of the image pager and observes status changes", () => {
    const source = swift("Features/Projects/Detail/Views/AIPreviewSection.swift");
    expect(source).toContain("$0.status == .completed && $0.previewURL != nil");
    expect(source).toContain(".onChange(of: completedGenerations.map(\\.id))");
    expect(source).toContain("min(selectedGenerationIndex, max(0, ids.count - 1))");
  });
  it("requires successful uploads before spending a generation credit", () => {
    const source = swift("Features/Projects/Creation/ViewModels/ProjectCreationViewModel.swift");
    expect(source).toContain("private func uploadPhotos(projectId: String) async throws");
    expect(source).toContain("guard !uploadedPhotoIndices.contains(index) else { continue }");
    expect(source).toContain("uploadedPhotoIndices.insert(index)");
    expect(source.match(/try await uploadPhotos\(projectId: project.id\)/g)).toHaveLength(2);
    expect(source).not.toContain("photo upload failed silently");
  });
  it("resumes timed-out existing jobs rather than automatically creating a second one", () => {
    const source = swift("Features/Projects/Creation/ViewModels/ProjectCreationViewModel.swift");
    const retry = source.slice(source.indexOf("func retryGeneration()"));
    expect(retry).toContain("guard !isPipelineRunning else { return }");
    expect(retry).toContain("if let pendingGeneration, pendingGeneration.status != .failed");
    expect(retry.indexOf("await pollGeneration(initial: pendingGeneration)")).toBeLessThan(retry.indexOf("generationService.startGeneration("));
  });
});
