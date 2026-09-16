import type { FailureKind } from "./types";

/**
 * Cloudflare Email Service 当前 Workers API 文档列出的 Error.code。
 * E_RECIPIENT_UNVERIFIED 是兼容旧返回/受限收件人模式的保守别名，不将其视作当前文档代码。
 */
const CLOUDFLARE_PERMANENT_CODES = new Set([
  "E_VALIDATION_ERROR",
  "E_FIELD_MISSING",
  "E_TOO_MANY_RECIPIENTS",
  "E_TOO_MANY_ATTACHMENTS",
  "E_SENDER_NOT_VERIFIED",
  "E_RECIPIENT_NOT_ALLOWED",
  // 兼容旧返回/受限收件人模式；当前文档对应的正式代码是 E_RECIPIENT_NOT_ALLOWED
  "E_RECIPIENT_UNVERIFIED",
  "E_RECIPIENT_SUPPRESSED",
  "E_SENDER_DOMAIN_NOT_AVAILABLE",
  "E_CONTENT_TOO_LARGE",
  "E_DELIVERY_FAILED",
  "E_HEADER_NOT_ALLOWED",
  "E_HEADER_USE_API_FIELD",
  "E_HEADER_VALUE_INVALID",
  "E_HEADER_VALUE_TOO_LONG",
  "E_HEADER_NAME_INVALID",
  "E_HEADERS_TOO_LARGE",
  "E_HEADERS_TOO_MANY",
]);

const CLOUDFLARE_TRANSIENT_CODES = new Set([
  "E_RATE_LIMIT_EXCEEDED",
  "E_DAILY_LIMIT_EXCEEDED",
  "E_INTERNAL_SERVER_ERROR",
]);

const CLOUDFLARE_ERROR_HINTS: Record<string, string> = {
  E_VALIDATION_ERROR: "邮件参数无效，请检查发件人、收件人、主题及附件后重试。",
  E_FIELD_MISSING: "邮件缺少必填字段，请补全发件人、收件人和主题后重试。",
  E_TOO_MANY_RECIPIENTS: "收件人总数超过 Cloudflare 的单封上限，请减少 To、Cc 与 Bcc 地址。",
  E_TOO_MANY_ATTACHMENTS: "附件数量超过 Cloudflare 的单封上限，请减少附件后重试。",
  E_SENDER_NOT_VERIFIED:
    "发件域尚未验证，请在 Cloudflare 控制台 Email Service → Email Sending 完成域名验证后重试。",
  E_SENDER_DOMAIN_NOT_AVAILABLE:
    "发件域尚未加入 Cloudflare Email Sending，请先完成发件域 onboarding 与 DNS 配置。",
  E_RECIPIENT_NOT_ALLOWED:
    "当前 send_email 绑定不允许此收件地址。未完成发件域 onboarding 时只能发给账户里已验证的 destination address；若 wrangler.jsonc 写了 allowed_destination_addresses，收件人必须在该名单中。",
  E_RECIPIENT_UNVERIFIED: "收件地址尚未验证；请先验证该地址，或使用 Workers Paid 向任意外部收件人发信。",
  E_RECIPIENT_SUPPRESSED: "收件地址位于 Cloudflare 抑制列表中，请检查退信或投诉记录后再处理。",
  E_CONTENT_TOO_LARGE: "邮件正文与附件总大小超过 Cloudflare 限制，请缩小内容后重试。",
  E_DELIVERY_FAILED: "收件服务器拒绝或无法完成投递，请核对收件地址与退信原因。",
  E_RATE_LIMIT_EXCEEDED: "Cloudflare 发信速率已达上限，系统稍后会重试。",
  E_DAILY_LIMIT_EXCEEDED: "Cloudflare 当日发信额度已用尽，系统会在额度恢复后重试。",
  E_INTERNAL_SERVER_ERROR: "Cloudflare Email Service 暂时不可用，系统稍后会重试。",
  E_HEADER_NOT_ALLOWED: "邮件包含 Cloudflare 不允许的自定义头，请移除后重试。",
  E_HEADER_USE_API_FIELD: "邮件头应通过专用字段设置，请检查 From、To、Subject 等字段。",
  E_HEADER_VALUE_INVALID: "邮件头内容无效，请修正自定义头后重试。",
  E_HEADER_VALUE_TOO_LONG: "邮件头内容过长，请缩短自定义头后重试。",
  E_HEADER_NAME_INVALID: "邮件头名称无效，请修正自定义头后重试。",
  E_HEADERS_TOO_LARGE: "自定义邮件头总大小超过 Cloudflare 限制，请精简后重试。",
  E_HEADERS_TOO_MANY: "自定义邮件头数量超过 Cloudflare 限制，请精简后重试。",
};

