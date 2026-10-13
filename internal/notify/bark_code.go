package notify

import (
	"regexp"
	"strings"
)

// 验证码提取的正则模式（按优先级排序）
var verificationCodePatterns = []*regexp.Regexp{
	// 中文：验证码[是为：:]?\s*(\d{4,8})
	regexp.MustCompile(`验证码[是为：:]?\s*(\d{4,8})`),
	// 英文：code[\s:=]+(\d{4,8})
	regexp.MustCompile(`(?i)code[\s:=]+(\d{4,8})`),
	// 兜底：独立 4-8 位数字（前后都不是数字）
	regexp.MustCompile(`(?:^|[^\d])(\d{4,8})(?:[^\d]|$)`),
}

// extractSMSContent 从通知文本中取「内容 」一行的正文。
// 通知文本格式：收到新短信 / 蜂窝\n设备  ec20\n号码  138…\n时间  2026-…\n内容  <正文>
// 不要直接在整段文本上抓数字，会抓到时间/号码。
func extractSMSContent(text string) string {
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "内容") {
			body := strings.TrimSpace(strings.TrimPrefix(line, "内容"))
			body = strings.TrimSpace(strings.TrimPrefix(body, ":"))
			body = strings.TrimSpace(strings.TrimPrefix(body, "："))
			if body != "" {
				return body
			}
		}
	}
	// 找不到「内容」行则退回整段文本
	return text
}

// extractVerificationCode 从短信正文中提取验证码，找不到返回空串。
func extractVerificationCode(text string) string {
	for _, p := range verificationCodePatterns {
		if m := p.FindStringSubmatch(text); len(m) >= 2 {
			return m[1]
		}
	}
	return ""
}
