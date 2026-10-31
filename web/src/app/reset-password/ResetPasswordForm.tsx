"use client";

import { useEffect, useRef, useState, type FormEvent } from "react";
import Link from "next/link";
import { APIError, fetchAPI } from "@/lib/api";
import { readPasswordResetToken, validateNewPassword } from "@/lib/password-reset";

type Mode = "loading" | "reset" | "request" | "sent" | "done";
type FormError = { field: "password" | "confirmation" | "email" | "general"; message: string };

export function ResetPasswordForm() {
  const [mode, setMode] = useState<Mode>("loading");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirmation, setShowConfirmation] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<FormError | null>(null);
  const [expired, setExpired] = useState(false);
  const token = useRef<string | null>(null);
  const initialized = useRef(false);
  const submitting = useRef(false);

  useEffect(() => {
    // An email client can reuse this tab for a later fragment-only link.
    // Reload that navigation so no prior success state or proof survives it.
    const openNewLink = () => { if (window.location.hash) window.location.reload(); };
    window.addEventListener("hashchange", openNewLink);
    // Strict Mode may replay the effect. Do not reread a URL already scrubbed.
    if (!initialized.current) {
      initialized.current = true;
      token.current = readPasswordResetToken(window.location.href);
      window.history.replaceState(window.history.state, "", window.location.pathname);
      setMode(token.current ? "reset" : "request");
    }
    return () => window.removeEventListener("hashchange", openNewLink);
  }, []);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (submitting.current || (mode !== "reset" && mode !== "request")) return;
    setError(null);
    if (mode === "reset") {
      const invalid = validateNewPassword(password, confirmation);
      if (invalid) { setError(invalid); return; }
      if (!token.current) { setMode("request"); return; }
    } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim()) || email.trim().length > 255) {
      setError({ field: "email", message: "Enter a valid email address." });
      return;
    }

    submitting.current = true;
    setPending(true);
    const resetting = mode === "reset";
    try {
      await fetchAPI(resetting ? "/auth/reset-password" : "/auth/forgot-password", {
        method: "POST",
        credentials: "omit",
        referrerPolicy: "no-referrer",
        signal: AbortSignal.timeout(20_000),
        body: JSON.stringify(resetting
          ? { token: token.current, new_password: password }
          : { email: email.trim().toLowerCase() }),
      });
      token.current = null;
      setPassword("");
      setConfirmation("");
      setEmail("");
      setMode(resetting ? "done" : "sent");
    } catch (cause) {
      if (resetting && cause instanceof APIError && cause.status === 400) {
        setExpired(true);
        setError({ field: "general", message: "This reset link is invalid or has expired. Request a new link to continue." });
      } else {
        setError({ field: "general", message: cause instanceof APIError && cause.status === 429
          ? "Too many attempts. Wait a few minutes, then try again."
          : "We couldn’t complete your request. Check your connection and try again." });
      }
    } finally {
      submitting.current = false;
      setPending(false);
    }
  }

  function requestNewLink() {
    if (submitting.current) return;
    token.current = null;
    setPassword("");
    setConfirmation("");
    setExpired(false);
    setError(null);
    setMode("request");
  }

  if (mode === "loading") return <p role="status" className="text-ink-200">Checking your reset link…</p>;
  if (mode === "done" || mode === "sent") {
    return (
      <div role="status" aria-live="polite">
        <p className="mb-3 text-xs font-semibold uppercase tracking-[0.15em] text-brand-400">Account recovery</p>
        <h1 className="mb-3 text-[28px] font-semibold leading-tight tracking-tight">{mode === "done" ? "Password updated" : "Check your inbox"}</h1>
        <p className="text-[15px] leading-relaxed text-ink-200">{mode === "done"
          ? "Your password is ready. Return to ProEstimate AI and sign in with your new password."
          : "If an account uses that email and has password sign-in enabled, we’ve sent a reset link. It expires in one hour. Check your spam folder too."}</p>
        <Link href="/" className="mt-7 flex min-h-[50px] w-full items-center justify-center rounded-[14px] bg-brand-500 px-5 py-3 text-[15px] font-semibold text-black hover:bg-brand-400">Back to ProEstimate AI</Link>
        {mode === "sent" ? <button type="button" onClick={requestNewLink} className="mt-3 min-h-11 w-full text-sm font-medium text-ink-200 underline underline-offset-4 hover:text-white">Use a different email</button> : null}
      </div>
    );
  }

  const inputClass = "min-h-[50px] w-full rounded-[14px] border border-white/15 bg-[#111113] px-4 py-3 text-base text-white placeholder:text-ink-400 focus:border-brand-500 focus:outline-none focus:ring-2 focus:ring-brand-500/20 disabled:opacity-60";
  const toggleClass = "absolute right-1 top-1 flex min-h-11 min-w-[54px] items-center justify-center rounded-[10px] px-2 text-xs font-semibold text-ink-200 hover:text-brand-400 focus-visible:outline-2 focus-visible:outline-brand-400";
  return (
    <>
      <p className="mb-3 text-xs font-semibold uppercase tracking-[0.15em] text-brand-400">Account recovery</p>
      <h1 className="mb-3 text-[28px] font-semibold leading-tight tracking-tight">{mode === "reset" ? "Choose a new password" : "Reset your password"}</h1>
      <p className="mb-7 text-[15px] leading-relaxed text-ink-200">{mode === "reset" ? "Create a secure password for your ProEstimate AI account." : "Enter your account email and we’ll send you a fresh reset link."}</p>
      <form onSubmit={submit} noValidate className="space-y-5" aria-busy={pending}>
        {mode === "request" ? (
          <div>
            <label htmlFor="reset-email" className="mb-2 block text-sm font-medium">Email address</label>
            <input id="reset-email" name="email" type="email" autoComplete="email" inputMode="email" maxLength={255} required value={email} onChange={(event) => setEmail(event.target.value)} disabled={pending} aria-invalid={error?.field === "email"} aria-describedby={error ? "reset-error" : undefined} className={inputClass} placeholder="you@company.com" />
          </div>
        ) : (
          <>
            <div>
              <label htmlFor="reset-password" className="mb-2 block text-sm font-medium">New password</label>
              <div className="relative">
                <input id="reset-password" name="new_password" type={showPassword ? "text" : "password"} autoComplete="new-password" minLength={8} maxLength={128} required value={password} onChange={(event) => setPassword(event.target.value)} disabled={pending || expired} aria-invalid={error?.field === "password"} aria-describedby={`password-requirements${error ? " reset-error" : ""}`} className={`${inputClass} pr-[66px]`} />
                <button type="button" onClick={() => setShowPassword(!showPassword)} aria-label={showPassword ? "Hide new password" : "Show new password"} aria-pressed={showPassword} className={toggleClass}>{showPassword ? "Hide" : "Show"}</button>
              </div>
              <p id="password-requirements" className="mt-2 text-xs leading-relaxed text-ink-300">8+ characters, with uppercase, lowercase, and a number.</p>
            </div>
            <div>
              <label htmlFor="reset-confirmation" className="mb-2 block text-sm font-medium">Confirm new password</label>
              <div className="relative">
                <input id="reset-confirmation" name="confirmation" type={showConfirmation ? "text" : "password"} autoComplete="new-password" minLength={8} maxLength={128} required value={confirmation} onChange={(event) => setConfirmation(event.target.value)} disabled={pending || expired} aria-invalid={error?.field === "confirmation"} aria-describedby={error ? "reset-error" : undefined} className={`${inputClass} pr-[66px]`} />
                <button type="button" onClick={() => setShowConfirmation(!showConfirmation)} aria-label={showConfirmation ? "Hide confirmed password" : "Show confirmed password"} aria-pressed={showConfirmation} className={toggleClass}>{showConfirmation ? "Hide" : "Show"}</button>
              </div>
            </div>
          </>
        )}
        {error ? <p id="reset-error" role="alert" className="rounded-xl border border-red-300/30 bg-red-400/10 px-4 py-3 text-sm leading-relaxed text-red-200">{error.message}</p> : null}
        {expired ? <button type="button" onClick={requestNewLink} className="min-h-[50px] w-full rounded-[14px] bg-brand-500 px-5 py-3 text-[15px] font-semibold text-black hover:bg-brand-400">Request a new link</button> : (
          <button type="submit" disabled={pending} className="min-h-[50px] w-full rounded-[14px] bg-brand-500 px-5 py-3 text-[15px] font-semibold text-black hover:bg-brand-400 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-brand-400 disabled:cursor-wait disabled:opacity-60">{pending ? "Please wait…" : mode === "reset" ? "Update password" : "Email reset link"}</button>
        )}
      </form>
    </>
  );
}
