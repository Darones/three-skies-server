package main

import (
	"context"
	"crypto/md5"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"
)

// Shard packs sold through VK Voices and OKi. The client sends the same
// `shards_<n>` SKU to VKWebAppShowOrderBox; 100 shards cost 1 voice/OKi.
const (
	defaultOKAppID = "512005268801"
	paymentSKUPrefix = "shards_"
	minPaymentShards = 100
	maxPaymentShards = 10000
	paymentShardStep = 100
)

type paymentItem struct {
	Shards int
	Price  int
	Title  string
	ItemID string
}

func vkPaymentItem(sku string) (paymentItem, bool) {
	sku = strings.TrimSpace(sku)
	if !strings.HasPrefix(sku, paymentSKUPrefix) {
		return paymentItem{}, false
	}
	shards, err := strconv.Atoi(strings.TrimPrefix(sku, paymentSKUPrefix))
	if err != nil || shards < minPaymentShards || shards > maxPaymentShards || shards%paymentShardStep != 0 {
		return paymentItem{}, false
	}
	return paymentItem{
		Shards: shards,
		Price:  shards / paymentShardStep,
		Title:  fmt.Sprintf("%d осколков", shards),
		ItemID: sku,
	}, true
}

func publicBaseURL() string {
	value := strings.TrimRight(strings.TrimSpace(os.Getenv("PUBLIC_BASE_URL")), "/")
	if value == "" {
		value = "https://three-skies-server.relaxdev.ru"
	}
	return value
}

func paymentPhotoURL() string {
	return publicBaseURL() + "/game/shard.png"
}

func okAppID() string {
	if value := strings.TrimSpace(os.Getenv("OK_APP_ID")); value != "" {
		return value
	}
	return defaultOKAppID
}

// vkPaymentSignature is the payment notification signature: MD5 of sorted
// `key=value` pairs without separators, followed by the VK app secret. This is
// deliberately different from the HMAC launch-param signature.
func vkPaymentSignature(params map[string]string, secret string) string {
	keys := make([]string, 0, len(params))
	for key := range params {
		if key == "sig" {
			continue
		}
		keys = append(keys, key)
	}
	sort.Strings(keys)
	var builder strings.Builder
	for _, key := range keys {
		builder.WriteString(key)
		builder.WriteString("=")
		builder.WriteString(params[key])
	}
	builder.WriteString(secret)
	sum := md5.Sum([]byte(builder.String()))
	return hex.EncodeToString(sum[:])
}

func verifyVKPaymentSignature(params map[string]string, secret string) bool {
	signature := strings.ToLower(strings.TrimSpace(params["sig"]))
	if signature == "" || secret == "" {
		return false
	}
	return signature == vkPaymentSignature(params, secret)
}

func paymentParams(r *http.Request) map[string]string {
	params := make(map[string]string)
	if err := r.ParseForm(); err != nil {
		return params
	}
	for key, values := range r.Form {
		if len(values) > 0 {
			params[key] = values[0]
		}
	}
	return params
}

func firstPaymentValue(params map[string]string, keys ...string) string {
	for _, key := range keys {
		if value := strings.TrimSpace(params[key]); value != "" {
			return value
		}
	}
	return ""
}

func paymentErrorResponse(w http.ResponseWriter, code int, message string) {
	writeJSON(w, http.StatusOK, map[string]any{
		"error": map[string]any{
			"error_code": code,
			"error_msg":  message,
			"critical":   true,
		},
	})
}

func paymentItemResponse(item paymentItem) map[string]any {
	return map[string]any{
		"response": map[string]any{
			"title":     item.Title,
			"price":     item.Price,
			"photo_url": paymentPhotoURL(),
			"item_id":   item.ItemID,
		},
	}
}

func paymentOrderResponse(orderID string) map[string]any {
	return map[string]any{
		"response": map[string]any{
			"order_id":     orderID,
			"app_order_id": time.Now().UnixMilli(),
		},
	}
}

