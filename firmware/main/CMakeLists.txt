idf_component_register(
    SRCS "main.cpp"
    INCLUDE_DIRS "."
    REQUIRES board_waveshare_5 ui transport clock_sync weather_client ota_policy nvs_flash esp_timer
)

target_compile_options(${COMPONENT_LIB} PRIVATE -Wno-missing-field-initializers)
