/**
 * The state of an IMAP login the relay watches with, one row per login in `imap_logins` (migrations/0011), since the
 * server's answer to a login holds for every device watching with it: `watching`, or `refused` after the server
 * refused it `refusals` times in a row, the last at `refusedAt` (ms since 1970). A refused login is tried again later
 * (`isDue`), since a server can refuse a good login once. Every move is one statement, so checks that race each count.
 */
export type LoginState = { kind: "watching" } | Refused;
export type Refused = { kind: "refused"; refusals: number; refusedAt: number };

export const WATCHING: LoginState = { kind: "watching" };

/** How a check of the login went: the server took it, or refused it. */
export type LoginCheck = "taken" | "refused";

/**
 * How long after each refusal in a row the login is tried again: about 5 minutes, a quarter of an hour, an hour, and
 * every six hours from then on. Each is a minute short of the round time, so a cron run at that mark takes it when
 * the cron does the watching. A wrong password is tried a few times a day at most, which locks no account.
 */
const RETRY_AFTER_MS = [4, 14, 59].map((minutes) => minutes * 60_000);
const LAST_RETRY_AFTER_MS = 359 * 60_000;

/** Whether a check at `now` logs in with a login in this state. */
export function isDue(state: LoginState, now: number): boolean {
  if (state.kind === "watching") return true;
  return now >= state.refusedAt + (RETRY_AFTER_MS[state.refusals - 1] ?? LAST_RETRY_AFTER_MS);
}

/** A login's row, or a watch's row joined with it: no row is a login no check has refused. */
export interface LoginRow {
  state: "watching" | "refused" | null;
  refusals: number | null;
  refused_at: number | null;
}

export function loginStateOf(row: LoginRow): LoginState {
  return row.state === "refused" ? { kind: "refused", refusals: row.refusals ?? 0, refusedAt: row.refused_at ?? 0 } : WATCHING;
}

export async function loginState(db: D1Database, loginHash: string): Promise<LoginState> {
  const row = await db
    .prepare("SELECT state, refusals, refused_at FROM imap_logins WHERE login_hash = ?1")
    .bind(loginHash)
    .first<LoginRow>();
  return row ? loginStateOf(row) : WATCHING;
}

/**
 * Records a check's answer for a login some watch uses, the watch `watchId` with `secretHash` when it names one, and
 * returns the state it leaves (none when no such watch exists). A refusal counts on from the one stored, whoever
 * stored it.
 */
export function recordCheck(
  db: D1Database,
  loginHash: string,
  check: LoginCheck,
  now: number,
  watch?: { watchId: string; secretHash: string },
): D1PreparedStatement {
  const [values, update] =
    check === "taken"
      ? ["'watching', 0, 0", "state = 'watching', refusals = 0, refused_at = 0"]
      : [
          "'refused', 1, ?2",
          `refusals = CASE WHEN imap_logins.state = 'refused' THEN imap_logins.refusals + 1 ELSE 1 END,
           state = 'refused', refused_at = ?2`,
        ];
  // Numbered in turn, since each statement binds exactly the values it names: ?2 is `now` only for a refusal.
  const params: (string | number)[] = check === "taken" ? [loginHash] : [loginHash, now];
  const owner = watch ? `AND watch_id = ?${params.length + 1} AND secret_hash = ?${params.length + 2}` : "";
  if (watch) params.push(watch.watchId, watch.secretHash);
  return db
    .prepare(
      `INSERT INTO imap_logins (login_hash, state, refusals, refused_at)
       SELECT ?1, ${values} WHERE EXISTS (SELECT 1 FROM imap_watches WHERE login_hash = ?1 ${owner})
       ON CONFLICT (login_hash) DO UPDATE SET ${update}
       RETURNING state, refusals, refused_at`,
    )
    .bind(...params);
}

/**
 * Copies the login's state onto the `state`, `refusals` and `refused_at` columns of its watches, where they differ,
 * since the build from before `imap_logins` reads them there: rolled back to, it then still waits out a refused login
 * instead of retrying a wrong password every run. Goes once a migration drops those columns.
 */
export function mirrorLoginState(db: D1Database, loginHash: string): D1PreparedStatement {
  const login = "(SELECT state, refusals, refused_at FROM imap_logins WHERE login_hash = ?1)";
  return db
    .prepare(
      `UPDATE imap_watches SET (state, refusals, refused_at) = ${login}
       WHERE login_hash = ?1 AND EXISTS ${login} AND (state, refusals, refused_at) IS NOT ${login}`,
    )
    .bind(loginHash);
}

/**
 * Records that the server refused the login once more, at `now`. Returns the refusals in a row, or undefined when no
 * watch uses the login any more.
 */
export async function recordRefusal(db: D1Database, loginHash: string, now: number): Promise<Refused | undefined> {
  const [recorded] = await db.batch<LoginRow>([recordCheck(db, loginHash, "refused", now), mirrorLoginState(db, loginHash)]);
  const row = recorded?.results[0];
  const state = row ? loginStateOf(row) : undefined;
  return state?.kind === "refused" ? state : undefined;
}

/** Puts a refused login back to watching once the server takes it. Returns whether it had been refused. */
export async function recordTaken(db: D1Database, loginHash: string): Promise<boolean> {
  const [result] = await db.batch([
    db
      .prepare("UPDATE imap_logins SET state = 'watching', refusals = 0, refused_at = 0 WHERE login_hash = ?1 AND state = 'refused'")
      .bind(loginHash),
    mirrorLoginState(db, loginHash),
  ]);
  return (result?.meta.changes ?? 0) > 0;
}
