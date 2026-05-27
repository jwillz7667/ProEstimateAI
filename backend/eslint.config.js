const js = require("@eslint/js");
const tseslint = require("typescript-eslint");

/** @type {import("eslint").Linter.FlatConfig[]} */
module.exports = [
  {
    ignores: ["dist/**", "node_modules/**", "prisma/migrations/**"],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    languageOptions: {
      parserOptions: {
        // Keep lint fast + non-blocking; `tsc` remains the typecheck gate.
        tsconfigRootDir: __dirname,
      },
    },
    rules: {
      // Keep noise low; this repo favors explicitness but not busywork.
      "@typescript-eslint/no-unused-vars": [
        "warn",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
      ],
      "prefer-const": "off",

      // Pragmatic defaults for an existing codebase.
      "@typescript-eslint/no-explicit-any": "off",
      "@typescript-eslint/no-floating-promises": "off",
      "@typescript-eslint/no-misused-promises": "off",
      "@typescript-eslint/require-await": "off",
      "@typescript-eslint/no-base-to-string": "off",
      "@typescript-eslint/only-throw-error": "off",
      "@typescript-eslint/consistent-type-imports": "off",
    },
  },
];

