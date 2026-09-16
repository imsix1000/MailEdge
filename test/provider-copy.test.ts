import { describe, expect, it } from "vitest";
import { DICT } from "../web/src/i18n/dict";

describe("Cloudflare Provider 引导文案", () => {
  it.each(["zh", "en"] as const)("%s 明确 binding 不等于 Email Sending 已就绪", (lang) => {
    const copy = [
      DICT[lang]["providers.desc.cloudflare"],
      DICT[lang]["providers.cf.ready"],
      DICT[lang]["providers.cf.unavailable"],
    ].join(" ");

    expect(copy).toContain("Email Sending");
    expect(copy).toMatch(/onboarding|destination address|已验证/);
    expect(copy).not.toMatch(/部署即授权|authorized by deployment/i);
  });
});
