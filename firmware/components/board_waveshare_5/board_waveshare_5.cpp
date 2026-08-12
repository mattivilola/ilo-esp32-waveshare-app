#include "board_waveshare_5.h"

#include "driver/gpio.h"
#include "driver/i2c_master.h"
#include "esp_check.h"
#include "esp_lcd_io_i2c.h"
#include "esp_lcd_panel_rgb.h"
#include "esp_lcd_touch.h"
#include "esp_lcd_touch_gt911.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "board_waveshare_5";
static constexpr int I2C_PORT = 0;
static constexpr int I2C_SDA = 8;
static constexpr int I2C_SCL = 9;
static constexpr int TOUCH_INTERRUPT = 4;
static constexpr uint32_t I2C_SPEED_HZ = 400000;

// CH422G command addresses are separate I2C slave addresses, not registers.
static constexpr uint16_t CH422G_WRITE_SET_ADDRESS = 0x24;
static constexpr uint16_t CH422G_WRITE_IO_ADDRESS = 0x38;
static constexpr uint8_t CH422G_BACKLIGHT_MASK = 1U << 2;

static i2c_master_bus_handle_t i2c_bus;
static i2c_master_dev_handle_t ch422g_set_device;
static i2c_master_dev_handle_t ch422g_io_device;
static esp_lcd_panel_handle_t lcd_panel;
static esp_lcd_panel_io_handle_t touch_io;
static esp_lcd_touch_handle_t touch_panel;
static esp_lcd_touch_io_gt911_config_t touch_driver_config;
static bool initialized;
static bool backlight_enabled;

static esp_err_t add_i2c_device(uint16_t address, i2c_master_dev_handle_t *device)
{
    i2c_device_config_t config = {};
    config.dev_addr_length = I2C_ADDR_BIT_LEN_7;
    config.device_address = address;
    config.scl_speed_hz = I2C_SPEED_HZ;
    return i2c_master_bus_add_device(i2c_bus, &config, device);
}

static esp_err_t ch422g_write(i2c_master_dev_handle_t device, uint8_t value)
{
    return i2c_master_transmit(device, &value, sizeof(value), 1000);
}

static esp_err_t ch422g_write_backlight_off(uint8_t value)
{
    // Preserve Waveshare's reset patterns while holding the independent
    // EXIO2/DISP output low until LVGL has rendered its first useful frame.
    return ch422g_write(ch422g_io_device, value & (uint8_t)~CH422G_BACKLIGHT_MASK);
}

static esp_err_t init_i2c_and_expander(void)
{
    i2c_master_bus_config_t bus_config = {};
    bus_config.i2c_port = I2C_PORT;
    bus_config.sda_io_num = static_cast<gpio_num_t>(I2C_SDA);
    bus_config.scl_io_num = static_cast<gpio_num_t>(I2C_SCL);
    bus_config.clk_source = I2C_CLK_SRC_DEFAULT;
    bus_config.glitch_ignore_cnt = 7;
    bus_config.flags.enable_internal_pullup = true;
    ESP_RETURN_ON_ERROR(i2c_new_master_bus(&bus_config, &i2c_bus), TAG, "I2C bus initialization failed");
    ESP_RETURN_ON_ERROR(add_i2c_device(CH422G_WRITE_SET_ADDRESS, &ch422g_set_device), TAG,
                        "CH422G mode device initialization failed");
    ESP_RETURN_ON_ERROR(add_i2c_device(CH422G_WRITE_IO_ADDRESS, &ch422g_io_device), TAG,
                        "CH422G output device initialization failed");

    // Exact command used by Waveshare to enable the CH422G push-pull outputs.
    return ch422g_write(ch422g_set_device, 0x01);
}

static esp_err_t reset_lcd_and_touch(void)
{
    // Waveshare maps LCD_RST to EXIO3. Preserve its published output pattern.
    ESP_RETURN_ON_ERROR(ch422g_write_backlight_off(0x26), TAG, "LCD reset low failed");
    vTaskDelay(pdMS_TO_TICKS(10));
    ESP_RETURN_ON_ERROR(ch422g_write_backlight_off(0x2E), TAG, "LCD reset high failed");
    vTaskDelay(pdMS_TO_TICKS(100));

    // GT911 address selection: IRQ low while EXIO1 releases reset selects 0x5D.
    ESP_RETURN_ON_ERROR(gpio_set_direction(static_cast<gpio_num_t>(TOUCH_INTERRUPT), GPIO_MODE_OUTPUT), TAG,
                        "Touch interrupt output setup failed");
    ESP_RETURN_ON_ERROR(gpio_set_level(static_cast<gpio_num_t>(TOUCH_INTERRUPT), 0), TAG,
                        "Touch interrupt address select failed");
    vTaskDelay(pdMS_TO_TICKS(10));
    ESP_RETURN_ON_ERROR(ch422g_write_backlight_off(0x2C), TAG, "Touch reset low failed");
    vTaskDelay(pdMS_TO_TICKS(100));
    ESP_RETURN_ON_ERROR(ch422g_write_backlight_off(0x2E), TAG, "Touch reset high failed");
    vTaskDelay(pdMS_TO_TICKS(200));
    return gpio_reset_pin(static_cast<gpio_num_t>(TOUCH_INTERRUPT));
}

