package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeTempKeys(t *testing.T, content string) string {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "api-keys.yml")
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestLoadTenants(t *testing.T) {
	keysFilePath = writeTempKeys(t, `
tenants:
  - name: alpha
    key: pnpt_alpha_123
    default: true
    telegram_chat_ids:
      - "-100111"
      - "-100222"
  - name: beta
    key: pnpt_beta_456
    telegram_chat_ids:
      - "-100333"
  - name: empty
    key: pnpt_empty_789
    telegram_chat_ids: []
`)
	loadTenants()

	mu.RLock()
	defer mu.RUnlock()

	if len(tenants) != 3 {
		t.Fatalf("expected 3 tenants, got %d", len(tenants))
	}
	if len(tenants["alpha"]) != 2 {
		t.Fatalf("expected 2 chat IDs for alpha, got %d", len(tenants["alpha"]))
	}
	if len(tenants["beta"]) != 1 {
		t.Fatalf("expected 1 chat ID for beta, got %d", len(tenants["beta"]))
	}
	if len(defaultChatIDs) != 2 {
		t.Fatalf("expected 2 default chat IDs, got %d", len(defaultChatIDs))
	}
	if defaultChatIDs[0] != "-100111" {
		t.Fatalf("expected default chat ID -100111, got %s", defaultChatIDs[0])
	}
}

func TestLoadTenantsNumericChatID(t *testing.T) {
	keysFilePath = writeTempKeys(t, `
tenants:
  - name: numeric
    key: pnpt_num_123
    default: true
    telegram_chat_ids:
      - -100999888
`)
	loadTenants()

	mu.RLock()
	defer mu.RUnlock()

	if len(defaultChatIDs) != 1 {
		t.Fatalf("expected 1 default chat ID, got %d", len(defaultChatIDs))
	}
	if defaultChatIDs[0] != "-100999888" {
		t.Fatalf("expected -100999888, got %s", defaultChatIDs[0])
	}
}

func TestGetChatIDs(t *testing.T) {
	mu.Lock()
	tenants = map[string][]string{
		"alpha": {"-100111", "-100222"},
		"empty": {},
	}
	defaultChatIDs = []string{"-100999"}
	mu.Unlock()

	ids := getChatIDs("alpha")
	if len(ids) != 2 || ids[0] != "-100111" {
		t.Fatalf("expected alpha's chat IDs, got %v", ids)
	}

	ids = getChatIDs("unknown")
	if len(ids) != 1 || ids[0] != "-100999" {
		t.Fatalf("expected default chat IDs for unknown tenant, got %v", ids)
	}

	ids = getChatIDs("")
	if len(ids) != 1 || ids[0] != "-100999" {
		t.Fatalf("expected default chat IDs for empty tenant, got %v", ids)
	}

	ids = getChatIDs("empty")
	if len(ids) != 1 || ids[0] != "-100999" {
		t.Fatalf("expected default chat IDs for tenant with empty list, got %v", ids)
	}
}

func TestFormatMessageFiring(t *testing.T) {
	a := alert{
		Labels:      map[string]string{"severity": "critical", "alertname": "HighCPU", "instance": "srv1:9100"},
		Annotations: map[string]string{"summary": "CPU is high", "description": "CPU above 95%"},
	}
	msg := formatMessage(a, "firing")
	if !strings.HasPrefix(msg, "[CRITICAL] HighCPU (srv1:9100)") {
		t.Fatalf("unexpected message: %s", msg)
	}
	if !strings.Contains(msg, "CPU is high") || !strings.Contains(msg, "CPU above 95%") {
		t.Fatalf("missing annotations in message: %s", msg)
	}
}

