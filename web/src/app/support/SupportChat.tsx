"use client";

import { useCallback, useEffect, useRef, useState } from "react";

/// Keep the client-side conversation short — bounds the prompt the server
/// sends to DeepSeek and keeps latency predictable. The server re-applies
/// its own system prompt each turn so the user can't strip it.
const MAX_TURNS = 10;

type ChatRole = "user" | "assistant";

interface ChatMessage {
  id: string;
  role: ChatRole;
  content: string;
}

const INTRO_MESSAGE: ChatMessage = {
  id: "intro",
  role: "assistant",
  content:
    "Hi! I can help with ProEstimate AI — pricing, features, estimates, PDFs, branding, subscriptions, or troubleshooting. What can I answer?",
};

export function SupportChat() {
  const [messages, setMessages] = useState<ChatMessage[]>([INTRO_MESSAGE]);
  const [input, setInput] = useState("");
  const [isSending, setIsSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const scrollRef = useRef<HTMLDivElement | null>(null);

  // Auto-scroll to the newest message. Uses a ref on the transcript container
  // rather than window.scrollTo so the rest of the page (FAQ, footer) stays
  // put when a long AI reply streams in.
  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    el.scrollTop = el.scrollHeight;
  }, [messages]);

  const send = useCallback(async () => {
    const trimmed = input.trim();
    if (!trimmed || isSending) return;

    const userMessage: ChatMessage = {
      id: crypto.randomUUID(),
      role: "user",
      content: trimmed,
    };
    const assistantId = crypto.randomUUID();
    const placeholder: ChatMessage = {
      id: assistantId,
      role: "assistant",
      content: "",
    };

    // Snapshot messages BEFORE the async work so we send the correct history.
    const nextHistory = [...messages, userMessage].slice(-MAX_TURNS);

    setMessages([...messages, userMessage, placeholder]);
    setInput("");
    setIsSending(true);
    setError(null);

    try {
      const response = await fetch("/api/support/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          messages: nextHistory.map((m) => ({
            role: m.role,
            content: m.content,
          })),
        }),
      });

      if (!response.ok || !response.body) {
        const text = await response.text().catch(() => "");
        throw new Error(
          text || `The assistant is unavailable (HTTP ${response.status}).`,
        );
      }

      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        setMessages((prev) =>
          prev.map((m) => (m.id === assistantId ? { ...m, content: buffer } : m)),
        );
      }

      if (!buffer.trim()) {
        throw new Error("No response from the assistant.");
      }
    } catch (err) {
      const detail =
        err instanceof Error
          ? err.message
          : "Something went wrong reaching the assistant.";
      setError(detail);
      setMessages((prev) => prev.filter((m) => m.id !== assistantId));
    } finally {
      setIsSending(false);
    }
  }, [input, isSending, messages]);

  return (
    <div className="rounded-2xl border border-gray-100 bg-white shadow-sm">
      <div className="flex items-center justify-between border-b border-gray-100 px-5 py-4">
        <div className="flex items-center gap-3">
          <span
            aria-hidden
            className="flex h-8 w-8 items-center justify-center rounded-full bg-brand-500/10 text-brand-500"
          >
            {/* simple sparkle */}
            <svg
              viewBox="0 0 20 20"
              className="h-4 w-4"
              fill="currentColor"
              aria-hidden
            >
              <path d="M10 2l1.8 4.8L16.6 8.6 11.8 10.4 10 15.2 8.2 10.4 3.4 8.6l4.8-1.8L10 2zM16 13l.9 2.4 2.4.9-2.4.9-.9 2.4-.9-2.4-2.4-.9 2.4-.9.9-2.4zM4 13l.6 1.6 1.6.6-1.6.6L4 17.4l-.6-1.6-1.6-.6 1.6-.6L4 13z" />
            </svg>
          </span>
          <div>
            <div className="text-sm font-semibold text-gray-900">
              Ask the ProEstimate AI assistant
            </div>
            <div className="text-xs text-gray-500">
              Answers grounded in the app — not Apple or third-party billing help.
            </div>
          </div>
        </div>
      </div>

      <div
        ref={scrollRef}
        className="max-h-96 overflow-y-auto px-5 py-4 space-y-4"
        aria-live="polite"
      >
        {messages.map((m) => (
          <MessageBubble key={m.id} message={m} />
        ))}
        {isSending && messages[messages.length - 1]?.content === "" ? (
          <TypingIndicator />
        ) : null}
      </div>

      {error ? (
        <div className="border-t border-red-100 bg-red-50 px-5 py-3 text-sm text-red-700">
          {error}{" "}
          <a
            className="underline font-medium"
            href="mailto:support@proestimateai.com"
          >
            Email us instead
          </a>
          .
        </div>
      ) : null}

      <form
        className="border-t border-gray-100 p-3 flex items-end gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          void send();
        }}
      >
        <textarea
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => {
            // Shift+Enter inserts a newline; plain Enter submits. Follows the
            // convention most chat UIs use.
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              void send();
            }
          }}
          rows={2}
          placeholder="e.g. How do I upload my company logo?"
          className="flex-1 resize-none rounded-lg border border-gray-200 px-4 py-3 text-sm text-gray-900 placeholder:text-gray-400 focus:border-brand-500 focus:outline-none focus:ring-2 focus:ring-brand-500/20"
          disabled={isSending}
        />
        <button
          type="submit"
          disabled={isSending || input.trim().length === 0}
          className="inline-flex items-center justify-center rounded-lg bg-brand-500 px-4 py-3 text-sm font-semibold text-white hover:bg-brand-600 disabled:opacity-50 disabled:cursor-not-allowed transition"
          aria-label="Send message"
        >
          {isSending ? "…" : "Send"}
        </button>
      </form>
    </div>
  );
}

function MessageBubble({ message }: { message: ChatMessage }) {
  const isUser = message.role === "user";
  return (
    <div className={`flex ${isUser ? "justify-end" : "justify-start"}`}>
      <div
        className={`max-w-[85%] rounded-2xl px-4 py-3 text-sm leading-relaxed whitespace-pre-wrap ${
          isUser
            ? "bg-brand-500 text-white"
            : "bg-gray-50 text-gray-900 border border-gray-100"
        }`}
      >
        {message.content || (isUser ? "" : "\u2026")}
      </div>
    </div>
  );
}

function TypingIndicator() {
  return (
    <div className="flex justify-start">
      <div className="flex items-center gap-1 rounded-2xl bg-gray-50 border border-gray-100 px-4 py-3">
        <Dot delay="0s" />
        <Dot delay="0.15s" />
        <Dot delay="0.3s" />
      </div>
    </div>
  );
}

function Dot({ delay }: { delay: string }) {
  return (
    <span
      className="inline-block h-2 w-2 rounded-full bg-gray-400 animate-bounce"
      style={{ animationDelay: delay }}
    />
  );
}
