idf_component_register(
    SRCS "ota_policy.c"
    INCLUDE_DIRS "include"
    REQUIRES app_update esp_partition esp_system freertos heap
)