func isOKPayment(params map[string]string) bool {
	return strings.EqualFold(strings.TrimSpace(params["site"]), "OK") ||
		strings.TrimSpace(params["app_id"]) == okAppID() ||
		strings.TrimSpace(params["method"]) == "callbacks.getCustomProductInfo"
}

// handleVKPay serves both VK payment notifications and OK's get_item request
// (OK sends get_item to /vk/pay with site=OK; its payment callback goes to
// /ok/pay). OK skips the VK signature, exactly as in the proven Antivirus flow.
func (service *api) handleVKPay(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost && r.Method != http.MethodGet {
		paymentErrorResponse(w, 10, "Method not allowed")
		return
	}
	params := paymentParams(r)
	okPayment := isOKPayment(params)
	if !okPayment {
		secret := vkAppSecret()
		if secret == "" {
			log.Printf("[PAY] VK_APP_SECRET is not configured")
			paymentErrorResponse(w, 10, "not configured")
			return
		}
		if appID := strings.TrimSpace(params["app_id"]); appID != "" && appID != vkAppID() {
			log.Printf("[PAY] rejected app_id=%s", appID)
			paymentErrorResponse(w, 10, "invalid app")
			return
		}
		if !verifyVKPaymentSignature(params, secret) {
			log.Printf("[PAY] invalid signature")
			paymentErrorResponse(w, 10, "invalid signature")
			return
		}
	}

	notificationType := strings.TrimSpace(params["notification_type"])
	if notificationType == "" && okPayment {
		notificationType = "get_item"
	}
	switch {
	case strings.HasPrefix(notificationType, "get_item"):
		item, found := vkPaymentItem(firstPaymentValue(params, "item", "item_id"))
		if !found {
			paymentErrorResponse(w, 20, "Unknown item")
			return
		}
		writeJSON(w, http.StatusOK, paymentItemResponse(item))
	case strings.HasPrefix(notificationType, "order_status_change"):
		if !okPayment && strings.TrimSpace(params["status"]) != "chargeable" {
			// Pending/cancelled orders are acknowledged without a grant.
			writeJSON(w, http.StatusOK, paymentOrderResponse(firstPaymentValue(params, "order_id")))
			return
		}
		itemID := firstPaymentValue(params, "item", "item_id", "product_code")
		item, found := vkPaymentItem(itemID)
		if !found {
			paymentErrorResponse(w, 20, "Unknown item")
			return
		}
		platform := "vk"
		externalID := firstPaymentValue(params, "user_id", "receiver_id")
		if okPayment {
			platform = "ok"
			externalID = firstPaymentValue(params, "uid", "user_id")
		}
		orderID := firstPaymentValue(params, "order_id", "transaction_id")
		newShards, granted, err := service.grantPaymentItem(
			r.Context(), platform, externalID, orderID, item,
			firstPaymentValue(params, "item_price", "amount"),
		)
		if err != nil {
			log.Printf("[PAY] grant failed platform=%s order=%s: %v", platform, orderID, err)
			paymentErrorResponse(w, 30, "grant failed")
			return
		}
		log.Printf("[PAY] %s platform=%s user=%s item=%s shards=%d order=%s new=%d",
			map[bool]string{true: "granted", false: "duplicate"}[granted],
			platform, externalID, item.ItemID, item.Shards, orderID, newShards)
		writeJSON(w, http.StatusOK, paymentOrderResponse(orderID))
	default:
		paymentErrorResponse(w, 1, "Unknown type")
	}
}

