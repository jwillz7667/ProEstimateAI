import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// env.ts calls process.exit(1) on invalid env at module load. Mock it so the
// unit runner never touches real process env or the Zod boot guard. vi.hoisted
// lets the factory (hoisted to the top of the file) and the test body share one
// mutable object so individual tests can toggle DEEPSEEK_API_KEY.
const mockEnv = vi.hoisted(() => ({
  DEEPSEEK_API_KEY: "sk-test" as string | undefined,
}));
vi.mock("../config/env", () => ({ env: mockEnv }));
vi.mock("../config/logger", () => ({
  logger: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
}));

import { generateEstimate, type EstimateGenContext } from "./estimate-gen";
import { AppError } from "./errors";

// ─── Fixtures ──────────────────────────────────────────────────────────────

function baseContext(
  overrides: Partial<EstimateGenContext> = {},
): EstimateGenContext {
  return {
    projectType: "KITCHEN",
    qualityTier: "STANDARD",
    projectTitle: "Kitchen Refresh",
    companyName: "Acme Renovations",
    selectedMaterials: [],
    ...overrides,
  };
}

// DeepSeek returns OpenAI-compatible chat completions. `content` is the raw
// string the model emitted — here a JSON object matching GeneratedEstimate.
// Line item names are deliberately chosen NOT to match any tier-bounds
// keyword (no "cabinet", "permit", "paint"…) so unitCost passes through the
// clamp unchanged and cost assertions stay deterministic.
function deepSeekBody(content: string, finishReason = "stop") {
  return {
    choices: [{ message: { content }, finish_reason: finishReason }],
  };
}

function makeResponse(
  body: unknown,
  { ok = true, status = 200 }: { ok?: boolean; status?: number } = {},
) {
  return {
    ok,
    status,
    json: async () => body,
    text: async () => (typeof body === "string" ? body : JSON.stringify(body)),
  } as unknown as Response;
}

const CANNED_ESTIMATE = JSON.stringify({
  title: "Kitchen Refresh",
  overview: "We will refresh your kitchen.",
  lineItems: [
    // taxRate in percent form — must be normalized to a fraction (8.25 → 0.0825).
    {
      category: "materials",
      name: "Coordination package",
      description: "",
      quantity: 1,
      unit: "lot",
      unitCost: 960,
      markupPercent: 0,
      taxRate: 8.25,
    },
    // Labor is untaxed; taxRate already 0.
    {
      category: "labor",
      name: "General installation labor",
      description: "",
      quantity: 8,
      unit: "hour",
      unitCost: 65,
      markupPercent: 0,
      taxRate: 0,
    },
    // taxRate already a fraction — must pass through untouched.
    {
      category: "other",
      name: "Administrative handling",
      description: "",
      quantity: 1,
      unit: "lot",
      unitCost: 200,
      markupPercent: 0,
      taxRate: 0.07,
    },
    // Unknown category string — must be coerced to "other".
    {
      category: "bogus",
      name: "Site coordination",
      description: "",
      quantity: 1,
      unit: "lot",
      unitCost: 50,
      markupPercent: 0,
      taxRate: 0,
    },
  ],
  assumptions: "Standard access.",
  exclusions: "No structural work.",
  terms: "50% deposit.",
  contingencyPercent: 10,
  validDays: 30,
});

// ─── Tests ───────────────────────────────────────────────────────────────

describe("generateEstimate", () => {
  beforeEach(() => {
    mockEnv.DEEPSEEK_API_KEY = "sk-test";
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("normalizes percent-form taxRate to a fraction and preserves fractions", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      makeResponse(deepSeekBody(CANNED_ESTIMATE)),
    );
    vi.stubGlobal("fetch", fetchMock);

    const result = await generateEstimate(baseContext());

    expect(result.lineItems).toHaveLength(4);
    // 8.25 (percent) → 0.0825 (fraction)
    expect(result.lineItems[0].taxRate).toBe(0.0825);
    // Name matches no bounds keyword → unitCost passes through unclamped.
    expect(result.lineItems[0].unitCost).toBe(960);
    // Labor untaxed.
    expect(result.lineItems[1].taxRate).toBe(0);
    // Already-fractional rate preserved exactly.
    expect(result.lineItems[2].taxRate).toBe(0.07);
  });

  it("coerces an unknown category to 'other'", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(makeResponse(deepSeekBody(CANNED_ESTIMATE))),
    );

    const result = await generateEstimate(baseContext());

    expect(result.lineItems[3].category).toBe("other");
  });

  it("sends the DeepSeek key as a bearer token to the completions endpoint", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      makeResponse(deepSeekBody(CANNED_ESTIMATE)),
    );
    vi.stubGlobal("fetch", fetchMock);

    await generateEstimate(baseContext());

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("https://api.deepseek.com/chat/completions");
    expect((init as RequestInit).method).toBe("POST");
    const headers = (init as RequestInit).headers as Record<string, string>;
    expect(headers.Authorization).toBe("Bearer sk-test");
  });

  it("throws AI_UNCONFIGURED without calling the network when the key is absent", async () => {
    mockEnv.DEEPSEEK_API_KEY = undefined;
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    await expect(generateEstimate(baseContext())).rejects.toMatchObject({
      code: "AI_UNCONFIGURED",
      statusCode: 503,
    });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("retries an unparseable completion and succeeds on a fresh one", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(makeResponse(deepSeekBody("not json at all")))
      .mockResolvedValueOnce(makeResponse(deepSeekBody(CANNED_ESTIMATE)));
    vi.stubGlobal("fetch", fetchMock);

    const result = await generateEstimate(baseContext());

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(result.title).toBe("Kitchen Refresh");
  });

  it("surfaces a retryable AppError after exhausting all attempts on 5xx", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValue(makeResponse("upstream boom", { ok: false, status: 503 }));
    vi.stubGlobal("fetch", fetchMock);

    const err = await generateEstimate(baseContext()).catch((e) => e);

    expect(err).toBeInstanceOf(AppError);
    expect((err as AppError).retryable).toBe(true);
    // 3 attempts total (initial + 2 retries).
    expect(fetchMock).toHaveBeenCalledTimes(3);
  });
});
