/** Public document/image identifiers grant access, so never persist them in request logs. */
export function requestLogUrl(rawUrl: unknown): string {
  if (typeof rawUrl !== "string") return "[invalid-url]";
  try {
    const url = new URL(rawUrl, "https://request.invalid");
    const segments = url.pathname.split("/");
    const normalized = segments.map((part) => decodeURIComponent(part).toLowerCase());
    const redactAfter = (prefix: string[]) => {
      const offset = normalized[1] === "v1" ? 2 : 1;
      if (prefix.every((part, index) => normalized[offset + index] === part)
        && segments.length > offset + prefix.length) {
        segments[offset + prefix.length] = "[redacted]";
      }
    };
    redactAfter(["proposals", "share"]);
    redactAfter(["invoice-share"]);
    redactAfter(["follow-up-preferences"]);
    for (const [resource, suffix] of [["assets", "image"], ["generations", "preview"], ["estimate-exports", "file"]]) {
      const offset = normalized[1] === "v1" ? 2 : 1;
      if (normalized[offset] === resource && normalized[offset + 2] === suffix) {
        segments[offset + 1] = "[redacted]";
      }
    }
    // Drop all query content, including arbitrary key names; reset/OAuth tokens and customer searches can occur here.
    const path = Array.from(segments.join("/")).filter((character) => {
      const code = character.charCodeAt(0);
      return code > 31 && code !== 127;
    }).join("");
    return path + (url.search ? "?[redacted]" : "");
  } catch {
    // A malformed escape must not make the fallback log the original secret.
    return "[invalid-url]";
  }
}
