idf_component_register(
    SRCS "mac_transport.c"
    INCLUDE_DIRS "include"
    REQUIRES ui ota_updater esp_wifi esp_event esp_netif esp-tls esp_app_format json nvs_flash mdns mbedtls
)
