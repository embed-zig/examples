#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"

#include "esp_err.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "esp_wifi.h"
#include "esp_wifi_default.h"
#include "nvs.h"
#include "nvs_flash.h"

#define WIFI_CONNECTED_BIT BIT0
#define WIFI_FAIL_BIT BIT1
#define WIFI_MAX_RETRIES 8

typedef struct {
    EventGroupHandle_t event_group;
    int retries;
} wifi_connect_state_t;

static size_t cstr_len(const char *value)
{
    size_t len = 0;
    while (value[len] != '\0') {
        len += 1;
    }
    return len;
}

static void copy_u8_string(uint8_t *dst, size_t dst_len, const char *src, size_t src_len)
{
    size_t i = 0;
    for (; i < src_len && i + 1 < dst_len; i += 1) {
        dst[i] = (uint8_t)src[i];
    }
    if (dst_len > 0) {
        dst[i] = 0;
    }
}

static void wifi_event_handler(void *arg, esp_event_base_t event_base, int32_t event_id, void *event_data)
{
    (void)event_data;

    wifi_connect_state_t *state = (wifi_connect_state_t *)arg;
    if (state == NULL) {
        return;
    }

    if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_DISCONNECTED) {
        if (state->retries < WIFI_MAX_RETRIES) {
            state->retries += 1;
            (void)esp_wifi_connect();
            return;
        }
        xEventGroupSetBits(state->event_group, WIFI_FAIL_BIT);
        return;
    }

    if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
        xEventGroupSetBits(state->event_group, WIFI_CONNECTED_BIT);
    }
}

static esp_err_t ensure_nvs_initialized(void)
{
    esp_err_t rc = nvs_flash_init();
    if (rc == ESP_ERR_NVS_NO_FREE_PAGES || rc == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        rc = nvs_flash_erase();
        if (rc != ESP_OK) {
            return rc;
        }
        rc = nvs_flash_init();
    }
    return rc;
}

int32_t espz_test_wifi_connect(const char *ssid, const char *password, int32_t timeout_ms)
{
    if (ssid == NULL || password == NULL || timeout_ms <= 0) {
        return ESP_ERR_INVALID_ARG;
    }

    const size_t ssid_len = cstr_len(ssid);
    const size_t password_len = cstr_len(password);
    if (ssid_len == 0 || ssid_len >= sizeof(((wifi_config_t *)0)->sta.ssid)) {
        return ESP_ERR_INVALID_ARG;
    }
    if (password_len >= sizeof(((wifi_config_t *)0)->sta.password)) {
        return ESP_ERR_INVALID_ARG;
    }

    esp_err_t rc = ensure_nvs_initialized();
    if (rc != ESP_OK) {
        return rc;
    }

    rc = esp_netif_init();
    if (rc != ESP_OK && rc != ESP_ERR_INVALID_STATE) {
        return rc;
    }

    rc = esp_event_loop_create_default();
    if (rc != ESP_OK && rc != ESP_ERR_INVALID_STATE) {
        return rc;
    }

    esp_netif_create_default_wifi_sta();

    wifi_init_config_t init_cfg = WIFI_INIT_CONFIG_DEFAULT();
    rc = esp_wifi_init(&init_cfg);
    if (rc != ESP_OK && rc != ESP_ERR_INVALID_STATE) {
        return rc;
    }

    rc = esp_wifi_set_mode(WIFI_MODE_STA);
    if (rc != ESP_OK) {
        return rc;
    }

    wifi_config_t wifi_cfg = {0};
    copy_u8_string(wifi_cfg.sta.ssid, sizeof(wifi_cfg.sta.ssid), ssid, ssid_len);
    copy_u8_string(wifi_cfg.sta.password, sizeof(wifi_cfg.sta.password), password, password_len);
    wifi_cfg.sta.pmf_cfg.capable = true;
    wifi_cfg.sta.pmf_cfg.required = false;

    rc = esp_wifi_set_config(WIFI_IF_STA, &wifi_cfg);
    if (rc != ESP_OK) {
        return rc;
    }

    wifi_connect_state_t state = {
        .event_group = xEventGroupCreate(),
        .retries = 0,
    };
    if (state.event_group == NULL) {
        return ESP_ERR_NO_MEM;
    }

    rc = esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, &state);
    if (rc != ESP_OK) {
        vEventGroupDelete(state.event_group);
        return rc;
    }

    rc = esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, &wifi_event_handler, &state);
    if (rc != ESP_OK) {
        (void)esp_event_handler_unregister(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler);
        vEventGroupDelete(state.event_group);
        return rc;
    }

    rc = esp_wifi_start();
    if (rc != ESP_OK && rc != ESP_ERR_WIFI_CONN && rc != ESP_ERR_INVALID_STATE) {
        (void)esp_event_handler_unregister(IP_EVENT, IP_EVENT_STA_GOT_IP, &wifi_event_handler);
        (void)esp_event_handler_unregister(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler);
        vEventGroupDelete(state.event_group);
        return rc;
    }

    rc = esp_wifi_connect();
    if (rc != ESP_OK) {
        (void)esp_event_handler_unregister(IP_EVENT, IP_EVENT_STA_GOT_IP, &wifi_event_handler);
        (void)esp_event_handler_unregister(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler);
        vEventGroupDelete(state.event_group);
        return rc;
    }

    const EventBits_t bits = xEventGroupWaitBits(
        state.event_group,
        WIFI_CONNECTED_BIT | WIFI_FAIL_BIT,
        pdFALSE,
        pdFALSE,
        pdMS_TO_TICKS(timeout_ms)
    );

    (void)esp_event_handler_unregister(IP_EVENT, IP_EVENT_STA_GOT_IP, &wifi_event_handler);
    (void)esp_event_handler_unregister(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler);
    vEventGroupDelete(state.event_group);

    if ((bits & WIFI_CONNECTED_BIT) != 0) {
        return ESP_OK;
    }
    if ((bits & WIFI_FAIL_BIT) != 0) {
        return ESP_FAIL;
    }
    return ESP_ERR_TIMEOUT;
}
