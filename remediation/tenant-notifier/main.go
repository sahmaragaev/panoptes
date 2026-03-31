package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"gopkg.in/yaml.v3"
)

type tenantEntry struct {
	Name            string   `yaml:"name"`
	Key             string   `yaml:"key"`
	Default         bool     `yaml:"default"`
	TelegramChatIDs []string `yaml:"telegram_chat_ids"`
}

type keysFile struct {
	Tenants []tenantEntry `yaml:"tenants"`
}

type alertPayload struct {
	Status string  `json:"status"`
	Alerts []alert `json:"alerts"`
}

type alert struct {
	Status      string            `json:"status"`
	Labels      map[string]string `json:"labels"`
	Annotations map[string]string `json:"annotations"`
}

type webhookResult struct {
	Alert      string `json:"alert"`
	Tenant     string `json:"tenant"`
	SentTo     int    `json:"sent_to"`
	TotalChats int    `json:"total_chats"`
	Timestamp  string `json:"timestamp"`
}

var (
	keysFilePath   string
	botToken       string
	httpClient     = &http.Client{Timeout: 10 * time.Second}
	telegramAPI    = "https://api.telegram.org/bot%s/sendMessage"
	reloadInterval = 10 * time.Second

	mu             sync.RWMutex
	tenants        = make(map[string][]string)
	defaultChatIDs []string
	lastMtime      time.Time
)

func loadTenants() {
	data, err := os.ReadFile(keysFilePath)
	if err != nil {
		slog.Error("failed to read keys file", "path", keysFilePath, "error", err)
		return
	}

	var kf keysFile
	if err := yaml.Unmarshal(data, &kf); err != nil {
		slog.Error("failed to parse keys file", "error", err)
		return
	}

	newTenants := make(map[string][]string)
	var newDefaults []string
	for _, t := range kf.Tenants {
		if t.Name == "" {
			continue
		}
		var ids []string
		for _, id := range t.TelegramChatIDs {
			if id != "" {
				ids = append(ids, id)
			}
		}
		newTenants[t.Name] = ids
		if t.Default && len(ids) > 0 {
			newDefaults = ids
		}
	}

	mu.Lock()
	tenants = newTenants
	defaultChatIDs = newDefaults
	mu.Unlock()

	slog.Info("loaded tenants", "count", len(newTenants))
}

func getChatIDs(tenant string) []string {
	mu.RLock()
	defer mu.RUnlock()

	if tenant != "" {
		if ids, ok := tenants[tenant]; ok && len(ids) > 0 {
			result := make([]string, len(ids))
			copy(result, ids)
			return result
		}
	}
	result := make([]string, len(defaultChatIDs))
	copy(result, defaultChatIDs)
	return result
}

func formatMessage(a alert, status string) string {
	severity := strings.ToUpper(a.Labels["severity"])
	if severity == "" {
		severity = "UNKNOWN"
	}
	alertname := a.Labels["alertname"]
	if alertname == "" {
		alertname = "unknown"
	}
	instance := a.Labels["instance"]
	summary := a.Annotations["summary"]
	description := a.Annotations["description"]

	tag := severity
	if status == "resolved" {
		tag = "RESOLVED"
	}

	var b strings.Builder
	fmt.Fprintf(&b, "[%s] %s", tag, alertname)
	if instance != "" {
		fmt.Fprintf(&b, " (%s)", instance)
	}
	if summary != "" {
		fmt.Fprintf(&b, "\n%s", summary)
	}
	if description != "" {
		fmt.Fprintf(&b, "\n%s", description)
	}
	return b.String()
}

func sendTelegram(chatID, message string) bool {
	if botToken == "" || chatID == "" {
		slog.Warn("missing bot token or chat_id, skipping")
		return false
	}

	body, _ := json.Marshal(map[string]string{
		"chat_id": chatID,
		"text":    message,
	})

	url := fmt.Sprintf(telegramAPI, botToken)
	resp, err := httpClient.Post(url, "application/json", bytes.NewReader(body))
	if err != nil {
		slog.Error("failed to send telegram message", "chat_id", chatID, "error", err)
		return false
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusOK {
		return true
	}
	slog.Error("telegram API error", "status", resp.StatusCode, "chat_id", chatID)
	return false
}

func watchFile() {
	ticker := time.NewTicker(reloadInterval)
	defer ticker.Stop()

	for range ticker.C {
		info, err := os.Stat(keysFilePath)
		if err != nil {
			continue
		}
		if !info.ModTime().Equal(lastMtime) {
			lastMtime = info.ModTime()
			loadTenants()
		}
	}
}

func handleWebhook(w http.ResponseWriter, r *http.Request) {
	var payload alertPayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		http.Error(w, `{"error":"invalid json"}`, http.StatusBadRequest)
		return
	}

	var results []webhookResult
	for _, a := range payload.Alerts {
		tenant := a.Labels["tenant"]
		alertname := a.Labels["alertname"]
		if alertname == "" {
			alertname = "unknown"
		}
		status := a.Status
		if status == "" {
			status = payload.Status
		}

		chatIDs := getChatIDs(tenant)
		message := formatMessage(a, status)

		sentTo := 0
		for _, chatID := range chatIDs {
			if sendTelegram(chatID, message) {
				sentTo++
			}
		}

		displayTenant := tenant
		if displayTenant == "" {
			displayTenant = "default"
		}

		results = append(results, webhookResult{
			Alert:      alertname,
			Tenant:     displayTenant,
			SentTo:     sentTo,
			TotalChats: len(chatIDs),
			Timestamp:  time.Now().UTC().Format(time.RFC3339),
		})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"results": results})
}

func handleReload(w http.ResponseWriter, r *http.Request) {
	loadTenants()

	mu.RLock()
	count := len(tenants)
	mu.RUnlock()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"status": "reloaded", "tenants": count})
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
}

func main() {
	keysFilePath = os.Getenv("KEYS_FILE")
	if keysFilePath == "" {
		keysFilePath = "/etc/nginx/api-keys.yml"
	}
	botToken = os.Getenv("TELEGRAM_BOT_TOKEN")

	loadTenants()

	if info, err := os.Stat(keysFilePath); err == nil {
		lastMtime = info.ModTime()
	}

	go watchFile()

	mux := http.NewServeMux()
	mux.HandleFunc("POST /webhook", handleWebhook)
	mux.HandleFunc("POST /reload", handleReload)
	mux.HandleFunc("GET /health", handleHealth)

	slog.Info("starting tenant-notifier", "port", 5002)
	if err := http.ListenAndServe(":5002", mux); err != nil {
		slog.Error("server failed", "error", err)
		os.Exit(1)
	}
}
