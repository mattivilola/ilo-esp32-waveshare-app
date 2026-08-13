idf_component_register(
    SRCS "dashboard_model.c" "dashboard_ui.c" "lando_screensaver.c"
    INCLUDE_DIRS "include" "assets"
    EMBED_FILES "assets/lando_screensaver.rgb565"
    REQUIRES board_waveshare_5 device_settings focus_session weather_model esp_app_format esp_lvgl_port lvgl esp_lcd
)

target_compile_options(${COMPONENT_LIB} PRIVATE -Wno-missing-field-initializers)
