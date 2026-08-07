idf_component_register(
    SRCS "board_waveshare_5.cpp"
    INCLUDE_DIRS "include"
    REQUIRES esp32_display_panel
)

target_compile_options(${COMPONENT_LIB} PRIVATE -Wno-missing-field-initializers)
