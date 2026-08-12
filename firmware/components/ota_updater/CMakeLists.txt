idf_component_register(
    SRCS "ota_updater.c"
    INCLUDE_DIRS "include"
    REQUIRES app_update esp_http_client esp-tls esp_event esp_netif esp_wifi json mbedtls nvs_flash ota_policy
)

if(CONFIG_ILO_OTA_DELIVERY)
    if("$ENV{ILO_BOARD_FIRMWARE_PUBLIC_KEY}" STREQUAL "")
        message(FATAL_ERROR "ILO_OTA_DELIVERY requires ILO_BOARD_FIRMWARE_PUBLIC_KEY")
    endif()
    if(NOT EXISTS "$ENV{ILO_BOARD_FIRMWARE_PUBLIC_KEY}")
        message(FATAL_ERROR "ILO_BOARD_FIRMWARE_PUBLIC_KEY does not exist")
    endif()
    configure_file(
        "$ENV{ILO_BOARD_FIRMWARE_PUBLIC_KEY}"
        "${CMAKE_CURRENT_BINARY_DIR}/ota_manifest_public_key.pem"
        COPYONLY
    )
    target_add_binary_data(${COMPONENT_LIB} "${CMAKE_CURRENT_BINARY_DIR}/ota_manifest_public_key.pem" TEXT)
endif()
