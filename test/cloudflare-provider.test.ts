import { describe, expect, it } from "vitest";
import {
  buildCloudflareSendPayload,
  CloudflareMailProvider,
  isAllowedCloudflareHeader,
  sanitizeCloudflareHeaders,
} from "../src/mail/providers/cloudflare";
import type { SendMailInput } from "../src/mail/types";

const INPUT: SendMailInput = {
  from: { email: "sender@example.com", name: "MailEdge" },
  to: [{ email: "recipient@example.net" }],
  subject: "Cloudflare provider error mapping",
  text: "test",
};

function rejectingBinding(code: string, message = "Cloudflare rejected the message"): SendEmail {
  return {
    async send() {
      throw Object.assign(new Error(message), { code });
    },
  } as SendEmail;
}

describe("CloudflareMailProvider", () => {
  it.each([
    "E_SENDER_NOT_VERIFIED",
    "E_SENDER_DOMAIN_NOT_AVAILABLE",
    "E_RECIPIENT_NOT_ALLOWED",
    // 兼容旧返回；当前官方文档使用 E_RECIPIENT_NOT_ALLOWED
    "E_RECIPIENT_UNVERIFIED",
    "E_HEADER_NOT_ALLOWED",
    "E_HEADER_USE_API_FIELD",
  ])("保留 %s 并阻止切换备用渠道", async (code) => {
    const provider = new CloudflareMailProvider(rejectingBinding(code), "mail_cf_permanent");
    const result = await provider.send(INPUT);

    expect(result).toMatchObject({
      provider: "cloudflare",
      success: false,
      failureKind: "permanent",
    });
    expect(result.error).toContain(`[${code}]`);
  });

  it("保留限流为 transient，让状态机稍后重试", async () => {
    const provider = new CloudflareMailProvider(
      rejectingBinding("E_RATE_LIMIT_EXCEEDED"),
      "mail_cf_transient",
    );

    await expect(provider.send(INPUT)).resolves.toMatchObject({
      provider: "cloudflare",
      success: false,
      failureKind: "transient",
      error: expect.stringContaining("[E_RATE_LIMIT_EXCEEDED]"),
    });
  });

  it("用一次结构化 send() 带上 To / Cc / Bcc，并返回 Email Service 的 messageId", async () => {
    const sent: unknown[] = [];
    const binding = {
      async send(message: unknown) {
        sent.push(message);
        return { messageId: "cf_msg_structured_1" };
      },
    } as SendEmail;
    const provider = new CloudflareMailProvider(binding, "mail_cf_structured");
    const result = await provider.send({
      ...INPUT,
      cc: [{ email: "cc@example.net", name: "Copy" }],
      bcc: [{ email: "bcc@example.net" }],
      replyTo: { email: "reply@example.com" },
      html: "<p>test</p>",
      headers: {
        "In-Reply-To": "<origin@example.com>",
        Date: "should-be-dropped",
        From: "spoof@example.com",
        "X-Campaign": "qa",
      },
    });

    expect(result).toEqual({
      provider: "cloudflare",
      success: true,
      providerMessageId: "cf_msg_structured_1",
    });
    expect(sent).toHaveLength(1);
    expect(sent[0]).toMatchObject({
      from: { email: "sender@example.com", name: "MailEdge" },
      to: "recipient@example.net",
      cc: { email: "cc@example.net", name: "Copy" },
      bcc: "bcc@example.net",
      replyTo: "reply@example.com",
      subject: INPUT.subject,
      text: "test",
      html: "<p>test</p>",
      headers: {
        "In-Reply-To": "<origin@example.com>",
        "X-Campaign": "qa",
        "X-App-Message-ID": "mail_cf_structured",
      },
    });
    expect(JSON.stringify(sent[0])).not.toContain("should-be-dropped");
    expect(JSON.stringify(sent[0])).not.toContain("spoof@example.com");
  });

  it("内嵌图片走 inline 附件，普通文件走 attachment", async () => {
    const sent: unknown[] = [];
    const binding = {
      async send(message: unknown) {
        sent.push(message);
        return { messageId: "cf_msg_att" };
      },
    } as SendEmail;
    const inline = new Uint8Array([0x47, 0x49, 0x46]).buffer as ArrayBuffer;
    const file = new Uint8Array([0x25, 0x50, 0x44, 0x46]).buffer as ArrayBuffer;
    const provider = new CloudflareMailProvider(binding, "mail_cf_att");

    await provider.send({
      ...INPUT,
      attachments: [
        { filename: "logo.gif", contentType: "image/gif", content: inline, contentId: "logo@cid" },
        { filename: "quote.pdf", contentType: "application/pdf", content: file },
      ],
    });

    expect(sent[0]).toMatchObject({
      attachments: [
        {
          filename: "logo.gif",
          type: "image/gif",
          disposition: "inline",
          contentId: "logo@cid",
        },
        {
          filename: "quote.pdf",
          type: "application/pdf",
          disposition: "attachment",
        },
      ],
    });
  });
});

describe("Cloudflare Email Service 载荷整理", () => {
  it("丢掉平台托管头和应从专用字段设置的头", () => {
    expect(
      sanitizeCloudflareHeaders({
        Date: "Wed, 16 Sep 2026 00:00:00 +0000",
        "Message-ID": "<legacy@example.com>",
        From: "spoof@example.com",
        Subject: "nope",
        "In-Reply-To": "<origin@example.com>",
        "X-App-Message-ID": "mail_01TEST",
        "Content-Type": "text/plain",
        "ARC-Authentication-Results": "i=1",
      }),
    ).toEqual({
      "In-Reply-To": "<origin@example.com>",
      "X-App-Message-ID": "mail_01TEST",
    });
  });

  it("拒绝非 allowlist、非 X- 的自定义头", () => {
    expect(isAllowedCloudflareHeader("X-Mailer")).toBe(true);
    expect(isAllowedCloudflareHeader("References")).toBe(true);
    expect(isAllowedCloudflareHeader("Received")).toBe(false);
    expect(isAllowedCloudflareHeader("X-Bad Header")).toBe(false);
    expect(isAllowedCloudflareHeader("Unsupported")).toBe(false);
  });

  it("同一收件人只出现一次，空 To 直接失败", () => {
    const payload = buildCloudflareSendPayload(
      {
        ...INPUT,
        to: [{ email: "recipient@example.net" }, { email: "Recipient@example.net" }],
        cc: [{ email: "cc@example.net" }, { email: "cc@example.net" }],
      },
      "mail_dedupe",
    );
    expect(payload.to).toBe("recipient@example.net");
    expect(payload.cc).toBe("cc@example.net");
    expect(() => buildCloudflareSendPayload({ ...INPUT, to: [] }, "mail_empty")).toThrow(/收件人为空/);
  });
});
