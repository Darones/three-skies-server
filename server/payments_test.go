package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

func TestVKPaymentItemCatalog(t *testing.T) {
	for _, sku := range []string{"shards_100", "shards_500", "shards_10000"} {
		item, ok := vkPaymentItem(sku)
		if !ok {
			t.Fatalf("%s should be a valid item", sku)
		}
		if item.Shards != item.Price*100 {
			t.Fatalf("%s: shards=%d price=%d", sku, item.Shards, item.Price)
		}
	}
	for _, sku := range []string{"", "shards_50", "shards_150", "shards_20000", "coins_100"} {
		if _, ok := vkPaymentItem(sku); ok {
			t.Fatalf("%s should be rejected", sku)
		}
	}
}

func TestVKPaymentSignature(t *testing.T) {
	t.Setenv("VK_APP_SECRET", "test_secret")
	params := map[string]string{
		"app_id":            vkAppID(),
		"notification_type": "get_item",
		"item":              "shards_500",
		"user_id":           "42",
	}
	params["sig"] = vkPaymentSignature(params, "test_secret")
	if !verifyVKPaymentSignature(params, "test_secret") {
		t.Fatal("valid payment signature was rejected")
	}
	params["item"] = "shards_1000"
	if verifyVKPaymentSignature(params, "test_secret") {
		t.Fatal("tampered payment signature was accepted")
	}
	if verifyVKPaymentSignature(params, "") {
		t.Fatal("empty secret must not verify")
	}
}

func TestHandleVKPayGetItem(t *testing.T) {
	t.Setenv("VK_APP_SECRET", "test_secret")
	t.Setenv("PUBLIC_BASE_URL", "https://example.test")
	params := map[string]string{
		"app_id":            vkAppID(),
		"notification_type": "get_item",
		"item":              "shards_500",
		"user_id":           "42",
	}
	params["sig"] = vkPaymentSignature(params, "test_secret")
	recorder := httptest.NewRecorder()
	(&api{}).handleVKPay(recorder, paymentRequest("/vk/pay", params))
	if recorder.Code != http.StatusOK {
		t.Fatalf("status=%d", recorder.Code)
	}
	var body struct {
		Response struct {
			Title    string `json:"title"`
			Price    int    `json:"price"`
			PhotoURL string `json:"photo_url"`
			ItemID   string `json:"item_id"`
		} `json:"response"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatalf("json: %v (%s)", err, recorder.Body.String())
	}
	if body.Response.ItemID != "shards_500" || body.Response.Price != 5 {
		t.Fatalf("unexpected item: %+v", body.Response)
	}
	if body.Response.PhotoURL != "https://example.test/game/shard.png" {
		t.Fatalf("photo_url=%q", body.Response.PhotoURL)
	}
}

func TestHandleVKPayOKGetItemSkipsSignature(t *testing.T) {
	params := map[string]string{
		"site":              "OK",
		"app_id":            okAppID(),
		"method":            "callbacks.getCustomProductInfo",
		"notification_type": "get_item",
		"item":              "shards_300",
		"user_id":           "ok-user",
	}
	recorder := httptest.NewRecorder()
	(&api{}).handleVKPay(recorder, paymentRequest("/vk/pay", params))
	if recorder.Code != http.StatusOK {
		t.Fatalf("status=%d", recorder.Code)
	}
	var body struct {
		Response struct {
			Price  int    `json:"price"`
			ItemID string `json:"item_id"`
		} `json:"response"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatalf("json: %v", err)
	}
	if body.Response.Price != 3 || body.Response.ItemID != "shards_300" {
		t.Fatalf("unexpected OK item: %+v", body.Response)
	}
}

func TestHandleVKPayRejectsBadSignature(t *testing.T) {
	t.Setenv("VK_APP_SECRET", "test_secret")
	params := map[string]string{
		"app_id":            vkAppID(),
		"notification_type": "get_item",
		"item":              "shards_500",
		"user_id":           "42",
		"sig":               "bad",
	}
	recorder := httptest.NewRecorder()
	(&api{}).handleVKPay(recorder, paymentRequest("/vk/pay", params))
	if recorder.Code != http.StatusOK {
		t.Fatalf("status=%d", recorder.Code)
	}
	var body struct {
		Error struct {
			Code int `json:"error_code"`
		} `json:"error"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatalf("json: %v", err)
	}
	if body.Error.Code != 10 {
		t.Fatalf("unexpected error: %+v", body)
	}
}

func TestHandleOKPayFallback(t *testing.T) {
	recorder := httptest.NewRecorder()
	(&api{}).handleOKPay(recorder, paymentRequest("/ok/pay", map[string]string{}))
	if recorder.Code != http.StatusOK {
		t.Fatalf("status=%d", recorder.Code)
	}
	if strings.TrimSpace(recorder.Body.String()) != `{"status":"ok"}` {
		t.Fatalf("body=%s", recorder.Body.String())
	}
}

func paymentRequest(path string, params map[string]string) *http.Request {
	form := url.Values{}
	for key, value := range params {
		form.Set(key, value)
	}
	request := httptest.NewRequest(http.MethodPost, path, strings.NewReader(form.Encode()))
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	return request
}
