import { isValidEmail } from "../address";
import { describeCloudflareEmailError } from "../errors";
import type { MailAddress, MailProvider, SendMailInput, SendMailResult } from "../types";

/**
 * Cloudflare Email Service（Workers Binding）。
 * 走官方推荐的结构化 send()：一次调用即可带上 To / Cc / Bcc / 附件 / 自定义头，
 * 不再把整封 RFC 5322 MIME 塞进旧的 EmailMessage 构造器。
 *
 * 旧 MIME 路径会把 Date、Message-ID、From、To 等平台托管头写进报文；
 * Email Service 现在按 allowlist 校验自定义头，这些字段会触发
 * E_HEADER_NOT_ALLOWED / E_HEADER_USE_API_FIELD，表现为「渠道已保存但发不出去」。
 *
 * 限制：整封邮件（正文 + 附件）≤ 5 MiB，最多 32 个附件。
 * 发件域必须先在 Email Service → Email Sending 完成 onboarding；
 * 未完成时只能发给账户里已验证的 destination address。
 */
export class CloudflareMailProvider implements MailProvider {
  readonly type = "cloudflare" as const;

  constructor(
    private readonly emailBinding: SendEmail | undefined,
    private readonly internalId: string,
  ) {}

  async send(input: SendMailInput): Promise<SendMailResult> {
    if (!this.emailBinding) {
      return {
        provider: this.type,
        success: false,
        error:
          "未绑定 Cloudflare Email Service。请在 wrangler.jsonc 配置 send_email 后重新部署，再在设置里保存此渠道。",
        failureKind: "permanent",
      };
    }

    try {
      const result = await this.emailBinding.send(buildCloudflareSendPayload(input, this.internalId));
      return {
        provider: this.type,
        success: true,
        providerMessageId: result.messageId || this.internalId,
      };
    } catch (error) {
      const described = describeCloudflareEmailError(error);
      return {
        provider: this.type,
        success: false,
        error: described.message,
        failureKind: described.failureKind,
      };
    }
  }
}

export type CloudflareSendPayload = EmailMessageBuilder;
export type CloudflareAddress = string | EmailAddress;

const PLATFORM_HEADERS = new Set([
  "date",
  "message-id",
  "mime-version",
  "content-type",
  "content-transfer-encoding",
  "dkim-signature",
  "return-path",
  "received",
  "feedback-id",
  "tls-required",
  "tls-report-domain",
  "tls-report-submitter",
  "cfbl-address",
  "cfbl-feedback-id",
]);

const API_FIELD_HEADERS = new Set(["from", "to", "cc", "bcc", "subject", "reply-to"]);

const ALLOWLISTED_HEADERS = new Set([
  "in-reply-to",
  "references",
  "thread-index",
  "thread-topic",
  "list-unsubscribe",
  "list-unsubscribe-post",
  "list-id",
  "list-archive",
  "list-help",
  "list-owner",
  "list-post",
  "list-subscribe",
  "precedence",
  "auto-submitted",
  "content-language",
  "keywords",
  "comments",
  "importance",
  "priority",
  "sensitivity",
  "organization",
  "require-recipient-valid-since",
  "expires",
  "reply-by",
  "archived-at",
]);

/**
 * 把内部 SendMailInput 转成 Email Service 结构化载荷。
 * 测试发送不走 dispatcher，所以这里也会自行写入 X-App-Message-ID。
 */
export function buildCloudflareSendPayload(input: SendMailInput, internalId: string): CloudflareSendPayload {
  const to = requireAddresses(input.to, "收件人为空");
  const payload: CloudflareSendPayload = {
    from: toCloudflareAddress(input.from),
    to: to.length === 1 ? to[0]! : to,
    subject: input.subject,
  };

  if (input.html) payload.html = input.html;
  if (input.text) payload.text = input.text;

  const cc = optionalAddresses(input.cc);
  if (cc) payload.cc = cc.length === 1 ? cc[0]! : cc;

  const bcc = optionalAddresses(input.bcc);
  if (bcc) payload.bcc = bcc.length === 1 ? bcc[0]! : bcc;

  if (input.replyTo) payload.replyTo = toCloudflareAddress(input.replyTo);

  const attachments: EmailAttachment[] = (input.attachments ?? []).map((item) =>
    item.contentId
      ? {
          content: item.content,
          filename: item.filename,
          type: item.contentType || "application/octet-stream",
          disposition: "inline",
          contentId: item.contentId,
        }
      : {
          content: item.content,
          filename: item.filename,
          type: item.contentType || "application/octet-stream",
          disposition: "attachment",
        },
  );
  if (attachments.length) payload.attachments = attachments;

  const headers = sanitizeCloudflareHeaders({
    ...input.headers,
    "X-App-Message-ID": internalId,
  });
  if (Object.keys(headers).length) payload.headers = headers;

  return payload;
}

/**
 * Email Service 只接受 allowlist 头与 X-* 自定义头。
 * 平台托管头和 From/To/Subject 这类应走专用字段的头必须丢掉，否则整次 send() 被拒。
 */
export function sanitizeCloudflareHeaders(
  headers: Record<string, string> | undefined,
): Record<string, string> {
  const cleaned: Record<string, string> = {};
  for (const [name, rawValue] of Object.entries(headers ?? {})) {
    const value = rawValue.trim();
    if (!value) continue;
    if (!isAllowedCloudflareHeader(name)) continue;
    cleaned[name] = value;
  }
  return cleaned;
}

export function isAllowedCloudflareHeader(name: string): boolean {
  const key = name.trim().toLowerCase();
  if (!key) return false;
  if (key.startsWith("arc-")) return false;
  if (PLATFORM_HEADERS.has(key) || API_FIELD_HEADERS.has(key)) return false;
  if (ALLOWLISTED_HEADERS.has(key)) return true;
  return /^x-[a-z0-9\-_]+$/.test(key);
}

function toCloudflareAddress(address: MailAddress): CloudflareAddress {
  const email = address.email.trim();
  if (!isValidEmail(email)) {
    throw Object.assign(new Error(`invalid recipient：地址不合法 ${email.replace(/\p{C}/gu, "␡")}`), {
      code: "E_VALIDATION_ERROR",
    });
  }
  const name = address.name?.trim();
  return name ? { email, name } : email;
}

function requireAddresses(list: MailAddress[], emptyError: string): CloudflareAddress[] {
  const unique = uniqueAddresses(list);
  if (!unique.length) {
    throw Object.assign(new Error(`invalid recipient：${emptyError}`), { code: "E_VALIDATION_ERROR" });
  }
  return unique;
}

function optionalAddresses(list: MailAddress[] | undefined): CloudflareAddress[] | undefined {
  const unique = uniqueAddresses(list ?? []);
  return unique.length ? unique : undefined;
}

function uniqueAddresses(list: MailAddress[]): CloudflareAddress[] {
  const seen = new Set<string>();
  const result: CloudflareAddress[] = [];
  for (const item of list) {
    const converted = toCloudflareAddress(item);
    const email = (typeof converted === "string" ? converted : converted.email).toLowerCase();
    if (seen.has(email)) continue;
    seen.add(email);
    result.push(converted);
  }
  return result;
}
