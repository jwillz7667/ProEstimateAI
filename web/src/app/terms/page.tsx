import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Terms of Service",
  description:
    "ProEstimate AI Terms of Service — rules and conditions for using our platform.",
  alternates: { canonical: "https://proestimateai.com/terms" },
};

export default function TermsOfService() {
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
          Terms of Service
        </h1>
        <p className="text-gray-500 mb-12">
          Last updated: March 26, 2026
        </p>

        <div className="prose prose-gray prose-lg max-w-none [&_h2]:text-2xl [&_h2]:font-semibold [&_h2]:text-gray-900 [&_h2]:mt-12 [&_h2]:mb-4 [&_h3]:text-xl [&_h3]:font-semibold [&_h3]:text-gray-900 [&_h3]:mt-8 [&_h3]:mb-3 [&_p]:text-gray-600 [&_p]:leading-relaxed [&_p]:mb-4 [&_ul]:text-gray-600 [&_ul]:mb-4 [&_li]:mb-2">
          <p>
            These Terms of Service (&quot;Terms&quot;) govern your access to and
            use of the ProEstimate AI mobile application and website
            (collectively, the &quot;Service&quot;) operated by ProEstimate AI
            (&quot;we,&quot; &quot;our,&quot; or &quot;us&quot;). By accessing or
            using the Service, you agree to be bound by these Terms.
          </p>

          <h2>1. Acceptance of Terms</h2>
          <p>
            By creating an account or using any part of the Service, you
            acknowledge that you have read, understood, and agree to be bound by
            these Terms and our Privacy Policy. If you do not agree, do not use
            the Service.
          </p>

          <h2>2. Description of Service</h2>
          <p>
            ProEstimate AI is an AI-powered platform for renovation and
            construction projects. The Service enables users to:
          </p>
          <ul>
            <li>Upload photos and receive AI-generated remodel previews</li>
            <li>
              Receive AI-suggested material lists with estimated costs and
              supplier information
            </li>
            <li>
              Create professional cost estimates with material, labor, and other
              cost categories
            </li>
            <li>Generate proposals and invoices from estimates</li>
            <li>
              Toggle between DIY (materials only) and professional (with labor)
              pricing modes
            </li>
            <li>Manage clients, projects, and financial documents</li>
          </ul>

          <h2>3. Account Registration</h2>
          <p>
            You must create an account to use the Service. You agree to provide
            accurate, current, and complete information during registration and
            to keep your account information updated. You are responsible for
            maintaining the confidentiality of your credentials and for all
            activity under your account.
          </p>

          <h2>4. Subscriptions & Payments</h2>

          <h3>4.1 Free Tier</h3>
          <p>
            The free tier includes 3 AI preview generations, 3 estimate exports,
            and basic features. Free tier limits are tracked server-side and
            reset based on your usage bucket period.
          </p>

          <h3>4.2 Pro Subscription</h3>
          <p>
            Pro subscriptions are available as monthly ($19.99/month) or annual
            ($199.99/year) plans, billed through the Apple App Store. Pro
            includes unlimited AI generations, unlimited exports, priority
            processing, proposals, invoicing, and priority support.
          </p>

          <h3>4.3 Free Trial</h3>
          <p>
            New Pro subscribers may be eligible for a 7-day free trial. The trial
            is an Apple App Store introductory offer. If you do not cancel before
            the trial ends, your subscription will automatically convert to a
            paid subscription at the applicable rate.
          </p>

          <h3>4.4 Billing & Cancellation</h3>
          <p>
            All payments are processed by Apple through the App Store.
            Subscriptions automatically renew unless cancelled at least 24 hours
            before the end of the current period. You can manage and cancel
            subscriptions through your Apple ID settings. We do not provide
            refunds directly — refund requests should be directed to Apple.
          </p>

          <h2>5. AI-Generated Content</h2>

          <h3>5.1 Nature of AI Output</h3>
          <p>
            AI-generated remodel previews, material suggestions, and cost
            estimates are produced by artificial intelligence models and are
            provided for informational and planning purposes only. They are
            <strong> not</strong> professional engineering advice, architectural
            plans, or guaranteed cost projections.
          </p>

          <h3>5.2 No Guarantee of Accuracy</h3>
          <p>
            While we strive for accuracy, AI-generated content may contain
            errors, inaccuracies, or omissions. Material costs, quantities, and
            labor estimates are approximations based on market data and may not
            reflect actual prices in your area. Always verify costs with local
            suppliers and contractors before making purchasing or hiring
            decisions.
          </p>

          <h3>5.3 Ownership of Generated Content</h3>
          <p>
            You retain ownership of photos you upload. AI-generated images,
            material lists, and estimates created through your use of the Service
            are licensed to you for personal and commercial use (e.g., sharing
            with clients, including in proposals). We retain a license to use
            aggregate, anonymized data to improve our AI models.
          </p>

          <h2>6. User Content & Conduct</h2>
          <p>You agree not to:</p>
          <ul>
            <li>
              Upload content that is illegal, harmful, or violates third-party
              rights
            </li>
            <li>
              Use the Service to generate misleading estimates intended to
              defraud clients
            </li>
            <li>
              Attempt to reverse-engineer, decompile, or extract our AI models
            </li>
            <li>
              Use automated tools (bots, scrapers) to access the Service without
              written permission
            </li>
            <li>
              Exceed your plan limits through account sharing or circumvention
            </li>
            <li>
              Resell, redistribute, or white-label the Service without written
              authorization
            </li>
          </ul>

          <h2>7. Intellectual Property</h2>
          <p>
            The Service, including its design, features, AI models, code, and
            documentation, is owned by ProEstimate AI and protected by
            intellectual property laws. These Terms do not grant you any rights
            to our trademarks, logos, or brand assets except as needed to use the
            Service.
          </p>

          <h2>8. Third-Party Services</h2>
          <p>
            The Service may include links to third-party suppliers (e.g., Home
            Depot, Lowe&apos;s) for material sourcing. We are not affiliated
            with these suppliers and do not guarantee the accuracy of linked
            prices, availability, or product information. Your transactions with
            third-party suppliers are solely between you and the supplier.
          </p>

          <h2>9. Disclaimer of Warranties</h2>
          <p>
            THE SERVICE IS PROVIDED &quot;AS IS&quot; AND &quot;AS
            AVAILABLE&quot; WITHOUT WARRANTIES OF ANY KIND, EXPRESS OR IMPLIED,
            INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, FITNESS
            FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT. WE DO NOT WARRANT
            THAT THE SERVICE WILL BE UNINTERRUPTED, ERROR-FREE, OR SECURE.
          </p>

          <h2>10. Limitation of Liability</h2>
          <p>
            TO THE MAXIMUM EXTENT PERMITTED BY LAW, PROESTIMATE AI SHALL NOT BE
            LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR
            PUNITIVE DAMAGES, INCLUDING BUT NOT LIMITED TO LOSS OF PROFITS, DATA,
            OR BUSINESS OPPORTUNITIES, ARISING FROM YOUR USE OF THE SERVICE. OUR
            TOTAL LIABILITY SHALL NOT EXCEED THE AMOUNT YOU PAID US IN THE 12
            MONTHS PRECEDING THE CLAIM.
          </p>

          <h2>11. Indemnification</h2>
          <p>
            You agree to indemnify and hold harmless ProEstimate AI, its
            officers, employees, and agents from any claims, damages, or
            expenses (including reasonable attorney&apos;s fees) arising from
            your use of the Service, violation of these Terms, or infringement of
            any third-party rights.
          </p>

          <h2>12. Termination</h2>
          <p>
            We may suspend or terminate your account at any time for violation of
            these Terms or for any other reason at our sole discretion. Upon
            termination, your right to use the Service ceases immediately. You
            may delete your account at any time through the app settings.
          </p>

          <h2>13. Governing Law</h2>
          <p>
            These Terms are governed by and construed in accordance with the laws
            of the State of California, United States, without regard to
            conflicts of law principles. Any disputes arising from these Terms
            shall be resolved in the courts of California.
          </p>

          <h2>14. Changes to Terms</h2>
          <p>
            We reserve the right to modify these Terms at any time. We will
            provide notice of material changes through the Service or by email.
            Your continued use after changes constitutes acceptance of the
            revised Terms.
          </p>

          <h2>15. Severability</h2>
          <p>
            If any provision of these Terms is held invalid or unenforceable, the
            remaining provisions shall continue in full force and effect.
          </p>

          <h2>16. Contact</h2>
          <p>
            For questions about these Terms, contact us at:
          </p>
          <p>
            ProEstimate AI
            <br />
            Email:{" "}
            <a
              href="mailto:legal@proestimateai.com"
              className="text-brand-500 hover:text-brand-600"
            >
              legal@proestimateai.com
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
            href="/privacy"
            className="text-brand-500 hover:text-brand-600 font-medium"
          >
            Privacy Policy
          </Link>
        </div>
      </footer>
    </main>
  );
}
