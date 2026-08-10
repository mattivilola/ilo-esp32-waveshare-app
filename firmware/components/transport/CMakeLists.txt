idf_component_register(
    SRCS "mac_transport.c"
    INCLUDE_DIRS "include"
    REQUIRES ui esp_wifi esp_event esp_netif esp-tls json nvs_flash mdns mbedtls
)