// handleOKPay receives OK callbacks.payment (GET or POST, no status field) and
// always answers with valid JSON; the proven OK flow requires 200 even for
// unknown requests.
func (service *api) handleOKPay(w http.ResponseWriter, r *http.Request) {
	params := paymentParams(r)
	method := strings.TrimSpace(params["method"])
	itemID := firstPaymentValue(params, "product_code", "item_id", "item")
	externalID := firstPaymentValue(params, "uid", "user_id", "receiver_id")
	orderID := firstPaymentValue(params, "transaction_id", "order_id")
	isPayment := method == "callbacks.payment" ||
		(strings.TrimSpace(params["notification_type"]) == "order_status_change") ||
		(itemID != "" && externalID != "" && orderID != "" && params["amount"] != "")
	if !isPayment {
		writeJSON(w, http.StatusOK, map[string]any{"status": "ok"})
		return
	}
	item, found := vkPaymentItem(itemID)
	if !found {
		log.Printf("[OK-PAY] unknown item=%q", itemID)
		writeJSON(w, http.StatusOK, map[string]any{"response": map[string]any{
			"order_id": orderID, "app_order_id": time.Now().UnixMilli(),
		}})
		return
	}
	newShards, granted, err := service.grantPaymentItem(
		r.Context(), "ok", externalID, orderID, item, firstPaymentValue(params, "amount", "item_price"),
	)
	if err != nil {
		log.Printf("[OK-PAY] grant failed order=%s: %v", orderID, err)
	}
	log.Printf("[OK-PAY] %s user=%s item=%s shards=%d order=%s new=%d",
		map[bool]string{true: "granted", false: "duplicate"}[granted],
		externalID, item.ItemID, item.Shards, orderID, newShards)
	writeJSON(w, http.StatusOK, map[string]any{"response": map[string]any{
		"order_id": orderID, "app_order_id": time.Now().UnixMilli(),
	}})
}

// grantPaymentItem creates/loads the platform profile, records the order once
// (unique platform+order_id), and adds shards. Duplicate callbacks do not grant
// twice. The client never adds shards locally.
func (service *api) grantPaymentItem(
	ctx context.Context,
	platform, externalID, orderID string, item paymentItem, amountText string,
) (int, bool, error) {
	if service.db == nil {
		return 0, false, errors.New("database unavailable")
	}
	externalID = strings.TrimSpace(externalID)
	orderID = strings.TrimSpace(orderID)
	if externalID == "" || orderID == "" {
		return 0, false, errors.New("missing user or order")
	}
	price := item.Price
	if parsed, err := strconv.Atoi(strings.TrimSpace(amountText)); err == nil && parsed > 0 {
		price = parsed
	}
	var profile vkProfileRow
	var err error
	if platform == "ok" {
		profile, err = service.upsertOKProfile(ctx, externalID, "")
	} else {
		profile, err = service.upsertVKProfile(ctx, externalID, "")
	}
	if err != nil {
		return 0, false, err
	}

	transaction, err := service.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, false, err
	}
	defer transaction.Rollback()

	result, err := transaction.ExecContext(ctx, `
		INSERT INTO payments (platform, external_id, order_id, item_id, shards, amount)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT (platform, order_id) DO NOTHING
	`, platform, externalID, orderID, item.ItemID, item.Shards, price)
	if err != nil {
		return 0, false, err
	}
	inserted, err := result.RowsAffected()
	if err != nil {
		return 0, false, err
	}
	if inserted == 0 {
		_ = transaction.Rollback()
		return profile.shards, false, nil
	}
	var newShards int
	if err := transaction.QueryRowContext(ctx,
		`UPDATE players SET sky_shards = COALESCE(sky_shards, 0) + $1 WHERE id = $2 RETURNING COALESCE(sky_shards, 0)`,
		item.Shards, profile.id,
	).Scan(&newShards); err != nil {
		return 0, false, err
	}
	if err := transaction.Commit(); err != nil {
		return 0, false, err
	}
	return newShards, true, nil
}

func createPaymentsTable(ctx context.Context, db *sql.DB) error {
	_, err := db.ExecContext(ctx, `
		CREATE TABLE IF NOT EXISTS payments (
			id SERIAL PRIMARY KEY,
			platform TEXT NOT NULL,
			external_id TEXT NOT NULL,
			order_id TEXT NOT NULL,
			item_id TEXT NOT NULL,
			shards INTEGER NOT NULL,
			amount INTEGER NOT NULL DEFAULT 0,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			UNIQUE (platform, order_id)
		)
	`)
	return err
}
