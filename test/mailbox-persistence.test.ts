import { applyD1Migrations, env, evictDurableObject, runInDurableObject } from "cloudflare:test";
import { beforeAll, describe, expect, it } from "vitest";
import type { StoreMessageInput } from "../src/do/mailbox";

beforeAll(async () => {
  await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
});

function fixture(id: string): StoreMessageInput {
  return {
    id,
    internalId: `internal-${id}`,
    direction: "inbound",
    folder: "inbox",
    messageId: `<${id}@sender.example>`,
    from: { email: "sender@example.com", name: "Migration Sender" },
    to: [{ email: "owner@example.com", name: "Owner" }],
    subject: "Durable Object persistence fixture",
    html: "<h1>Persistent HTML</h1><p>This body must survive archival.</p>",
    text: "Persistent text body",
    headers: { "x-migration-fixture": "preserve-me" },
    size: 8192,
    receivedAt: "2020-01-01T00:00:00.000Z",
    attachments: [
      {
        id: `attachment-${id}`,
        filename: "evidence.pdf",
        contentType: "application/pdf",
        size: 4096,
        mode: "inline",
        r2Key: `inbound/mb_persistence/${id}/evidence.pdf`,
        token: null,
      },
    ],
  };
}

describe("mailbox Durable Object persistence", () => {
  it("keeps message, attachment, state, and archived body across fresh stub handles", async () => {
    const suffix = crypto.randomUUID();
    const messageId = `message-${suffix}`;
    const namespaceId = env.MAILBOX.idFromName(`qa:persistence:${suffix}`);
    const first = env.MAILBOX.get(namespaceId);

    await first.store(fixture(messageId));
    await first.setCategory(messageId, "important");
    await first.setSummary(messageId, "Preserved AI summary");
    await first.setRead(messageId, true);
    await first.setStarred(messageId, true);
    await first.move(messageId, "archive");

    const beforeArchive = await first.get(messageId);
    expect(beforeArchive).toMatchObject({
      id: messageId,
      folder: "archive",
      category: "important",
      aiSummary: "Preserved AI summary",
      isRead: true,
      isStarred: true,
      html: "<h1>Persistent HTML</h1><p>This body must survive archival.</p>",
      text: "Persistent text body",
      headers: { "x-migration-fixture": "preserve-me" },
      attachments: [
        {
          id: `attachment-${messageId}`,
          filename: "evidence.pdf",
          contentType: "application/pdf",
          size: 4096,
        },
      ],
    });

    const archived = await first.archiveOldMessages("mb_persistence", "2021-01-01T00:00:00.000Z", 10);
    expect(archived).toEqual({ archived: 1, hasMore: false });

    // Force a real actor restart, then acquire a new handle. This verifies the
    // SQLite/object-storage state rather than relying on the existing JS object.
    await evictDurableObject(first);
    const reopened = env.MAILBOX.get(namespaceId);
    const afterArchive = await reopened.get(messageId);
    expect(afterArchive).toMatchObject({
      id: messageId,
      folder: "archive",
      category: "important",
      aiSummary: "Preserved AI summary",
      isRead: true,
      isStarred: true,
      html: "<h1>Persistent HTML</h1><p>This body must survive archival.</p>",
      text: "Persistent text body",
      headers: { "x-migration-fixture": "preserve-me" },
      attachments: [{ id: `attachment-${messageId}`, filename: "evidence.pdf" }],
    });

    await expect(reopened.listAttachments()).resolves.toMatchObject([
      {
        id: `attachment-${messageId}`,
        messageId,
        filename: "evidence.pdf",
        r2Key: `inbound/mb_persistence/${messageId}/evidence.pdf`,
      },
    ]);
    await expect(reopened.usage()).resolves.toMatchObject({
      messages: 1,
      attachments: 1,
      archivedMessages: 1,
    });
  });

  it("migrates legacy catch-all rows to inbox idempotently without breaking FTS search", async () => {
    const suffix = crypto.randomUUID();
    const messageId = `legacy-catchall-${suffix}`;
    const namespaceId = env.MAILBOX.idFromName(`qa:catchall-migration:${suffix}`);
    const first = env.MAILBOX.get(namespaceId);

    await first.store({
      ...fixture(messageId),
      folder: "catchall",
      subject: "Legacy hidden catch-all message",
      text: "migration-search-marker",
    });
    await expect(first.list({ folder: "catchall" })).resolves.toMatchObject({
      items: [{ id: messageId }],
    });

    // Constructor migration normally runs before tests can seed legacy data. Re-create the
    // historical row, evict the actor, then the next constructor must migrate it to inbox.
    await evictDurableObject(first);
    const reopened = env.MAILBOX.get(namespaceId);
    await expect(reopened.list({ folder: "inbox" })).resolves.toMatchObject({
      items: [{ id: messageId, folder: "inbox" }],
    });
    await expect(reopened.list({ folder: "catchall" })).resolves.toMatchObject({ items: [] });
    await expect(
      reopened.list({ folder: "inbox", search: "migration-search-marker" }),
    ).resolves.toMatchObject({
      items: [{ id: messageId }],
    });

    // A second actor restart reruns the migration safely and must not duplicate the FTS row.
    await evictDurableObject(reopened);
    const twiceReopened = env.MAILBOX.get(namespaceId);
    await expect(
      twiceReopened.list({ folder: "inbox", search: "migration-search-marker" }),
    ).resolves.toMatchObject({
      items: [{ id: messageId }],
    });
    await runInDurableObject(twiceReopened, (_instance, state) => {
      const rows = state.storage.sql
        .exec<{ count: number }>("SELECT COUNT(*) AS count FROM messages_fts WHERE message_id = ?", messageId)
        .toArray();
      expect(rows[0]?.count).toBe(1);
    });
  });
});
