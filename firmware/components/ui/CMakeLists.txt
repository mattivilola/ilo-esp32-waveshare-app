idf_component_register(
    SRCS "dashboard_model.c" "dashboard_ui.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_lvgl_port lvgl esp_lcd
)

target_compile_options(${COMPONENT_LIB} PRIVATE -Wno-missing-field-initializers)
