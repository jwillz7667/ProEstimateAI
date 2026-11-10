export type PasswordResetValidation = { field: "password" | "confirmation"; message: string };

export function validateNewPassword(password: string, confirmation: string): PasswordResetValidation | null {
  if (password.length < 8) return { field: "password", message: "Use at least 8 characters." };
  if (password.length > 128 || new TextEncoder().encode(password).length > 72) {
    return { field: "password", message: "This password is too long. Choose a shorter password." };
  }
  if (!/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).+$/.test(password)) {
    return { field: "password", message: "Include an uppercase letter, a lowercase letter, and a number." };
  }
  if (password !== confirmation) return { field: "confirmation", message: "The passwords do not match." };
  return null;
}

/** New email links use fragments so the proof never reaches an HTTP access log. */
export function readPasswordResetToken(href: string): string | null {
  const url = new URL(href);
  const fragment = new URLSearchParams(url.hash.slice(1)).getAll("token");
  const query = url.searchParams.getAll("token");
  const values = [...fragment, ...query];
  if (values.length !== 1 || !/^[a-f0-9]{64}$/i.test(values[0])) return null;
  return values[0];
}