static esp_err_t init_rgb_panel(void)
{
    esp_lcd_rgb_panel_config_t config = {};
    config.clk_src = LCD_CLK_SRC_DEFAULT;
    config.timings.pclk_hz = 21 * 1000 * 1000;
    config.timings.h_res = ILO_BOARD_WIDTH;
    config.timings.v_res = ILO_BOARD_HEIGHT;
    config.timings.hsync_pulse_width = 24;
    config.timings.hsync_back_porch = 160;
    config.timings.hsync_front_porch = 160;
    config.timings.vsync_pulse_width = 2;
    config.timings.vsync_back_porch = 23;
    config.timings.vsync_front_porch = 12;
    config.timings.flags.pclk_active_neg = true;
    config.data_width = 16;
    config.bits_per_pixel = 16;
    config.num_fbs = 2;
    config.bounce_buffer_size_px = ILO_BOARD_WIDTH * 10;
    config.dma_burst_size = 64;
    config.hsync_gpio_num = 46;
    config.vsync_gpio_num = 3;
    config.de_gpio_num = 5;
    config.pclk_gpio_num = 7;
    config.disp_gpio_num = GPIO_NUM_NC;
    const int data_pins[16] = {14, 38, 18, 17, 10, 39, 0, 45, 48, 47, 21, 1, 2, 42, 41, 40};
    for (int index = 0; index < 16; ++index) {
        config.data_gpio_nums[index] = data_pins[index];
    }
    config.flags.fb_in_psram = true;

    ESP_RETURN_ON_ERROR(esp_lcd_new_rgb_panel(&config, &lcd_panel), TAG, "RGB panel creation failed");
    return esp_lcd_panel_init(lcd_panel);
}

static esp_err_t init_touch(void)
{
    // Assign fields explicitly because the component macro uses C designators
    // in an order that C++ correctly rejects.
    esp_lcd_panel_io_i2c_config_t io_config = {};
    io_config.dev_addr = ESP_LCD_TOUCH_IO_I2C_GT911_ADDRESS;
    io_config.scl_speed_hz = I2C_SPEED_HZ;
    io_config.control_phase_bytes = 1;
    io_config.dc_bit_offset = 0;
    io_config.lcd_cmd_bits = 16;
    io_config.flags.disable_control_phase = true;
    ESP_RETURN_ON_ERROR(esp_lcd_new_panel_io_i2c(i2c_bus, &io_config, &touch_io), TAG,
                        "GT911 I2C panel IO creation failed");

    touch_driver_config.dev_addr = io_config.dev_addr;
    esp_lcd_touch_config_t touch_config = {};
    touch_config.x_max = ILO_BOARD_WIDTH;
    touch_config.y_max = ILO_BOARD_HEIGHT;
    touch_config.rst_gpio_num = GPIO_NUM_NC;
    touch_config.int_gpio_num = static_cast<gpio_num_t>(TOUCH_INTERRUPT);
    touch_config.levels.reset = 0;
    touch_config.levels.interrupt = 0;
    touch_config.driver_data = &touch_driver_config;
    return esp_lcd_touch_new_i2c_gt911(touch_io, &touch_config, &touch_panel);
}

extern "C" esp_err_t board_waveshare_5_init(void)
{
    if (initialized) {
        return ESP_OK;
    }

    ESP_RETURN_ON_ERROR(init_i2c_and_expander(), TAG, "I2C/CH422G startup failed");
    ESP_RETURN_ON_ERROR(reset_lcd_and_touch(), TAG, "Panel reset sequence failed");
    ESP_RETURN_ON_ERROR(init_rgb_panel(), TAG, "LCD startup failed");
    ESP_RETURN_ON_ERROR(init_touch(), TAG, "Touch startup failed");
    // Leave DISP low until the application explicitly presents a rendered
    // LVGL frame. This avoids exposing uninitialized framebuffer contents.
    ESP_RETURN_ON_ERROR(ch422g_write(ch422g_io_device, 0x1A), TAG, "Backlight hold-off failed");
    backlight_enabled = false;

    initialized = true;
    ESP_LOGI(TAG, "Waveshare 5B 1024x600 display and GT911 touch initialized");
    return ESP_OK;
}

extern "C" esp_lcd_panel_handle_t board_waveshare_5_lcd(void)
{
    return lcd_panel;
}

extern "C" bool board_waveshare_5_read_touch(uint16_t *x, uint16_t *y)
{
    if (touch_panel == nullptr || x == nullptr || y == nullptr) {
        return false;
    }
    if (esp_lcd_touch_read_data(touch_panel) != ESP_OK) {
        return false;
    }
    esp_lcd_touch_point_data_t point = {};
    uint8_t count = 0;
    if (esp_lcd_touch_get_data(touch_panel, &point, &count, 1) != ESP_OK || count == 0) {
        return false;
    }
    *x = point.x;
    *y = point.y;
    return true;
}

extern "C" esp_err_t board_waveshare_5_set_backlight(bool enabled)
{
    if (!initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    if (enabled == backlight_enabled) {
        return ESP_OK;
    }
    // DISP is CH422G EXIO2 on this exact Waveshare 5B profile. It is a
    // binary enable line, not a PWM brightness channel.
    esp_err_t status = ch422g_write(ch422g_io_device, enabled ? 0x1E : 0x1A);
    if (status == ESP_OK) {
        backlight_enabled = enabled;
    }
    return status;
}

extern "C" bool board_waveshare_5_backlight_enabled(void)
{
    return backlight_enabled;
}
