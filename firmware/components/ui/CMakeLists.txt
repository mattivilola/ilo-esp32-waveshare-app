idf_component_register(
    SRCS "dashboard_model.c" "dashboard_ui.c" "assets/ilo_icon_48.c"
    INCLUDE_DIRS "include" "assets"
    REQUIRES board_waveshare_5 device_settings weather_model esp_app_format esp_lvgl_port lvgl esp_lcd
)

target_compile_options(${COMPONENT_LIB} PRIVATE -Wno-missing-field-initializers)
