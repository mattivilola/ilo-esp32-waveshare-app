idf_component_register(
    SRCS "clock_sync.c"
    INCLUDE_DIRS "include"
    REQUIRES board_waveshare_5 transport esp_netif
)
