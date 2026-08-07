#include "dashboard_ui.h"

#include <stdio.h>

#include "esp_check.h"
#include "esp_lvgl_port.h"
#include "lvgl.h"
#include "board_waveshare_5.h"

#define COLOR_CARBON  lv_color_hex(0x0A0F14)
#define COLOR_SLATE   lv_color_hex(0x131B22)
#define COLOR_STEEL   lv_color_hex(0x24313C)
#define COLOR_SIGNAL  lv_color_hex(0x65E5B8)
#define COLOR_AMBER   lv_color_hex(0xFFB55A)
#define COLOR_MIST    lv_color_hex(0xF3F7F8)
#define COLOR_FOG     lv_color_hex(0x8EA2B2)

static lv_obj_t *connection_label;
static lv_obj_t *attention_count_label;
static lv_obj_t *attention_hint_label;
static lv_obj_t *task_rows[DASHBOARD_MAX_TASKS];
static lv_obj_t *task_titles[DASHBOARD_MAX_TASKS];
static lv_obj_t *task_summaries[DASHBOARD_MAX_TASKS];
static lv_obj_t *task_dots[DASHBOARD_MAX_TASKS];

static void touch_read(lv_indev_t *input, lv_indev_data_t *data)
{
    (void)input;
    uint16_t x = 0;
    uint16_t y = 0;
    if (board_waveshare_5_read_touch(&x, &y)) {
        data->point.x = x;
        data->point.y = y;
        data->state = LV_INDEV_STATE_PRESSED;
    } else {
        data->state = LV_INDEV_STATE_RELEASED;
    }
}

