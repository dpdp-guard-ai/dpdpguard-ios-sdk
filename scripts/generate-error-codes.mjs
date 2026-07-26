#!/usr/bin/env node
// Regenerates Sources/DPDPGuardConsent/Generated/ApiErrorCode.swift from
// contract/conformance/error-catalog.json (ADR-002 D2). Re-run after
// scripts/update-contract.sh whenever the catalog changes, and commit the
// diff - this file is generated but checked in, not built on the fly.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const catalog = JSON.parse(
  readFileSync(join(repoRoot, "contract/conformance/error-catalog.json"), "utf8")
);

function toCamelCase(code) {
  return code
    .toLowerCase()
    .split("_")
    .map((part, i) => (i === 0 ? part : part[0].toUpperCase() + part.slice(1)))
    .join("");
}

const cases = catalog.codes
  .map(
    ({ code, description }) =>
      `    /// ${description}\n    case ${toCamelCase(code)} = "${code}"`
  )
  .join("\n\n");

const output = `// Generated from contract/conformance/error-catalog.json by
// scripts/generate-error-codes.mjs. Do not hand-edit - re-run the script
// against an updated @dpdpguard/contract and commit the diff instead.

/// The ADR-002 D2 machine-readable \`ApiError.code\` catalog.
public enum ApiErrorCode: String, Codable, Sendable, CaseIterable {
${cases}
}
`;

const outDir = join(repoRoot, "Sources/DPDPGuardConsent/Generated");
mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, "ApiErrorCode.swift"), output);
console.log(`Wrote ${catalog.codes.length} error codes to Sources/DPDPGuardConsent/Generated/ApiErrorCode.swift`);
