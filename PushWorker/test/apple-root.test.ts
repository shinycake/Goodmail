import { expect, it } from "vitest";
import { APP_ATTESTATION_ROOT } from "../src/apple-root";
import { isAuthority, isIssuedBy, pemCertificate } from "../src/x509";

it("pins Apple's App Attestation root, which signs itself and is a CA", async () => {
  const root = pemCertificate(APP_ATTESTATION_ROOT);
  expect(root.curve).toBe("P-384");
  expect(isAuthority(root)).toBe(true);
  expect(await isIssuedBy(root, root)).toBe(true);
  expect(root.notAfter).toBe(Date.UTC(2045, 2, 15));
});
