idf_component_register(
    SRCS "weather_client.c"
    INCLUDE_DIRS "include"
    REQUIRES weather_model transport esp_http_client esp_netif mbedtls json nvs_flash
)