static void set_clean_box(lv_obj_t *object, lv_color_t color, int radius)
{
    lv_obj_set_style_bg_color(object, color, 0);
    lv_obj_set_style_bg_opa(object, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(object, 0, 0);
    lv_obj_set_style_radius(object, radius, 0);
    lv_obj_set_style_pad_all(object, 0, 0);
}

static void attention_tapped(lv_event_t *event)
{
    if (lv_event_get_code(event) != LV_EVENT_CLICKED || attention_hint_label == NULL) {
        return;
    }
    lv_label_set_text(attention_hint_label, "Touch input ready\nActions stay on Mac");
    lv_obj_set_style_text_color(attention_hint_label, COLOR_SIGNAL, 0);
}

static void build_ui(void)
{
    lv_obj_t *screen = lv_screen_active();
    set_clean_box(screen, COLOR_CARBON, 0);
    lv_obj_set_scrollbar_mode(screen, LV_SCROLLBAR_MODE_OFF);

    lv_obj_t *rail = lv_obj_create(screen);
    set_clean_box(rail, COLOR_SIGNAL, 0);
    lv_obj_set_size(rail, 6, 480);
    lv_obj_align(rail, LV_ALIGN_LEFT_MID, 0, 0);

    lv_obj_t *header = lv_obj_create(screen);
    set_clean_box(header, COLOR_CARBON, 0);
    lv_obj_set_size(header, 770, 64);
    lv_obj_align(header, LV_ALIGN_TOP_LEFT, 22, 0);

    lv_obj_t *eyebrow = lv_label_create(header);
    lv_label_set_text(eyebrow, "ILO / WORK PULSE");
    lv_obj_set_style_text_color(eyebrow, COLOR_SIGNAL, 0);
    lv_obj_set_style_text_font(eyebrow, &lv_font_montserrat_14, 0);
    lv_obj_align(eyebrow, LV_ALIGN_LEFT_MID, 0, 0);

    connection_label = lv_label_create(header);
    lv_label_set_text(connection_label, "Mac not configured");
    lv_obj_set_style_text_color(connection_label, COLOR_FOG, 0);
    lv_obj_set_style_text_font(connection_label, &lv_font_montserrat_14, 0);
    lv_obj_align(connection_label, LV_ALIGN_RIGHT_MID, 0, 0);

    lv_obj_t *attention = lv_obj_create(screen);
    set_clean_box(attention, COLOR_SLATE, 18);
    lv_obj_set_size(attention, 192, 344);
    lv_obj_align(attention, LV_ALIGN_BOTTOM_LEFT, 22, -24);
    lv_obj_add_flag(attention, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_event_cb(attention, attention_tapped, LV_EVENT_CLICKED, NULL);

    lv_obj_t *attention_title = lv_label_create(attention);
    lv_label_set_text(attention_title, "ATTENTION");
    lv_obj_set_style_text_color(attention_title, COLOR_FOG, 0);
    lv_obj_set_style_text_font(attention_title, &lv_font_montserrat_14, 0);
    lv_obj_align(attention_title, LV_ALIGN_TOP_LEFT, 20, 22);

    attention_count_label = lv_label_create(attention);
    lv_label_set_text(attention_count_label, "0");
    lv_obj_set_style_text_color(attention_count_label, COLOR_MIST, 0);
    lv_obj_set_style_text_font(attention_count_label, &lv_font_montserrat_28, 0);
    lv_obj_align(attention_count_label, LV_ALIGN_TOP_LEFT, 20, 60);

    attention_hint_label = lv_label_create(attention);
    lv_label_set_text(attention_hint_label, "Tap to test touch\nRemote actions off");
    lv_obj_set_style_text_color(attention_hint_label, COLOR_FOG, 0);
    lv_obj_set_style_text_font(attention_hint_label, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_line_space(attention_hint_label, 8, 0);
    lv_obj_align(attention_hint_label, LV_ALIGN_BOTTOM_LEFT, 20, -22);

    lv_obj_t *work_title = lv_label_create(screen);
    lv_label_set_text(work_title, "Active work");
    lv_obj_set_style_text_color(work_title, COLOR_MIST, 0);
    lv_obj_set_style_text_font(work_title, &lv_font_montserrat_20, 0);
    lv_obj_align(work_title, LV_ALIGN_TOP_LEFT, 238, 78);

    for (int i = 0; i < DASHBOARD_MAX_TASKS; ++i) {
        task_rows[i] = lv_obj_create(screen);
        set_clean_box(task_rows[i], COLOR_SLATE, 14);
        lv_obj_set_size(task_rows[i], 540, 66);
        lv_obj_align(task_rows[i], LV_ALIGN_TOP_LEFT, 238, 112 + (i * 72));
        lv_obj_add_flag(task_rows[i], LV_OBJ_FLAG_HIDDEN);

        task_dots[i] = lv_obj_create(task_rows[i]);
        set_clean_box(task_dots[i], COLOR_STEEL, LV_RADIUS_CIRCLE);
        lv_obj_set_size(task_dots[i], 10, 10);
        lv_obj_align(task_dots[i], LV_ALIGN_LEFT_MID, 16, 0);

        task_titles[i] = lv_label_create(task_rows[i]);
        lv_obj_set_style_text_color(task_titles[i], COLOR_MIST, 0);
        lv_obj_set_style_text_font(task_titles[i], &lv_font_montserrat_14, 0);
        lv_obj_align(task_titles[i], LV_ALIGN_TOP_LEFT, 42, 12);

        task_summaries[i] = lv_label_create(task_rows[i]);
        lv_obj_set_width(task_summaries[i], 470);
        lv_label_set_long_mode(task_summaries[i], LV_LABEL_LONG_DOT);
        lv_obj_set_style_text_color(task_summaries[i], COLOR_FOG, 0);
        lv_obj_set_style_text_font(task_summaries[i], &lv_font_montserrat_14, 0);
        lv_obj_align(task_summaries[i], LV_ALIGN_BOTTOM_LEFT, 42, -10);
    }
}

esp_err_t dashboard_ui_init(esp_lcd_panel_handle_t lcd)
{
    if (lcd == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    const lvgl_port_cfg_t port_config = {
        .task_priority = 4,
        .task_stack = 8192,
        .task_affinity = 1,
        .task_max_sleep_ms = 100,
        .task_stack_caps = MALLOC_CAP_INTERNAL | MALLOC_CAP_DEFAULT,
        .timer_period_ms = 5,
    };
    ESP_RETURN_ON_ERROR(lvgl_port_init(&port_config), "dashboard_ui", "LVGL port init failed");

    const lvgl_port_display_cfg_t display_config = {
        .io_handle = NULL,
        .panel_handle = lcd,
        .control_handle = NULL,
        .buffer_size = 800 * 480,
        .double_buffer = true,
        .trans_size = 0,
        .hres = 800,
        .vres = 480,
        .monochrome = false,
        .rotation = { .swap_xy = false, .mirror_x = false, .mirror_y = false },
        .rounder_cb = NULL,
        .color_format = LV_COLOR_FORMAT_RGB565,
        .flags = {
            .buff_dma = false,
            .buff_spiram = true,
            .sw_rotate = false,
            .swap_bytes = false,
            .full_refresh = false,
            .direct_mode = true,
        },
    };
    const lvgl_port_display_rgb_cfg_t rgb_config = {
        .flags = { .bb_mode = true, .avoid_tearing = true },
    };
    lv_display_t *display = lvgl_port_add_disp_rgb(&display_config, &rgb_config);
    if (display == NULL) {
        return ESP_FAIL;
    }

    lvgl_port_lock(0);
    lv_indev_t *touch = lv_indev_create();
    if (touch == NULL) {
        lvgl_port_unlock();
        return ESP_FAIL;
    }
    lv_indev_set_type(touch, LV_INDEV_TYPE_POINTER);
    lv_indev_set_read_cb(touch, touch_read);

    build_ui();
    lvgl_port_unlock();
    return ESP_OK;
}

void dashboard_ui_set_model(const dashboard_model_t *model)
{
    if (model == NULL || attention_count_label == NULL) {
        return;
    }
    lvgl_port_lock(0);
    int attention_count = 0;
    for (int i = 0; i < DASHBOARD_MAX_TASKS; ++i) {
        if (i >= model->task_count) {
            lv_obj_add_flag(task_rows[i], LV_OBJ_FLAG_HIDDEN);
            continue;
        }
        const dashboard_task_t *task = &model->tasks[i];
        lv_obj_remove_flag(task_rows[i], LV_OBJ_FLAG_HIDDEN);
        lv_label_set_text(task_titles[i], task->title);
        lv_label_set_text(task_summaries[i], task->summary);
        lv_color_t dot = COLOR_STEEL;
        if (task->attention != DASHBOARD_ATTENTION_NONE) {
            dot = COLOR_AMBER;
            ++attention_count;
        } else if (task->state == DASHBOARD_TASK_ACTIVE) {
            dot = COLOR_SIGNAL;
        }
        lv_obj_set_style_bg_color(task_dots[i], dot, 0);
    }
    char count[8];
    snprintf(count, sizeof(count), "%d", attention_count);
    lv_label_set_text(attention_count_label, count);
    lv_obj_set_style_text_color(attention_count_label, attention_count > 0 ? COLOR_AMBER : COLOR_MIST, 0);
    lvgl_port_unlock();
}

void dashboard_ui_set_connection_state(dashboard_connection_state_t state)
{
    if (connection_label == NULL) {
        return;
    }
    const char *text = "Mac offline";
    lv_color_t color = COLOR_FOG;
    switch (state) {
    case DASHBOARD_CONNECTION_ONLINE:
        text = "Mac online";
        color = COLOR_SIGNAL;
        break;
    case DASHBOARD_CONNECTION_CONNECTING:
        text = "Connecting to Mac";
        break;
    case DASHBOARD_CONNECTION_NOT_CONFIGURED:
        text = "Mac not configured";
        break;
    case DASHBOARD_CONNECTION_OFFLINE:
    default:
        break;
    }
    lvgl_port_lock(0);
    lv_label_set_text(connection_label, text);
    lv_obj_set_style_text_color(connection_label, color, 0);
    lvgl_port_unlock();
}
