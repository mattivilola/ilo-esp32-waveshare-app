cmake_minimum_required(VERSION 3.16)

set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CMAKE_CURRENT_LIST_DIR}/version.txt")
file(STRINGS "${CMAKE_CURRENT_LIST_DIR}/version.txt" PROJECT_VER LIMIT_COUNT 1)
string(STRIP "${PROJECT_VER}" PROJECT_VER)
if(NOT PROJECT_VER MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+$")
    message(FATAL_ERROR "firmware/version.txt must contain one major.minor.patch version")
endif()

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(ilo_board)

# LVGL's built-in allocator normally reserves its pool in internal BSS. The
# dashboard needs more room than that without starving Wi-Fi's DMA buffers, so
# compile only LVGL with a pool allocator backed explicitly by external PSRAM.
idf_component_get_property(lvgl_component lvgl__lvgl COMPONENT_LIB)
target_include_directories(${lvgl_component} PRIVATE "${CMAKE_CURRENT_LIST_DIR}/components/ui/include")
target_compile_definitions(${lvgl_component} PRIVATE LV_MEM_POOL_INCLUDE=\"lvgl_psram_pool.h\")
