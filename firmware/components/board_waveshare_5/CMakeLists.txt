idf_component_register(
    SRCS "board_waveshare_5.cpp"
    INCLUDE_DIRS "include"
    REQUIRES esp_driver_gpio esp_driver_i2c esp_lcd esp_lcd_touch esp_lcd_touch_gt911
)

target_compile_options(${COMPONENT_LIB} PRIVATE -Wno-missing-field-initializers)
