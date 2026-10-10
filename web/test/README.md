# Proposal response regressions

Run `npm test` from `web` for dependency-free state/handler tests of the actual
compiled `ProposalActions` component with deterministic React-hook mocks. These
check error recovery, unchanged decision/message, cancellation, synchronous
repeated clicks, success, and the label association. They are not DOM/browser
rendering tests.

For actual browser tests, make the `playwright` package and its Chromium browser
available in your development environment, then run `npm run test:browser`.
`NODE_PATH` may point to an environment-provided Playwright install;
`CHROMIUM_PATH` may point to an existing Chromium executable.
The test starts Next on localhost:14320 and a fixture API on localhost:14319.
Both API environment variables are overridden: no production customer data or
proposal decisions are used. Browser tests write synthetic screenshots under
`SCREENSHOT_DIR` when supplied, otherwise `/tmp`.

If the host sandbox prevents Chromium from opening local sockets, the browser
suite is blocked, not passed. Run it in a supported environment before release.
