idf_component_register(
    SRCS "weather_client.c"
    INCLUDE_DIRS "include"
    REQUIRES weather_model transport clock_sync esp_http_client mbedtls json nvs_flash
)
