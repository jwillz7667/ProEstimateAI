import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description:
    "ProEstimate AI Privacy Policy — how we collect, use, and protect your personal information.",
  alternates: { canonical: "https://proestimateai.com/privacy" },
};

export default function PrivacyPolicy() {
  return (
    <main className="min-h-screen bg-surface">
      {/* Header */}
      <header className="border-b border-gray-100">
        <div className="mx-auto max-w-4xl px-6 py-6 flex items-center justify-between">
          <Link href="/" className="text-xl font-bold text-gray-900">
            ProEstimate<span className="text-brand-500">AI</span>
          </Link>
          <Link
            href="/"
            className="text-sm text-brand-500 hover:text-brand-600 font-medium"
          >
            &larr; Back to Home
          </Link>
        </div>
      </header>

      {/* Content */}
      <article className="mx-auto max-w-4xl px-6 py-16">
        <h1 className="text-4xl font-bold text-gray-900 mb-2">
          Privacy Policy
        </h1>
        <p className="text-gray-500 mb-12">
          Last updated: March 26, 2026
        </p>

        <div className="prose prose-gray prose-lg max-w-none [&_h2]:text-2xl [&_h2]:font-semibold [&_h2]:text-gray-900 [&_h2]:mt-12 [&_h2]:mb-4 [&_h3]:text-xl [&_h3]:font-semibold [&_h3]:text-gray-900 [&_h3]:mt-8 [&_h3]:mb-3 [&_p]:text-gray-600 [&_p]:leading-relaxed [&_p]:mb-4 [&_ul]:text-gray-600 [&_ul]:mb-4 [&_li]:mb-2">
          <p>
            ProEstimate AI (&quot;we,&quot; &quot;our,&quot; or &quot;us&quot;)
            operates the ProEstimate AI mobile application and the
            proestimateai.com website (collectively, the
            &quot;Service&quot;). This Privacy Policy explains how we collect,
            use, disclose, and safeguard your information when you use our
            Service.
          </p>

          <h2>1. Information We Collect</h2>

          <h3>1.1 Account Information</h3>
          <p>
            When you create an account, we collect your name, email address, and
            company name. If you sign in with Apple, we receive your Apple user
            ID and, optionally, your name and email as provided by Apple.
          </p>

          <h3>1.2 Project Data</h3>
          <p>
            When you use the Service, you may upload photos of renovation
            spaces, create projects, generate AI previews, build estimates, and
            create proposals and invoices. All project data — including photos,
            AI-generated images, material suggestions, estimates, proposals, and
            invoices — is stored on our servers to provide the Service.
          </p>

          <h3>1.3 Payment Information</h3>
          <p>
            Subscriptions are processed through Apple&apos;s App Store. We do
            not directly collect or store credit card numbers. We receive
            transaction identifiers and subscription status from Apple to manage
            your entitlements.
          </p>

          <h3>1.4 Usage Data</h3>
          <p>
            We automatically collect usage metrics including AI generation
            counts, estimate exports, feature usage patterns, device type, OS
            version, and app version. This data helps us improve performance and
            user experience.
          </p>

          <h3>1.5 Device Information</h3>
          <p>
            We collect device identifiers, operating system, browser type (for
            web access), IP address, and general location (city/region level, not
            precise GPS) for analytics, security, and service optimization.
          </p>

          <h2>2. How We Use Your Information</h2>
          <ul>
            <li>
              <strong>Service Delivery:</strong> To process your photos through
              our AI pipeline, generate remodel previews, suggest materials,
              calculate estimates, and deliver proposals and invoices.
            </li>
            <li>
              <strong>AI Processing:</strong> Photos you upload are sent to
              our AI service (powered by Google&apos;s Gemini) to generate remodel
              previews and material suggestions. Photos are processed in real
              time and are not used to train AI models.
            </li>
            <li>
              <strong>Account Management:</strong> To authenticate your
              identity, manage your subscription, and track usage against your
              plan limits.
            </li>
            <li>
              <strong>Communication:</strong> To send transactional emails
              (password resets, receipts), and with your consent, product updates
              and tips.
            </li>
            <li>
              <strong>Improvement:</strong> To analyze aggregate usage patterns,
              diagnose bugs, and improve our AI models and user experience.
            </li>
            <li>
              <strong>Security:</strong> To detect fraud, enforce our Terms of
              Service, and protect the security of our platform.
            </li>
          </ul>

          <h2>3. Data Sharing & Third Parties</h2>
          <p>We do not sell your personal information. We share data only with:</p>
          <ul>
            <li>
              <strong>AI Processing:</strong> Google Cloud (Gemini API) receives
              your uploaded photos for AI preview generation. Google processes
              these images under their Cloud Data Processing terms and does not
              use them for model training.
            </li>
            <li>
              <strong>Infrastructure:</strong> Railway (hosting), PostgreSQL
              database hosting, and Vercel (website hosting) store and process
              data on our behalf under data processing agreements.
            </li>
            <li>
              <strong>Payment Processing:</strong> Apple processes all
              subscription payments. We receive only transaction metadata, not
              payment card details.
            </li>
            <li>
              <strong>Legal Requirements:</strong> We may disclose information if
              required by law, court order, or government request, or to protect
              our rights, safety, or property.
            </li>
          </ul>

          <h2>4. Data Retention</h2>
          <p>
            We retain your account data and project content for as long as your
            account is active. If you delete your account, we will remove your
            personal data within 30 days, except where retention is required by
            law or for legitimate business purposes (e.g., fraud prevention).
            AI-generated images and material suggestions are deleted when the
            associated project is deleted.
          </p>

          <h2>5. Data Security</h2>
          <p>
            We implement industry-standard security measures including encrypted
            data transmission (TLS 1.3), encrypted data at rest, secure API
            authentication (JWT with refresh tokens), and regular security
            audits. However, no method of electronic transmission or storage is
            100% secure.
          </p>

          <h2>6. Your Rights</h2>
          <p>Depending on your jurisdiction, you may have the right to:</p>
          <ul>
            <li>Access and receive a copy of your personal data</li>
            <li>Correct inaccurate personal data</li>
            <li>Delete your personal data</li>
            <li>Object to or restrict processing of your data</li>
            <li>Data portability (receive data in a machine-readable format)</li>
            <li>Withdraw consent at any time</li>
          </ul>
          <p>
            To exercise these rights, contact us at{" "}
            <a
              href="mailto:privacy@proestimateai.com"
              className="text-brand-500 hover:text-brand-600"
            >
              privacy@proestimateai.com
            </a>
            .
          </p>

          <h2>7. Children&apos;s Privacy</h2>
          <p>
            Our Service is not directed to children under 13. We do not
            knowingly collect personal information from children under 13. If you
            believe we have collected such information, please contact us
            immediately.
          </p>

          <h2>8. International Data Transfers</h2>
          <p>
            Your data may be transferred to and processed in countries other than
            your country of residence, including the United States. We ensure
            appropriate safeguards are in place for such transfers in compliance
            with applicable data protection laws.
          </p>

          <h2>9. Cookies & Tracking (Website)</h2>
          <p>
            Our website uses essential cookies for functionality and analytics
            cookies to understand traffic patterns. We do not use third-party
            advertising cookies. You can control cookie preferences through your
            browser settings.
          </p>

          <h2>10. Changes to This Policy</h2>
          <p>
            We may update this Privacy Policy from time to time. We will notify
            you of material changes by posting the updated policy on our website
            and, where appropriate, through in-app notifications. Your continued
            use of the Service after changes constitutes acceptance.
          </p>

          <h2>11. Contact Us</h2>
          <p>
            If you have questions about this Privacy Policy or our data
            practices, contact us at:
          </p>
          <p>
            ProEstimate AI
            <br />
            Email:{" "}
            <a
              href="mailto:privacy@proestimateai.com"
              className="text-brand-500 hover:text-brand-600"
            >
              privacy@proestimateai.com
            </a>
            <br />
            Website: proestimateai.com
          </p>
        </div>
      </article>

      {/* Footer */}
      <footer className="border-t border-gray-100 py-8 text-center text-sm text-gray-500">
        <div className="mx-auto max-w-4xl px-6 flex items-center justify-between">
          <p>&copy; 2026 ProEstimate AI. All rights reserved.</p>
          <Link
            href="/terms"
            className="text-brand-500 hover:text-brand-600 font-medium"
          >
            Terms of Service
          </Link>
        </div>
      </footer>
    </main>
  );
}
