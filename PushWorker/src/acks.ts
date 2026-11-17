import type { Env } from "./env";
import { ALERT_ID, move } from "./fallback";
import { BadRequest, readJson } from "./shared";

/**
 * `POST /v1/acks` with `{"alert"}`: the iPhone's notification extension says the alert arrived, so its watch doesn't
 * get it too (ADR-023). Always 204 for a well-formed ID, so the answer never says whether the alert existed or whether
 * the watch already got it.
 */
export async function acknowledge(request: Request, env: Env): Promise<Response> {
  const { alert } = await readJson(request);
  if (typeof alert !== "string" || !ALERT_ID.test(alert)) throw new BadRequest("bad alert");
  await move(env.DB, alert.toLowerCase(), "confirmed");
  return new Response(null, { status: 204 });
}
