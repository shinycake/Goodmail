import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig(async () => {
  const migrations = await readD1Migrations("./migrations");
  return {
    plugins: [
      cloudflareTest({
        wrangler: { configPath: "./wrangler.toml" },
        miniflare: {
          bindings: {
            TEST_MIGRATIONS: migrations,
            PUBSUB_AUDIENCE: "https://push.example.test/v1/pubsub",
            APNS_KEY_ID: "KEY1234567",
            APNS_TEAM_ID: "TEAM123456",
            EMAIL_HMAC_SECRET: "test-hmac-secret",
          },
        },
      }),
    ],
    test: { setupFiles: ["./test/apply-migrations.ts"] },
  };
});
