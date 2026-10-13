package notify

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestExtractSMSContent(t *testing.T) {
	text := "收到新短信 / 蜂窝\n设备  ec20\n号码  13812345678\n时间  2026-10-13 12:00:00\n内容  验证码 123456，5分钟内有效"
	got := extractSMSContent(text)
	if got != "验证码 123456，5分钟内有效" {
		t.Fatalf("extractSMSContent = %q, want 验证码 123456，5分钟内有效", got)
	}
}

func TestExtractVerificationCode(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"中文验证码", "验证码 123456，5分钟内有效", "123456"},
		{"中文验证码是", "验证码是 8899", "8899"},
		{"英文code", "your code: 8899", "8899"},
		{"独立数字", "本次验证码为 556677", "556677"},
	}
	for _, c := range cases {
		if got := extractVerificationCode(c.in); got != c.want {
			t.Errorf("%s: extractVerificationCode(%q) = %q, want %q", c.name, c.in, got, c.want)
		}
	}
}

func TestBuildPayload_Positive(t *testing.T) {
	c := &BarkChannel{autoCopy: true}
	ctx := NotificationContext{Text: "收到新短信 / 蜂窝\n设备  ec20\n号码  13812345678\n时间  2026-10-13 12:00:00\n内容  验证码 123456，5分钟内有效"}
	p := c.buildPayload(ctx, "openvohive")
	if p.Copy != "123456" {
		t.Errorf("Copy = %q, want 123456", p.Copy)
	}
	if p.AutoCopy != "1" {
		t.Errorf("AutoCopy = %q, want 1", p.AutoCopy)
	}
}

func TestBuildPayload_EnglishCode(t *testing.T) {
	c := &BarkChannel{autoCopy: true}
	ctx := NotificationContext{Text: "收到新短信 / 蜂窝\n设备  ec20\n号码  13812345678\n时间  2026-10-13 12:00:00\n内容  your code: 8899"}
	p := c.buildPayload(ctx, "openvohive")
	if p.Copy != "8899" {
		t.Errorf("Copy = %q, want 8899", p.Copy)
	}
}

func TestBuildPayload_Negative(t *testing.T) {
	c := &BarkChannel{autoCopy: true}
	ctx := NotificationContext{Text: "收到新短信 / 蜂窝\n设备  ec20\n号码  13812345678\n时间  2026-10-13 12:00:00\n内容  【中国银联】用云闪付乘北京地铁享优惠"}
	p := c.buildPayload(ctx, "openvohive")
	if p.Copy != "" || p.AutoCopy != "" {
		t.Errorf("负例不应产生 copy/autoCopy, got Copy=%q AutoCopy=%q", p.Copy, p.AutoCopy)
	}
	b, _ := json.Marshal(p)
	if strings.Contains(string(b), "autoCopy") || strings.Contains(string(b), "\"copy\"") {
		t.Errorf("序列化后不应含 autoCopy/copy, got %s", string(b))
	}
}

func TestBuildPayload_SwitchOff(t *testing.T) {
	c := &BarkChannel{autoCopy: false}
	ctx := NotificationContext{Text: "收到新短信 / 蜂窝\n设备  ec20\n号码  13812345678\n时间  2026-10-13 12:00:00\n内容  验证码 123456，5分钟内有效"}
	p := c.buildPayload(ctx, "openvohive")
	if p.Copy != "" || p.AutoCopy != "" {
		t.Errorf("开关关闭时不应产生 copy/autoCopy, got Copy=%q AutoCopy=%q", p.Copy, p.AutoCopy)
	}
}
