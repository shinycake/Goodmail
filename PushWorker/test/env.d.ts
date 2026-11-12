type GoodmailEnv = import("../src/env").Env;

declare namespace Cloudflare {
  interface Env extends GoodmailEnv {
    TEST_MIGRATIONS: import("cloudflare:test").D1Migration[];
  }
}
