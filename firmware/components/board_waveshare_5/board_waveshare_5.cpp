#include "board_waveshare_5.h"

#include <new>

#include "esp_display_panel.hpp"
#include "esp_log.h"

using esp_panel::board::Board;
using esp_panel::drivers::BusRGB;
using esp_panel::drivers::TouchPoint;

static const char *TAG = "board_waveshare_5";
static Board *board;

extern "C" esp_err_t board_waveshare_5_init(void)
{
    if (board != nullptr) {
        return ESP_OK;
    }

    board = new (std::nothrow) Board();
    if (board == nullptr) {
        return ESP_ERR_NO_MEM;
    }
    if (!board->init()) {
        ESP_LOGE(TAG, "Board configuration initialization failed");
        return ESP_FAIL;
    }

    auto lcd = board->getLCD();
    if (lcd == nullptr) {
        ESP_LOGE(TAG, "Configured board has no LCD");
        return ESP_ERR_NOT_FOUND;
    }
    lcd->configFrameBufferNumber(2);
    auto bus = lcd->getBus();
    if (bus != nullptr && bus->getBasicAttributes().type == ESP_PANEL_BUS_TYPE_RGB) {
        static_cast<BusRGB *>(bus)->configRGB_BounceBufferSize(ILO_BOARD_WIDTH * 10);
    }

    if (!board->begin()) {
        ESP_LOGE(TAG, "LCD, touch, backlight, or IO-expander startup failed");
        return ESP_FAIL;
    }

    ESP_LOGI(TAG, "Waveshare 800x480 display and GT911 touch initialized");
    return ESP_OK;
}

extern "C" esp_lcd_panel_handle_t board_waveshare_5_lcd(void)
{
    return board != nullptr && board->getLCD() != nullptr
        ? board->getLCD()->getRefreshPanelHandle()
        : nullptr;
}

extern "C" bool board_waveshare_5_read_touch(uint16_t *x, uint16_t *y)
{
    if (board == nullptr || board->getTouch() == nullptr || x == nullptr || y == nullptr) {
        return false;
    }
    TouchPoint point;
    if (board->getTouch()->readPoints(&point, 1, 0) < 1) {
        return false;
    }
    *x = static_cast<uint16_t>(point.x);
    *y = static_cast<uint16_t>(point.y);
    return true;
}
