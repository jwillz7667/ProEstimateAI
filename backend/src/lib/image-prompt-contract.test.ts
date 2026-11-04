import { describe, expect, it } from "vitest";
import { getMaterialPrompt, getProviderImagePrompt } from "./prompts";
import type { PromptContext } from "./prompts/types";

const context: PromptContext = {
  projectType: "KITCHEN",
  qualityTier: "STANDARD",
  projectTitle: "QA Kitchen Slider Comparison",
  projectDescription: "Temporary before/after divider validation; remove after QA.",
  squareFootage: 180,
  dimensions: "12 by 15 feet",
  materials: [{ name: "forest green cabinet paint", quantity: 2, unit: "gallon" }],
};
const request = "Change only the cabinets to dark forest green and add warm brass handles. Keep the windows and countertops unchanged.";
const displayVocabulary = /\b(slider|divider|comparison|diptych|collage)\b|before\s*\/\s*after|\bsplit composition\b/i;

describe("completed-project image output contract", () => {
  it.each([true, false])("keeps app display instructions out of the provider prompt (reference=%s)", (hasReference) => {
    const prompt = getProviderImagePrompt(request, context, hasReference);
    expect(prompt).not.toMatch(displayVocabulary);
    expect(prompt).not.toContain(context.projectTitle);
    expect(prompt).not.toContain(context.projectDescription);
    expect(prompt).toContain(request);
    expect(prompt).toContain("one continuous, full-bleed photograph");
    expect(prompt).toContain("180 sq ft");
    expect(prompt).toContain("forest green cabinet paint");
    if (hasReference) {
      expect(prompt).toContain("SAME photograph");
      expect(prompt).toContain("same image coordinates");
      expect(prompt).toContain("source aspect ratio");
    }
  });

  it("retains administrative project facts for estimating rather than changing the shared material scope", () => {
    const materialPrompt = getMaterialPrompt(context);
    expect(materialPrompt).toContain(context.projectTitle);
    expect(materialPrompt).toContain(context.projectDescription);
  });
});
