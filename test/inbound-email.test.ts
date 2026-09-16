import { applyD1Migrations, createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { createMailbox, mailboxStub } from "../src/db/mailboxes";
import { createSession, createUser, type UserRecord } from "../src/db/users";
import { handleInboundEmail } from "../src/email/inbound";
import type { Env } from "../src/env";
import worker from "../src/index";

const workerEnv = env as unknown as Env;
let user: UserRecord;
let domain: string;

beforeAll(async () => {
  await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
});

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM mailboxes"),
    env.DB.prepare("DELETE FROM sessions"),
    env.DB.prepare("DELETE FROM users"),
    env.DB.prepare("DELETE FROM settings"),
  ]);
  domain = `${crypto.randomUUID()}.catchall-inbound.test`;
  user = await createUser(workerEnv, {
    email: `owner@${domain}`,
    password: "test-password-123",
    name: "Catch-all owner",
    role: "admin",
  });
});

describe("inbound Email Worker routing", () => {
  it("stores an unmatched alias in the catch-all mailbox inbox and preserves the envelope recipient", async () => {
    const fallback = await createMailbox(workerEnv, {
      address: `inbox@${domain}`,
      userId: user.id,
      isCatchAll: true,
    });
    const context = createExecutionContext();
    const message = inboundMessage(`random-alias@${domain}`);

    await handleInboundEmail(message, workerEnv, context);
    await waitOnExecutionContext(context);

    expect(message.rejectReason).toBeNull();
    const inbox = await mailboxStub(workerEnv, fallback).list({ folder: "inbox" });
    expect(inbox.items).toHaveLength(1);
    expect(inbox.items[0]).toMatchObject({
      folder: "inbox",
      subject: "Catch-all delivery fixture",
      to: [{ email: `random-alias@${domain}` }],
    });
    await expect(mailboxStub(workerEnv, fallback).list({ folder: "catchall" })).resolves.toMatchObject({
      items: [],
    });
  });

  it("keeps exact-address delivery in that mailbox inbox", async () => {
    await createMailbox(workerEnv, {
      address: `fallback@${domain}`,
      userId: user.id,
      isCatchAll: true,
    });
    const exact = await createMailbox(workerEnv, {
      address: `support@${domain}`,
      userId: user.id,
    });
    const context = createExecutionContext();
    const message = inboundMessage(`support@${domain}`);

    await handleInboundEmail(message, workerEnv, context);
    await waitOnExecutionContext(context);

    expect(message.rejectReason).toBeNull();
    await expect(mailboxStub(workerEnv, exact).list({ folder: "inbox" })).resolves.toMatchObject({
      items: [{ to: [{ email: `support@${domain}` }] }],
    });
  });

  it("rejects an address whose domain has no exact or catch-all mailbox", async () => {
    const context = createExecutionContext();
    const message = inboundMessage("nobody@unconfigured.test");

    await handleInboundEmail(message, workerEnv, context);
    await waitOnExecutionContext(context);

    expect(message.rejectReason).toContain("550 5.1.1");
  });

  it("maps the legacy catchall list API to inbox", async () => {
    const fallback = await createMailbox(workerEnv, {
      address: `inbox@${domain}`,
      userId: user.id,
      isCatchAll: true,
    });
    await mailboxStub(workerEnv, fallback).store({
      id: `legacy-api-${crypto.randomUUID()}`,
      direction: "inbound",
      folder: "inbox",
      from: { email: "sender@external.test" },
      to: [{ email: `alias@${domain}` }],
      subject: "Legacy route compatibility fixture",
      text: "visible from the legacy catchall API",
      receivedAt: "2026-08-12T12:00:00.000Z",
    });
    const token = (await createSession(workerEnv, user.id)).token;
    const context = createExecutionContext();

    const response = await worker.fetch(
      new Request(
        `https://mailedge.test/api/messages?mailboxId=${encodeURIComponent(fallback.id)}&folder=catchall`,
        { headers: { Cookie: `mailedge_session=${token}` } },
      ),
      workerEnv,
      context,
    );
    await waitOnExecutionContext(context);

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      items: [{ folder: "inbox", subject: "Legacy route compatibility fixture" }],
    });
  });
});

type TestInboundMessage = ForwardableEmailMessage & { rejectReason: string | null };

function inboundMessage(to: string): TestInboundMessage {
  const from = "sender@external.test";
  const raw = [
    `From: External Sender <${from}>`,
    `To: ${to}`,
    "Subject: Catch-all delivery fixture",
    "Message-ID: <catchall-fixture@external.test>",
    "Date: Tue, 12 Aug 2026 12:00:00 +0000",
    "MIME-Version: 1.0",
    'Content-Type: text/plain; charset="UTF-8"',
    "",
    "This message verifies the inbound catch-all path.",
    "",
  ].join("\r\n");
  const state = {
    from,
    to,
    raw: new Response(raw).body!,
    rawSize: new TextEncoder().encode(raw).byteLength,
    headers: new Headers(),
    rejectReason: null as string | null,
    setReject(reason: string) {
      state.rejectReason = reason;
    },
    async forward() {},
    async reply() {},
  };
  return state as unknown as TestInboundMessage;
}