/**
 * 只有 transient 才允许重试或切换备用 Provider。
 * 域名未验证、地址非法、内容被拒、账户被暂停这类错误一律 permanent，
 * 否则同一封被拒的邮件会在三个平台各发一次。
 */

const PERMANENT_PATTERNS = [
  /not\s+verified/i,
  /domain\s+.*(not|isn't)\s+verified/i,
  /unverified/i,
  /invalid\s+(email|recipient|address|from|sender)/i,
  /malformed/i,
  /not\s+allowed/i,
  /no\s+permission/i,
  /unauthorized/i,
  /forbidden/i,
  /suspended/i,
  /blocked/i,
  /blocklist/i,
  /spam/i,
  /complaint/i,
  /rejected/i,
  /content\s+.*(reject|violat)/i,
  /exceeds?\s+.*size/i,
  /too\s+large/i,
  /destination\s+address\s+not\s+allowed/i,
  /域名.*未验证/,
  /地址.*不合法/,
];

const TRANSIENT_PATTERNS = [
  /rate\s*limit/i,
  /too\s+many\s+requests/i,
  /timeout/i,
  /timed\s+out/i,
  /temporar/i,
  /try\s+again/i,
  /unavailable/i,
  /connection/i,
  /network/i,
  /socket/i,
];

export function classifyHttpFailure(status: number, message: string): FailureKind {
  if (status === 408 || status === 425 || status === 429 || status >= 500) return "transient";
  if (status >= 400) {
    // 4xx 默认永久失败，除非报文明确表示是临时问题
    return TRANSIENT_PATTERNS.some((pattern) => pattern.test(message)) ? "transient" : "permanent";
  }
  return "transient";
}

export function classifyThrown(error: unknown): FailureKind {
  const code = errorCode(error);
  if (code && CLOUDFLARE_PERMANENT_CODES.has(code)) return "permanent";
  if (code && CLOUDFLARE_TRANSIENT_CODES.has(code)) return "transient";
  const message = error instanceof Error ? error.message : String(error);
  if (PERMANENT_PATTERNS.some((pattern) => pattern.test(message))) return "permanent";
  // fetch 抛出、DNS、断连等网络层错误都算临时
  return "transient";
}

export function classifyMessage(message: string, fallback: FailureKind = "transient"): FailureKind {
  if (PERMANENT_PATTERNS.some((pattern) => pattern.test(message))) return "permanent";
  if (TRANSIENT_PATTERNS.some((pattern) => pattern.test(message))) return "transient";
  return fallback;
}

export function errorMessage(error: unknown, fallback = "发送失败"): string {
  if (error instanceof Error) return error.message || fallback;
  if (typeof error === "string" && error) return error;
  return fallback;
}

/**
 * Cloudflare Email Service 的 Error.code 不一定出现在 message 中。
 * 这里既保留原始代码供排障，又把常见原因转换成用户可执行的中文提示。
 */
export function describeCloudflareEmailError(error: unknown): {
  message: string;
  failureKind: FailureKind;
} {
  const code = errorCode(error);
  const rawMessage = errorMessage(error);
  const hint = code ? CLOUDFLARE_ERROR_HINTS[code] : undefined;
  const message = code
    ? `[${code}] ${hint ?? rawMessage.replace(new RegExp(`^${escapeRegExp(code)}\\s*[:：-]?\\s*`, "i"), "")}`
    : rawMessage;

  return { message, failureKind: classifyThrown(error) };
}

function errorCode(error: unknown): string | undefined {
  if (typeof error === "object" && error !== null && "code" in error) {
    const code = (error as { code?: unknown }).code;
    if (typeof code === "string" && /^E_[A-Z0-9_]+$/.test(code)) return code;
  }

  const message = error instanceof Error ? error.message : typeof error === "string" ? error : "";
  return message.match(/\b(E_[A-Z0-9_]+)\b/)?.[1];
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