func TestFormatMessageResolved(t *testing.T) {
	a := alert{
		Labels:      map[string]string{"severity": "warning", "alertname": "DiskLow"},
		Annotations: map[string]string{"summary": "Disk recovered"},
	}
	msg := formatMessage(a, "resolved")
	if !strings.HasPrefix(msg, "[RESOLVED] DiskLow") {
		t.Fatalf("unexpected message: %s", msg)
	}
	if strings.Contains(msg, "(") {
		t.Fatalf("should not have instance in message: %s", msg)
	}
}

func TestFormatMessageNoAnnotations(t *testing.T) {
	a := alert{
		Labels: map[string]string{"alertname": "Test"},
	}
	msg := formatMessage(a, "firing")
	if msg != "[UNKNOWN] Test" {
		t.Fatalf("expected '[UNKNOWN] Test', got '%s'", msg)
	}
}

func TestHandleHealth(t *testing.T) {
	req := httptest.NewRequest("GET", "/health", nil)
	w := httptest.NewRecorder()
	handleHealth(w, req)

	if w.Code != 200 {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var body map[string]string
	json.NewDecoder(w.Body).Decode(&body)
	if body["status"] != "healthy" {
		t.Fatalf("expected healthy, got %s", body["status"])
	}
}

func TestHandleReload(t *testing.T) {
	keysFilePath = writeTempKeys(t, `
tenants:
  - name: test
    key: pnpt_test_123
    telegram_chat_ids:
      - "-100test"
`)
	req := httptest.NewRequest("POST", "/reload", nil)
	w := httptest.NewRecorder()
	handleReload(w, req)

	if w.Code != 200 {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var body map[string]any
	json.NewDecoder(w.Body).Decode(&body)
	if body["status"] != "reloaded" {
		t.Fatalf("expected reloaded, got %v", body["status"])
	}
	if body["tenants"].(float64) != 1 {
		t.Fatalf("expected 1 tenant, got %v", body["tenants"])
	}
}

func TestHandleWebhook(t *testing.T) {
	tgServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
		fmt.Fprint(w, `{"ok":true}`)
	}))
	defer tgServer.Close()

	origAPI := telegramAPI
	telegramAPI = tgServer.URL + "/%s"
	botToken = "test-token"
	defer func() {
		telegramAPI = origAPI
		botToken = ""
	}()

	mu.Lock()
	tenants = map[string][]string{"lab": {"-100lab1", "-100lab2"}}
	defaultChatIDs = []string{"-100default"}
	mu.Unlock()

	payload := `{
		"status": "firing",
		"alerts": [
			{
				"status": "firing",
				"labels": {"alertname": "HighCPU", "severity": "critical", "tenant": "lab", "instance": "srv1:9100"},
				"annotations": {"summary": "CPU high"}
			},
			{
				"status": "firing",
				"labels": {"alertname": "DiskFull", "severity": "warning"},
				"annotations": {"summary": "Disk full"}
			}
		]
	}`

	req := httptest.NewRequest("POST", "/webhook", strings.NewReader(payload))
	w := httptest.NewRecorder()
	handleWebhook(w, req)

	if w.Code != 200 {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var body map[string][]webhookResult
	json.NewDecoder(w.Body).Decode(&body)
	results := body["results"]

	if len(results) != 2 {
		t.Fatalf("expected 2 results, got %d", len(results))
	}

	if results[0].Alert != "HighCPU" || results[0].Tenant != "lab" || results[0].SentTo != 2 || results[0].TotalChats != 2 {
		t.Fatalf("unexpected first result: %+v", results[0])
	}

	if results[1].Alert != "DiskFull" || results[1].Tenant != "default" || results[1].SentTo != 1 || results[1].TotalChats != 1 {
		t.Fatalf("unexpected second result: %+v", results[1])
	}
}

func TestHandleWebhookInvalidJSON(t *testing.T) {
	req := httptest.NewRequest("POST", "/webhook", strings.NewReader("not json"))
	w := httptest.NewRecorder()
	handleWebhook(w, req)

	if w.Code != 400 {
		t.Fatalf("expected 400 for invalid json, got %d", w.Code)
	}
}
