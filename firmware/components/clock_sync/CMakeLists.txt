idf_component_register(
    SRCS "clock_sync.c"
    INCLUDE_DIRS "include"
    REQUIRES transport esp_netif
)
