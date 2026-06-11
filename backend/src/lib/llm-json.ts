/**
 * Tolerant JSON extraction for LLM output. Handles the malformed shapes
 * we've seen in production even with response_format=json_object:
 * markdown code fences, prose before/after the object, and trailing
 * commas. Anything still unparseable throws so callers can retry with a
 * fresh completion — a parse failure is as retryable as an HTTP 500.
 */
export function parseModelJson(text: string): unknown {
  const direct = tryParse(text);
  if (direct !== undefined) return direct;

  let cleaned = text.trim();
  const fenced = cleaned.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
  if (fenced) cleaned = fenced[1].trim();

  const start = cleaned.indexOf("{");
  const end = cleaned.lastIndexOf("}");
  if (start !== -1 && end > start) {
    cleaned = cleaned.slice(start, end + 1);
  }

  const extracted = tryParse(cleaned);
  if (extracted !== undefined) return extracted;

  // Trailing commas before a closing brace/bracket are the most common
  // remaining defect; stripping them cannot corrupt valid JSON because
  // valid JSON never contains them.
  const noTrailingCommas = cleaned.replace(/,\s*([}\]])/g, "$1");
  const repaired = tryParse(noTrailingCommas);
  if (repaired !== undefined) return repaired;

  throw new Error(
    `Model returned unparseable JSON (${text.length} chars): ${text.slice(0, 200)}`,
  );
}

function tryParse(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return undefined;
  }
}
