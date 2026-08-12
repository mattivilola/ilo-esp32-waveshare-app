#include "dashboard_ui.h"

#include <stdlib.h>
#include <string.h>

#include "esp_heap_caps.h"
#include <stdio.h>
#include <stdint.h>
#include <time.h>

#include "esp_check.h"
#include "esp_app_desc.h"
#include "esp_lvgl_port.h"
#include "lvgl.h"
#include "board_waveshare_5.h"
#include "device_settings.h"
#include "ilo_icon_48.h"

#define COLOR_CARBON  lv_color_hex(0x0A0F14)
#define COLOR_SLATE   lv_color_hex(0x131B22)
#define COLOR_STEEL   lv_color_hex(0x24313C)
#define COLOR_SIGNAL  lv_color_hex(0x65E5B8)
#define COLOR_AMBER   lv_color_hex(0xFFB55A)
#define COLOR_MIST    lv_color_hex(0xF3F7F8)
#define COLOR_FOG     lv_color_hex(0x8EA2B2)
#define COLOR_CYAN    lv_color_hex(0x37B3D9)

#define PAGE_COUNT 5
#define PAGE_DASHBOARD 0
#define PAGE_CODEX 1
#define PAGE_X_NEWS 2
#define PAGE_WEATHER 3
#define PAGE_SETTINGS 4
#define DASHBOARD_VISIBLE_TASKS 3
#define CODEX_VISIBLE_TASKS 3
#define X_NEWS_VISIBLE_STORIES DASHBOARD_MAX_NEWS
#define X_NEWS_RESULT_HOLD_MS 8000U
#define CODEX_CONTINUE_HOLD_MS 900U
#define CODEX_RESULT_HOLD_MS 8000U
#define MINUTE_MS 60000U

static lv_obj_t *connection_label;
static lv_obj_t *attention_count_label;
static lv_obj_t *mac_power_percent_label;
static lv_obj_t *mac_power_state_label;
static lv_obj_t *dashboard_weather_icon_box;
static lv_obj_t *dashboard_weather_icon_label;
static lv_obj_t *dashboard_weather_location_label;
static lv_obj_t *dashboard_weather_temperature_label;
static lv_obj_t *dashboard_weather_condition_label;
static lv_obj_t *dashboard_weather_state_label;
static lv_obj_t *task_rows[DASHBOARD_MAX_TASKS];
static lv_obj_t *task_titles[DASHBOARD_MAX_TASKS];
static lv_obj_t *task_summaries[DASHBOARD_MAX_TASKS];
static lv_obj_t *task_dots[DASHBOARD_MAX_TASKS];
static lv_obj_t *codex_rows[CODEX_VISIBLE_TASKS];
static lv_obj_t *codex_titles[CODEX_VISIBLE_TASKS];
static lv_obj_t *codex_summaries[CODEX_VISIBLE_TASKS];
static lv_obj_t *codex_dots[CODEX_VISIBLE_TASKS];
static lv_obj_t *codex_detail_eyebrow;
static lv_obj_t *codex_detail_title;
static lv_obj_t *codex_detail_summary;
static lv_obj_t *codex_detail_status;
static lv_obj_t *codex_hold_button;
static lv_obj_t *codex_hold_label;
static lv_obj_t *codex_confirm_button;
static lv_obj_t *codex_confirm_label;
static dashboard_codex_continue_callback_t codex_continue_callback;
static char codex_selected_task_id[81];
static uint32_t codex_hold_started_tick;
static uint32_t codex_result_started_tick;
static bool codex_continue_armed;
static bool codex_continue_in_flight;
static bool codex_result_visible;
static lv_obj_t *x_news_status_label;
static lv_obj_t *x_news_scroll;
static lv_obj_t *x_news_scroll_hint;
static lv_obj_t *x_news_empty_card;
static lv_obj_t *x_news_empty_spinner;
static lv_obj_t *x_news_empty_title;
static lv_obj_t *x_news_empty_help;
static lv_obj_t *x_news_rows[X_NEWS_VISIBLE_STORIES];
static lv_obj_t *x_news_titles[X_NEWS_VISIBLE_STORIES];
static lv_obj_t *x_news_summaries[X_NEWS_VISIBLE_STORIES];
static lv_obj_t *x_news_meta[X_NEWS_VISIBLE_STORIES];
static dashboard_x_news_refresh_callback_t x_news_refresh_callback;
static int32_t x_news_pull_distance;
static int32_t x_news_pull_start_x;
static int32_t x_news_pull_start_y;
static bool x_news_pull_tracking;
static bool x_news_refresh_in_flight;
static bool x_news_result_visible;
static uint32_t x_news_result_started_tick;
static lv_obj_t *page_eyebrow_label;
static lv_obj_t *page_title_label;
static lv_obj_t *brand_icon;
static lv_obj_t *work_pulse_rail;
static lv_obj_t *boot_beacon_icon;
static lv_obj_t *boot_ring_inner;
static lv_obj_t *boot_ring_outer;
static lv_obj_t *boot_scan_line;
static lv_obj_t *boot_particles[3];
static lv_obj_t *tileview;
static lv_obj_t *tiles[PAGE_COUNT];
static lv_obj_t *nav_buttons[PAGE_COUNT];
static lv_obj_t *nav_labels[PAGE_COUNT];
static lv_obj_t *screensaver;
static lv_obj_t *screensaver_content;
static lv_obj_t *screensaver_status_dot;
static lv_obj_t *screensaver_clock_label;
static lv_obj_t *screensaver_date_label;
static lv_obj_t *header_clock_label;
static lv_obj_t *focus_timer_label;
static lv_obj_t *settings_screensaver_value;
static lv_obj_t *settings_display_off_value;
static lv_obj_t *settings_privacy_value;
static lv_obj_t *settings_clock_value;
static lv_obj_t *settings_temperature_value;
static lv_obj_t *settings_focus_value;
static lv_obj_t *settings_x_news_value;
static lv_obj_t *settings_versions_value;
static lv_obj_t *settings_ota_value;
static dashboard_ota_callback_t ota_check_callback;
static dashboard_ota_callback_t ota_install_callback;
static dashboard_ota_state_t settings_ota_state = DASHBOARD_OTA_DISABLED;
static char settings_ota_version[32];
static uint8_t settings_ota_progress;
static lv_obj_t *wifi_setup_overlay;
static lv_obj_t *wifi_ssid_input;
static lv_obj_t *wifi_password_input;
static lv_obj_t *wifi_keyboard;
static lv_obj_t *wifi_setup_status;
static dashboard_wifi_update_callback_t wifi_update_callback;
static dashboard_wifi_scan_callback_t wifi_scan_callback;
static lv_obj_t *wifi_network_buttons[4];
static char wifi_network_ssids[4][33];
static lv_obj_t *weather_location_label;
static lv_obj_t *weather_state_label;
static lv_obj_t *weather_temperature_label;
static lv_obj_t *weather_condition_label;
static lv_obj_t *weather_details_label;
static lv_obj_t *weather_day_labels[WEATHER_FORECAST_DAYS];
static lv_display_t *ui_display;
static device_settings_t current_settings;
static dashboard_model_t latest_model;
static bool latest_model_valid;
static bool x_news_page_enabled;
static bool navigation_configured;
static bool display_asleep;
static bool consuming_wake_touch;
static bool boot_animation_active;
static uint32_t screensaver_tick;
static uint32_t focus_remaining_seconds;
static bool focus_running;
static int32_t clock_utc_offset_seconds;
static char clock_timezone_abbreviation[8] = "UTC";
static weather_model_t latest_weather_model;
static bool latest_weather_valid;

static void render_weather(const weather_model_t *model);
static void x_news_scroll_event(lv_event_t *event);
static void configure_x_news_page(bool enabled);
static void update_page_chrome(void);
static void finish_boot_animation(void);
static void refresh_clock_labels(void);
static void render_codex_detail(void);

static void set_clock_timezone_locked(int32_t utc_offset_seconds, const char *abbreviation)
{
    if (abbreviation == NULL || abbreviation[0] == 0) return;
    bool changed = clock_utc_offset_seconds != utc_offset_seconds
        || strcmp(clock_timezone_abbreviation, abbreviation) != 0;
    clock_utc_offset_seconds = utc_offset_seconds;
    strlcpy(clock_timezone_abbreviation, abbreviation, sizeof(clock_timezone_abbreviation));
    if (changed) {
        current_settings.clock_utc_offset_seconds = utc_offset_seconds;
        strlcpy(
            current_settings.clock_timezone_abbreviation,
            abbreviation,
            sizeof(current_settings.clock_timezone_abbreviation)
        );
        device_settings_save(&current_settings);
    }
    refresh_clock_labels();
}

static const char *page_eyebrows[PAGE_COUNT] = {
    "ILO / WORK PULSE", "ILO / CODEX", "ILO / X NEWS", "ILO / WEATHER", "ILO / SETTINGS"
};
static const char *page_titles[PAGE_COUNT] = {
    "Dashboard", "Codex", "X News", "Weather", "Settings"
};

static void touch_read(lv_indev_t *input, lv_indev_data_t *data)
{
    (void)input;
    uint16_t x = 0;
    uint16_t y = 0;
    if (board_waveshare_5_read_touch(&x, &y)) {
        if (boot_animation_active) {
            finish_boot_animation();
        }
        if (display_asleep) {
            board_waveshare_5_set_backlight(true);
            display_asleep = false;
            consuming_wake_touch = true;
            if (ui_display != NULL) {
                lv_display_trigger_activity(ui_display);
            }
            if (screensaver != NULL) {
                lv_obj_add_flag(screensaver, LV_OBJ_FLAG_HIDDEN);
            }
            // Consume the wake touch so it cannot activate a control hidden
            // behind the sleeping display.
            data->state = LV_INDEV_STATE_RELEASED;
            return;
        }
        if (consuming_wake_touch) {
            data->state = LV_INDEV_STATE_RELEASED;
            return;
        }
        data->point.x = x;
        data->point.y = y;
        data->state = LV_INDEV_STATE_PRESSED;
    } else {
        consuming_wake_touch = false;
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

static lv_obj_t *create_label(lv_obj_t *parent, const char *text, const lv_font_t *font, lv_color_t color)
{
    lv_obj_t *label = lv_label_create(parent);
    lv_label_set_text(label, text);
    lv_obj_set_style_text_font(label, font, 0);
    lv_obj_set_style_text_color(label, color, 0);
    return label;
}

static lv_obj_t *create_card(lv_obj_t *parent, int x, int y, int width, int height, int radius)
{
    lv_obj_t *card = lv_obj_create(parent);
    set_clean_box(card, COLOR_SLATE, radius);
    lv_obj_set_size(card, width, height);
    lv_obj_set_pos(card, x, y);
    lv_obj_clear_flag(card, LV_OBJ_FLAG_SCROLLABLE);
    return card;
}

static const dashboard_task_t *selected_codex_task(void)
{
    if (!latest_model_valid || codex_selected_task_id[0] == 0) return NULL;
    for (int index = 0; index < latest_model.task_count && index < DASHBOARD_MAX_TASKS; ++index) {
        if (strcmp(latest_model.tasks[index].id, codex_selected_task_id) == 0) {
            return &latest_model.tasks[index];
        }
    }
    return NULL;
}

static bool codex_task_can_continue(const dashboard_task_t *task)
{
    return latest_model.codex_continue_enabled
        && task != NULL
        && task->state == DASHBOARD_TASK_IDLE
        && task->attention == DASHBOARD_ATTENTION_NONE;
}

static void set_codex_button_visible(lv_obj_t *button, bool visible)
{
    if (button == NULL) return;
    if (visible) {
        lv_obj_remove_flag(button, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_add_flag(button, LV_OBJ_FLAG_HIDDEN);
    }
}

static void render_codex_detail(void)
{
    if (codex_detail_title == NULL) return;
    const dashboard_task_t *task = selected_codex_task();
    if (task == NULL) {
        lv_label_set_text(codex_detail_eyebrow, "BOUNDED CONTROL");
        lv_label_set_text(codex_detail_title, "Select a task");
        lv_label_set_text(codex_detail_summary, "Tap a recent task to inspect the only enabled action.");
        lv_label_set_text(codex_detail_status, "No approvals or free-form commands");
        lv_obj_set_style_text_color(codex_detail_status, COLOR_FOG, 0);
        set_codex_button_visible(codex_hold_button, false);
        set_codex_button_visible(codex_confirm_button, false);
        return;
    }

    lv_label_set_text(codex_detail_eyebrow, "TASK DETAIL");
    lv_label_set_text(codex_detail_title, task->title);
    lv_label_set_text(
        codex_detail_summary,
        current_settings.hide_task_summaries ? "Summary hidden by privacy setting" : task->summary
    );
    if (!codex_task_can_continue(task)) {
        const char *status = !latest_model.codex_continue_enabled
            ? "Enable Fixed Continue on the Mac"
            : (task->attention != DASHBOARD_ATTENTION_NONE
            ? "Needs attention on the Mac"
            : (task->state == DASHBOARD_TASK_ACTIVE ? "Already working" : "Continue is unavailable"));
        lv_label_set_text(codex_detail_status, status);
        lv_obj_set_style_text_color(codex_detail_status, COLOR_AMBER, 0);
        set_codex_button_visible(codex_hold_button, false);
        set_codex_button_visible(codex_confirm_button, false);
        codex_continue_armed = false;
        return;
    }

    if (!codex_result_visible && !codex_continue_in_flight) {
        lv_label_set_text(codex_detail_status, "Sends exactly: Please continue.");
        lv_obj_set_style_text_color(codex_detail_status, COLOR_FOG, 0);
    }
    set_codex_button_visible(codex_hold_button, !codex_continue_in_flight && !codex_continue_armed);
    set_codex_button_visible(codex_confirm_button, !codex_continue_in_flight && codex_continue_armed);
    if (codex_hold_label != NULL) lv_label_set_text(codex_hold_label, "HOLD TO ARM");
}

static void codex_row_tapped(lv_event_t *event)
{
    if (lv_event_get_code(event) != LV_EVENT_CLICKED || codex_continue_in_flight) return;
    int index = (int)(intptr_t)lv_event_get_user_data(event);
    if (!latest_model_valid || index < 0 || index >= latest_model.task_count) return;
    strlcpy(codex_selected_task_id, latest_model.tasks[index].id, sizeof(codex_selected_task_id));
    codex_continue_armed = false;
    codex_result_visible = false;
    render_codex_detail();
}

static void codex_hold_event(lv_event_t *event)
{
    lv_event_code_t code = lv_event_get_code(event);
    if (code == LV_EVENT_PRESSED) {
        codex_hold_started_tick = lv_tick_get();
        lv_label_set_text(codex_hold_label, "KEEP HOLDING...");
    } else if (code == LV_EVENT_PRESSING && !codex_continue_armed
               && lv_tick_elaps(codex_hold_started_tick) >= CODEX_CONTINUE_HOLD_MS) {
        codex_continue_armed = true;
        lv_label_set_text(codex_detail_status, "Armed - tap the separate confirm button");
        lv_obj_set_style_text_color(codex_detail_status, COLOR_SIGNAL, 0);
        set_codex_button_visible(codex_hold_button, false);
        set_codex_button_visible(codex_confirm_button, true);
    } else if (code == LV_EVENT_RELEASED && !codex_continue_armed) {
        lv_label_set_text(codex_hold_label, "HOLD TO ARM");
    }
}

static void codex_confirm_tapped(lv_event_t *event)
{
    if (lv_event_get_code(event) != LV_EVENT_CLICKED || !codex_continue_armed
        || codex_continue_in_flight || codex_continue_callback == NULL) return;
    const dashboard_task_t *task = selected_codex_task();
    if (!codex_task_can_continue(task)) {
        codex_continue_armed = false;
        render_codex_detail();
        return;
    }
    codex_continue_armed = false;
    codex_continue_in_flight = true;
    codex_result_visible = false;
    set_codex_button_visible(codex_hold_button, false);
    set_codex_button_visible(codex_confirm_button, false);
    lv_label_set_text(codex_detail_status, "Sending fixed action to paired Mac...");
    lv_obj_set_style_text_color(codex_detail_status, COLOR_SIGNAL, 0);
    if (!codex_continue_callback(task->id)) {
        codex_continue_in_flight = false;
        lv_label_set_text(codex_detail_status, "Mac is offline or another action is pending");
        lv_obj_set_style_text_color(codex_detail_status, COLOR_AMBER, 0);
        set_codex_button_visible(codex_hold_button, true);
    }
}

static void set_boot_rail_width(void *object, int32_t value)
{
    lv_obj_set_width((lv_obj_t *)object, value);
}

static void set_boot_icon_opacity(void *object, int32_t value)
{
    lv_obj_set_style_opa((lv_obj_t *)object, (lv_opa_t)value, 0);
}

static void set_boot_ring_size(void *object, int32_t value)
{
    lv_obj_set_size((lv_obj_t *)object, value, value);
    lv_obj_center((lv_obj_t *)object);
}

static void set_boot_scan_width(void *object, int32_t value)
{
    lv_obj_set_width((lv_obj_t *)object, value);
    lv_obj_center((lv_obj_t *)object);
}

static void delete_boot_object(lv_obj_t **object)
{
    if (*object != NULL) {
        lv_obj_delete(*object);
        *object = NULL;
    }
}

static void remove_boot_effects(void)
{
    delete_boot_object(&boot_beacon_icon);
    delete_boot_object(&boot_ring_inner);
    delete_boot_object(&boot_ring_outer);
    delete_boot_object(&boot_scan_line);
    for (int i = 0; i < 3; ++i) {
        delete_boot_object(&boot_particles[i]);
    }
}

static void finish_boot_animation(void)
{
    if (!boot_animation_active) {
        return;
    }
    boot_animation_active = false;

    lv_anim_delete(work_pulse_rail, set_boot_rail_width);
    if (boot_beacon_icon != NULL) {
        lv_anim_delete(boot_beacon_icon, set_boot_icon_opacity);
    }
    if (boot_ring_inner != NULL) {
        lv_anim_delete(boot_ring_inner, set_boot_ring_size);
        lv_anim_delete(boot_ring_inner, set_boot_icon_opacity);
    }
    if (boot_ring_outer != NULL) {
        lv_anim_delete(boot_ring_outer, set_boot_ring_size);
        lv_anim_delete(boot_ring_outer, set_boot_icon_opacity);
    }
    if (boot_scan_line != NULL) {
        lv_anim_delete(boot_scan_line, set_boot_scan_width);
    }
    for (int i = 0; i < 3; ++i) {
        if (boot_particles[i] != NULL) {
            lv_anim_delete(boot_particles[i], set_boot_icon_opacity);
        }
    }

    remove_boot_effects();
    lv_obj_set_width(work_pulse_rail, 6);
    lv_obj_set_style_opa(work_pulse_rail, LV_OPA_COVER, 0);
}

static void boot_animation_completed(lv_anim_t *animation)
{
    (void)animation;
    finish_boot_animation();
}

static void start_boot_animation(void)
{
    boot_animation_active = true;
    // Keep the ARGB icon at its native size. Continuously scaling it forces a
    // costly software transform on every RGB565 frame and can starve IDLE1.
    lv_image_set_scale(boot_beacon_icon, 256);
    lv_obj_set_style_opa(boot_beacon_icon, LV_OPA_COVER, 0);

    lv_anim_t animation;
    lv_anim_init(&animation);
    lv_anim_set_var(&animation, work_pulse_rail);
    lv_anim_set_exec_cb(&animation, set_boot_rail_width);
    lv_anim_set_values(&animation, 6, 14);
    lv_anim_set_duration(&animation, 120);
    lv_anim_set_reverse_delay(&animation, 80);
    lv_anim_set_reverse_duration(&animation, 160);
    lv_anim_set_path_cb(&animation, lv_anim_path_ease_out);
    lv_anim_start(&animation);

    lv_anim_init(&animation);
    lv_anim_set_var(&animation, boot_ring_inner);
    lv_anim_set_exec_cb(&animation, set_boot_ring_size);
    lv_anim_set_values(&animation, 90, 140);
    lv_anim_set_duration(&animation, 330);
    lv_anim_set_delay(&animation, 30);
    lv_anim_set_path_cb(&animation, lv_anim_path_ease_out);
    lv_anim_start(&animation);

    lv_anim_init(&animation);
    lv_anim_set_var(&animation, boot_ring_inner);
    lv_anim_set_exec_cb(&animation, set_boot_icon_opacity);
    lv_anim_set_values(&animation, LV_OPA_TRANSP, LV_OPA_70);
    lv_anim_set_duration(&animation, 110);
    lv_anim_set_delay(&animation, 30);
    lv_anim_set_reverse_delay(&animation, 160);
    lv_anim_set_reverse_duration(&animation, 120);
    lv_anim_start(&animation);

    lv_anim_init(&animation);
    lv_anim_set_var(&animation, boot_ring_outer);
    lv_anim_set_exec_cb(&animation, set_boot_ring_size);
    lv_anim_set_values(&animation, 112, 196);
    lv_anim_set_duration(&animation, 390);
    lv_anim_set_delay(&animation, 45);
    lv_anim_set_path_cb(&animation, lv_anim_path_ease_out);
    lv_anim_start(&animation);

    lv_anim_init(&animation);
    lv_anim_set_var(&animation, boot_ring_outer);
    lv_anim_set_exec_cb(&animation, set_boot_icon_opacity);
    lv_anim_set_values(&animation, LV_OPA_TRANSP, LV_OPA_60);
    lv_anim_set_duration(&animation, 100);
    lv_anim_set_delay(&animation, 50);
    lv_anim_set_reverse_delay(&animation, 140);
    lv_anim_set_reverse_duration(&animation, 120);
    lv_anim_start(&animation);

    lv_anim_init(&animation);
    lv_anim_set_var(&animation, boot_scan_line);
    lv_anim_set_exec_cb(&animation, set_boot_scan_width);
    lv_anim_set_values(&animation, 0, ILO_BOARD_WIDTH);
    lv_anim_set_duration(&animation, 180);
    lv_anim_set_delay(&animation, 70);
    lv_anim_set_reverse_delay(&animation, 35);
    lv_anim_set_reverse_duration(&animation, 160);
    lv_anim_set_completed_cb(&animation, boot_animation_completed);
    lv_anim_start(&animation);

    static const uint32_t particle_delays[3] = { 95, 130, 160 };
    for (int i = 0; i < 3; ++i) {
        lv_anim_init(&animation);
        lv_anim_set_var(&animation, boot_particles[i]);
        lv_anim_set_exec_cb(&animation, set_boot_icon_opacity);
        lv_anim_set_values(&animation, LV_OPA_TRANSP, LV_OPA_80);
        lv_anim_set_duration(&animation, 80);
        lv_anim_set_delay(&animation, particle_delays[i]);
        lv_anim_set_reverse_delay(&animation, 130);
        lv_anim_set_reverse_duration(&animation, 90);
        lv_anim_start(&animation);
    }
}

static bool local_clock(struct tm *clock)
{
    time_t now = time(NULL);
    if (now < 1700000000 || clock == NULL) {
        return false;
    }
    now += (time_t)clock_utc_offset_seconds;
    return gmtime_r(&now, clock) != NULL;
}

static void refresh_clock_labels(void)
{
    struct tm clock;
    char time_text[20] = "--:--";
    char date_text[24] = "TIME SYNC NEEDED";
    if (local_clock(&clock)) {
        if (current_settings.use_24_hour_clock) {
            strftime(time_text, sizeof(time_text), "%H:%M", &clock);
        } else {
            strftime(time_text, sizeof(time_text), "%I:%M %p", &clock);
            if (time_text[0] == '0') {
                memmove(time_text, time_text + 1, strlen(time_text));
            }
        }
        strftime(date_text, sizeof(date_text), "%a %d %b", &clock);
    }
    if (header_clock_label != NULL) {
        lv_label_set_text(header_clock_label, time_text);
    }
    if (screensaver_clock_label != NULL) {
        lv_label_set_text(screensaver_clock_label, time_text);
    }
    if (screensaver_date_label != NULL) {
        char dated_zone[36];
        snprintf(
            dated_zone,
            sizeof(dated_zone),
            "%s  %s",
            date_text,
            clock_timezone_abbreviation[0] != 0 ? clock_timezone_abbreviation : "UTC"
        );
        lv_label_set_text(screensaver_date_label, dated_zone);
    }
}

static void refresh_focus_label(void)
{
    if (focus_timer_label == NULL) return;
    if (focus_remaining_seconds == 0) {
        lv_label_set_text(focus_timer_label, "FOCUS COMPLETE    TAP TO RESTART");
        lv_obj_set_style_text_color(focus_timer_label, COLOR_SIGNAL, 0);
        return;
    }
    char text[64];
    snprintf(
        text,
        sizeof(text),
        "FOCUS %02u:%02u    %s",
        (unsigned int)(focus_remaining_seconds / 60),
        (unsigned int)(focus_remaining_seconds % 60),
        focus_running ? "PAUSE" : (focus_remaining_seconds < (uint32_t)current_settings.focus_minutes * 60U ? "RESUME" : "START")
    );
    lv_label_set_text(focus_timer_label, text);
    lv_obj_set_style_text_color(focus_timer_label, focus_running ? COLOR_SIGNAL : COLOR_MIST, 0);
}

static void focus_tapped(lv_event_t *event)
{
    if (lv_event_get_code(event) != LV_EVENT_CLICKED) return;
    if (focus_remaining_seconds == 0) {
        focus_remaining_seconds = (uint32_t)current_settings.focus_minutes * 60U;
    }
    focus_running = !focus_running;
    refresh_focus_label();
    lv_display_trigger_activity(ui_display);
}

static void build_codex_page(lv_obj_t *page)
{
    lv_obj_t *title = create_label(page, "Recent Codex tasks", &lv_font_montserrat_20, COLOR_MIST);
    lv_obj_set_pos(title, 22, 8);

    for (int i = 0; i < CODEX_VISIBLE_TASKS; ++i) {
        codex_rows[i] = create_card(page, 22, 48 + (i * 114), 660, 104, 14);
        lv_obj_add_flag(codex_rows[i], LV_OBJ_FLAG_CLICKABLE | LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_event_cb(codex_rows[i], codex_row_tapped, LV_EVENT_CLICKED, (void *)(intptr_t)i);

        codex_dots[i] = lv_obj_create(codex_rows[i]);
        set_clean_box(codex_dots[i], COLOR_STEEL, LV_RADIUS_CIRCLE);
        lv_obj_set_size(codex_dots[i], 10, 10);
        lv_obj_align(codex_dots[i], LV_ALIGN_LEFT_MID, 16, 0);

        codex_titles[i] = create_label(codex_rows[i], "", &lv_font_montserrat_14, COLOR_MIST);
        lv_obj_set_width(codex_titles[i], 500);
        lv_label_set_long_mode(codex_titles[i], LV_LABEL_LONG_DOT);
        lv_obj_align(codex_titles[i], LV_ALIGN_TOP_LEFT, 42, 20);

        codex_summaries[i] = create_label(codex_rows[i], "", &lv_font_montserrat_14, COLOR_FOG);
        lv_obj_set_width(codex_summaries[i], 560);
        lv_label_set_long_mode(codex_summaries[i], LV_LABEL_LONG_DOT);
        lv_obj_align(codex_summaries[i], LV_ALIGN_BOTTOM_LEFT, 42, -18);
    }

    lv_obj_t *detail = create_card(page, 702, 48, 294, 332, 16);
    codex_detail_eyebrow = create_label(detail, "BOUNDED CONTROL", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_set_pos(codex_detail_eyebrow, 18, 16);
    codex_detail_title = create_label(detail, "Select a task", &lv_font_montserrat_20, COLOR_MIST);
    lv_obj_set_width(codex_detail_title, 258);
    lv_label_set_long_mode(codex_detail_title, LV_LABEL_LONG_DOT);
    lv_obj_set_pos(codex_detail_title, 18, 48);
    codex_detail_summary = create_label(
        detail,
        "Tap a recent task to inspect the only enabled action.",
        &lv_font_montserrat_14,
        COLOR_FOG
    );
    lv_obj_set_width(codex_detail_summary, 258);
    lv_label_set_long_mode(codex_detail_summary, LV_LABEL_LONG_WRAP);
    lv_obj_set_pos(codex_detail_summary, 18, 86);
    codex_detail_status = create_label(detail, "No approvals or free-form commands", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_set_width(codex_detail_status, 258);
    lv_label_set_long_mode(codex_detail_status, LV_LABEL_LONG_WRAP);
    lv_obj_set_pos(codex_detail_status, 18, 180);

    codex_hold_button = lv_button_create(detail);
    set_clean_box(codex_hold_button, COLOR_STEEL, 12);
    lv_obj_set_size(codex_hold_button, 258, 54);
    lv_obj_align(codex_hold_button, LV_ALIGN_BOTTOM_MID, 0, -18);
    lv_obj_add_event_cb(codex_hold_button, codex_hold_event, LV_EVENT_ALL, NULL);
    codex_hold_label = create_label(codex_hold_button, "HOLD TO ARM", &lv_font_montserrat_14, COLOR_MIST);
    lv_obj_center(codex_hold_label);
    lv_obj_add_flag(codex_hold_button, LV_OBJ_FLAG_HIDDEN);

    codex_confirm_button = lv_button_create(detail);
    set_clean_box(codex_confirm_button, COLOR_SIGNAL, 12);
    lv_obj_set_size(codex_confirm_button, 258, 54);
    lv_obj_align(codex_confirm_button, LV_ALIGN_BOTTOM_MID, 0, -18);
    lv_obj_add_event_cb(codex_confirm_button, codex_confirm_tapped, LV_EVENT_CLICKED, NULL);
    codex_confirm_label = create_label(codex_confirm_button, "CONFIRM CONTINUE", &lv_font_montserrat_14, COLOR_CARBON);
    lv_obj_center(codex_confirm_label);
    lv_obj_add_flag(codex_confirm_button, LV_OBJ_FLAG_HIDDEN);
}

static void build_weather_page(lv_obj_t *page)
{
    weather_location_label = create_label(page, "Weather", &lv_font_montserrat_20, COLOR_MIST);
    lv_obj_set_pos(weather_location_label, 22, 8);
    lv_obj_set_width(weather_location_label, 300);
    lv_label_set_long_mode(weather_location_label, LV_LABEL_LONG_DOT);
    weather_state_label = create_label(page, "WAITING", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_set_pos(weather_state_label, 340, 12);
    lv_obj_t *attribution = create_label(page, "Weather data by Open-Meteo.com", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_align(attribution, LV_ALIGN_TOP_RIGHT, -22, 12);

    lv_obj_t *now = create_card(page, 22, 52, 350, 230, 16);
    lv_obj_t *now_label = create_label(now, "NOW", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_align(now_label, LV_ALIGN_TOP_LEFT, 18, 18);
    weather_temperature_label = create_label(now, "-- C", &lv_font_montserrat_28, COLOR_MIST);
    lv_obj_align(weather_temperature_label, LV_ALIGN_TOP_LEFT, 18, 66);
    weather_condition_label = create_label(now, "Waiting for forecast", &lv_font_montserrat_20, COLOR_CYAN);
    lv_obj_align(weather_condition_label, LV_ALIGN_TOP_LEFT, 18, 118);
    weather_details_label = create_label(now, "Direct Wi-Fi / Mac not required", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_align(weather_details_label, LV_ALIGN_BOTTOM_LEFT, 18, -18);

    lv_obj_t *hours = create_card(page, 388, 52, 608, 230, 16);
    lv_obj_t *hours_title = create_label(hours, "INDEPENDENT WEATHER", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_align(hours_title, LV_ALIGN_TOP_LEFT, 18, 18);
    lv_obj_t *hour_values = create_label(
        hours,
        "HTTPS verified with the ESP certificate bundle\nClock synchronized before the secure request\nForecast refreshes every 30 minutes",
        &lv_font_montserrat_14,
        COLOR_MIST
    );
    lv_obj_set_style_text_line_space(hour_values, 18, 0);
    lv_obj_align(hour_values, LV_ALIGN_TOP_LEFT, 18, 62);
    lv_obj_t *transition = create_label(hours, "Cached values are visibly marked STALE", &lv_font_montserrat_14, COLOR_CYAN);
    lv_obj_align(transition, LV_ALIGN_BOTTOM_LEFT, 18, -22);

    lv_obj_t *today = create_card(page, 22, 298, 314, 96, 14);
    weather_day_labels[0] = create_label(today, "TODAY\nWaiting", &lv_font_montserrat_14, COLOR_MIST);
    lv_obj_set_style_text_line_space(weather_day_labels[0], 10, 0);
    lv_obj_align(weather_day_labels[0], LV_ALIGN_LEFT_MID, 18, 0);
    lv_obj_t *tomorrow = create_card(page, 352, 298, 308, 96, 14);
    weather_day_labels[1] = create_label(tomorrow, "TOMORROW\nWaiting", &lv_font_montserrat_14, COLOR_MIST);
    lv_obj_set_style_text_line_space(weather_day_labels[1], 10, 0);
    lv_obj_align(weather_day_labels[1], LV_ALIGN_LEFT_MID, 18, 0);
    lv_obj_t *later = create_card(page, 676, 298, 320, 96, 14);
    weather_day_labels[2] = create_label(later, "+2 DAYS\nWaiting", &lv_font_montserrat_14, COLOR_MIST);
    lv_obj_set_style_text_line_space(weather_day_labels[2], 10, 0);
    lv_obj_align(weather_day_labels[2], LV_ALIGN_LEFT_MID, 18, 0);
}

static void show_model_x_news_status(void)
{
    if (x_news_status_label == NULL || !latest_model_valid) return;
    if (latest_model.news_count > 0) {
        char status[40];
        snprintf(status, sizeof(status), "%u VERIFIED STORIES", (unsigned int)latest_model.news_count);
        lv_label_set_text(x_news_status_label, status);
        lv_obj_set_style_text_color(x_news_status_label, COLOR_SIGNAL, 0);
        if (x_news_empty_card != NULL) lv_obj_add_flag(x_news_empty_card, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_label_set_text(x_news_status_label, "WAITING FOR VERIFIED MAC FEED");
        lv_obj_set_style_text_color(x_news_status_label, COLOR_AMBER, 0);
        if (x_news_empty_card != NULL) {
            lv_obj_remove_flag(x_news_empty_card, LV_OBJ_FLAG_HIDDEN);
            lv_obj_add_flag(x_news_empty_spinner, LV_OBJ_FLAG_HIDDEN);
            lv_label_set_text(x_news_empty_title, "Ready for your first brief");
            lv_obj_set_style_text_color(x_news_empty_title, COLOR_MIST, 0);
            lv_label_set_text(
                x_news_empty_help,
                "Pull down to fetch the latest AI + robotics news\nthrough your paired Mac companion"
            );
        }
    }
}

static void show_x_news_empty_activity(
    const char *title,
    const char *help,
    lv_color_t color,
    bool spinning
)
{
    if (x_news_empty_card == NULL || latest_model.news_count > 0) return;
    lv_obj_remove_flag(x_news_empty_card, LV_OBJ_FLAG_HIDDEN);
    if (spinning) {
        lv_obj_remove_flag(x_news_empty_spinner, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_add_flag(x_news_empty_spinner, LV_OBJ_FLAG_HIDDEN);
    }
    lv_label_set_text(x_news_empty_title, title);
    lv_obj_set_style_text_color(x_news_empty_title, color, 0);
    lv_label_set_text(x_news_empty_help, help);
}

static void show_x_news_pull_status(void)
{
    lv_label_set_text(
        x_news_status_label,
        x_news_pull_distance >= 72 ? "RELEASE TO FETCH LATEST NEWS" : "PULL DOWN TO REFRESH"
    );
    lv_obj_set_style_text_color(x_news_status_label, COLOR_CYAN, 0);
}

static void finish_x_news_pull(void)
{
    bool should_refresh = x_news_pull_distance >= 72;
    x_news_pull_tracking = false;
    x_news_pull_distance = 0;
    if (!should_refresh) {
        show_model_x_news_status();
        return;
    }
    if (x_news_refresh_callback != NULL && x_news_refresh_callback()) {
        x_news_refresh_in_flight = true;
        lv_label_set_text(x_news_status_label, "FETCHING LATEST AI NEWS...");
        lv_obj_set_style_text_color(x_news_status_label, COLOR_SIGNAL, 0);
        show_x_news_empty_activity(
            "Fetching latest AI + robotics news",
            "Grok via Mac  /  validating citations and timestamps\nThis can take a minute",
            COLOR_MIST,
            true
        );
    } else {
        lv_label_set_text(x_news_status_label, "MAC OFFLINE - REFRESH NOT SENT");
        lv_obj_set_style_text_color(x_news_status_label, COLOR_AMBER, 0);
    }
}

static void x_news_scroll_event(lv_event_t *event)
{
    lv_event_code_t code = lv_event_get_code(event);
    lv_obj_t *scroll = x_news_scroll;
    if (code == LV_EVENT_PRESSED && !x_news_refresh_in_flight && lv_obj_get_scroll_y(scroll) <= 0) {
        lv_indev_t *input = lv_event_get_indev(event);
        lv_point_t point;
        if (input != NULL) {
            lv_indev_get_point(input, &point);
            x_news_pull_start_x = point.x;
            x_news_pull_start_y = point.y;
            x_news_pull_tracking = true;
            x_news_pull_distance = 0;
        }
        return;
    }
    if (code == LV_EVENT_PRESSING && x_news_pull_tracking && !x_news_refresh_in_flight) {
        lv_indev_t *input = lv_event_get_indev(event);
        lv_point_t point;
        if (input != NULL) {
            lv_indev_get_point(input, &point);
            int32_t dx = point.x - x_news_pull_start_x;
            int32_t dy = point.y - x_news_pull_start_y;
            if (dy > 0 && dy > abs(dx)) {
                x_news_pull_distance = dy > 96 ? 96 : dy;
                show_x_news_pull_status();
            }
        }
        return;
    }
    if (code == LV_EVENT_RELEASED && x_news_pull_tracking) {
        finish_x_news_pull();
        return;
    }
    if (code == LV_EVENT_SCROLL && !x_news_refresh_in_flight) {
        int32_t y = lv_obj_get_scroll_y(scroll);
        if (y < 0) {
            int32_t distance = -y;
            if (distance > x_news_pull_distance) x_news_pull_distance = distance;
            show_x_news_pull_status();
        }
        return;
    }
    if (code != LV_EVENT_SCROLL_END || x_news_refresh_in_flight) return;
    finish_x_news_pull();
}

static void build_x_news_page(lv_obj_t *page)
{
    lv_obj_t *title = create_label(page, "AI + humanoid robotics", &lv_font_montserrat_20, COLOR_MIST);
    lv_obj_set_pos(title, 22, 8);
    x_news_status_label = create_label(page, "WAITING FOR VERIFIED MAC FEED", &lv_font_montserrat_14, COLOR_AMBER);
    lv_obj_align(x_news_status_label, LV_ALIGN_TOP_RIGHT, -22, 12);

    x_news_scroll = lv_obj_create(page);
    set_clean_box(x_news_scroll, COLOR_CARBON, 0);
    lv_obj_set_size(x_news_scroll, 998, 354);
    lv_obj_set_pos(x_news_scroll, 10, 46);
    lv_obj_set_scroll_dir(x_news_scroll, LV_DIR_VER);
    lv_obj_set_scrollbar_mode(x_news_scroll, LV_SCROLLBAR_MODE_AUTO);
    lv_obj_add_flag(x_news_scroll, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_SCROLL_MOMENTUM | LV_OBJ_FLAG_SCROLL_CHAIN_HOR);
    lv_obj_add_event_cb(x_news_scroll, x_news_scroll_event, LV_EVENT_ALL, NULL);

    for (int i = 0; i < X_NEWS_VISIBLE_STORIES; ++i) {
        x_news_rows[i] = create_card(x_news_scroll, 12, 4 + (i * 126), 964, 116, 14);
        lv_obj_add_flag(x_news_rows[i], LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_event_cb(x_news_rows[i], x_news_scroll_event, LV_EVENT_ALL, NULL);
        x_news_titles[i] = create_label(x_news_rows[i], "", &lv_font_montserrat_16, COLOR_MIST);
        lv_obj_set_width(x_news_titles[i], 700);
        lv_label_set_long_mode(x_news_titles[i], LV_LABEL_LONG_DOT);
        lv_obj_align(x_news_titles[i], LV_ALIGN_TOP_LEFT, 18, 14);
        x_news_summaries[i] = create_label(x_news_rows[i], "", &lv_font_montserrat_14, COLOR_FOG);
        lv_obj_set_size(x_news_summaries[i], 928, 42);
        lv_label_set_long_mode(x_news_summaries[i], LV_LABEL_LONG_CLIP);
        lv_obj_set_style_text_line_space(x_news_summaries[i], 4, 0);
        lv_obj_align(x_news_summaries[i], LV_ALIGN_TOP_LEFT, 18, 48);
        x_news_meta[i] = create_label(x_news_rows[i], "", &lv_font_montserrat_14, COLOR_SIGNAL);
        lv_obj_set_width(x_news_meta[i], 220);
        lv_label_set_long_mode(x_news_meta[i], LV_LABEL_LONG_DOT);
        lv_obj_align(x_news_meta[i], LV_ALIGN_TOP_RIGHT, -18, 16);
        lv_obj_set_style_text_align(x_news_meta[i], LV_TEXT_ALIGN_RIGHT, 0);
    }

    x_news_empty_card = create_card(x_news_scroll, 12, 4, 964, 326, 16);
    lv_obj_add_event_cb(x_news_empty_card, x_news_scroll_event, LV_EVENT_ALL, NULL);
    x_news_empty_spinner = lv_spinner_create(x_news_empty_card);
    lv_obj_clear_flag(x_news_empty_spinner, LV_OBJ_FLAG_CLICKABLE | LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_size(x_news_empty_spinner, 58, 58);
    lv_spinner_set_anim_params(x_news_empty_spinner, 900, 250);
    lv_obj_set_style_arc_width(x_news_empty_spinner, 6, LV_PART_MAIN);
    lv_obj_set_style_arc_color(x_news_empty_spinner, COLOR_STEEL, LV_PART_MAIN);
    lv_obj_set_style_arc_width(x_news_empty_spinner, 6, LV_PART_INDICATOR);
    lv_obj_set_style_arc_color(x_news_empty_spinner, COLOR_SIGNAL, LV_PART_INDICATOR);
    lv_obj_align(x_news_empty_spinner, LV_ALIGN_CENTER, 0, -76);
    lv_obj_add_flag(x_news_empty_spinner, LV_OBJ_FLAG_HIDDEN);
    x_news_empty_title = create_label(
        x_news_empty_card,
        "Ready for your first brief",
        &lv_font_montserrat_20,
        COLOR_MIST
    );
    lv_obj_align(x_news_empty_title, LV_ALIGN_CENTER, 0, -8);
    x_news_empty_help = create_label(
        x_news_empty_card,
        "Pull down to fetch the latest AI + robotics news\nthrough your paired Mac companion",
        &lv_font_montserrat_14,
        COLOR_FOG
    );
    lv_obj_set_style_text_align(x_news_empty_help, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_text_line_space(x_news_empty_help, 8, 0);
    lv_obj_align(x_news_empty_help, LV_ALIGN_CENTER, 0, 44);

    x_news_scroll_hint = create_label(page, "SWIPE UP FOR MORE", &lv_font_montserrat_14, COLOR_CYAN);
    lv_obj_align(x_news_scroll_hint, LV_ALIGN_BOTTOM_RIGHT, -28, -4);
    lv_obj_add_flag(x_news_scroll_hint, LV_OBJ_FLAG_HIDDEN);
}

static void format_minutes(char *buffer, size_t size, uint16_t minutes)
{
    if (minutes == 0) {
        snprintf(buffer, size, "Never");
    } else {
        snprintf(buffer, size, "%u min", (unsigned int)minutes);
    }
}

static void refresh_settings_labels(void)
{
    char value[20];
    if (settings_screensaver_value != NULL) {
        format_minutes(value, sizeof(value), current_settings.screensaver_minutes);
        lv_label_set_text(settings_screensaver_value, value);
    }
    if (settings_display_off_value != NULL) {
        format_minutes(value, sizeof(value), current_settings.display_off_minutes);
        lv_label_set_text(settings_display_off_value, value);
    }
    if (settings_privacy_value != NULL) {
        lv_label_set_text(settings_privacy_value, current_settings.hide_task_summaries ? "HIDDEN" : "VISIBLE");
        lv_obj_set_style_text_color(
            settings_privacy_value,
            current_settings.hide_task_summaries ? COLOR_AMBER : COLOR_SIGNAL,
            0
        );
    }
    if (settings_clock_value != NULL) {
        lv_label_set_text(settings_clock_value, current_settings.use_24_hour_clock ? "24 HOUR" : "12 HOUR");
    }
    if (settings_temperature_value != NULL) {
        lv_label_set_text(settings_temperature_value, current_settings.use_fahrenheit ? "FAHRENHEIT" : "CELSIUS");
    }
    if (settings_focus_value != NULL) {
        snprintf(value, sizeof(value), "%u MIN", (unsigned int)current_settings.focus_minutes);
        lv_label_set_text(settings_focus_value, value);
    }
    if (settings_x_news_value != NULL) {
        if (!latest_model_valid) {
            lv_label_set_text(settings_x_news_value, "X NEWS  WAITING FOR MAC");
            lv_obj_set_style_text_color(settings_x_news_value, COLOR_FOG, 0);
        } else {
            lv_label_set_text(
                settings_x_news_value,
                latest_model.x_news_enabled ? "X NEWS  MAC ENABLED" : "X NEWS  MAC DISABLED"
            );
            lv_obj_set_style_text_color(
                settings_x_news_value,
                latest_model.x_news_enabled ? COLOR_SIGNAL : COLOR_FOG,
                0
            );
        }
    }
    if (settings_versions_value != NULL) {
        const char *companion_version = latest_model_valid && latest_model.companion_version[0] != 0
            ? latest_model.companion_version
            : "--";
        char versions[36];
        snprintf(
            versions,
            sizeof(versions),
            "FW %.12s  MAC %.12s",
            esp_app_get_description()->version,
            companion_version
        );
        lv_label_set_text(settings_versions_value, versions);
    }
    if (settings_ota_value != NULL) {
        char ota_text[36];
        lv_color_t color = COLOR_SIGNAL;
        switch (settings_ota_state) {
        case DASHBOARD_OTA_IDLE: snprintf(ota_text, sizeof(ota_text), "CHECK"); break;
        case DASHBOARD_OTA_CHECKING: snprintf(ota_text, sizeof(ota_text), "CHECKING..."); break;
        case DASHBOARD_OTA_UP_TO_DATE: snprintf(ota_text, sizeof(ota_text), "UP TO DATE"); break;
        case DASHBOARD_OTA_AVAILABLE: snprintf(ota_text, sizeof(ota_text), "INSTALL %.12s", settings_ota_version); break;
        case DASHBOARD_OTA_DOWNLOADING: snprintf(ota_text, sizeof(ota_text), "%u%%", (unsigned)settings_ota_progress); break;
        case DASHBOARD_OTA_VERIFYING: snprintf(ota_text, sizeof(ota_text), "VERIFYING"); break;
        case DASHBOARD_OTA_REBOOTING: snprintf(ota_text, sizeof(ota_text), "REBOOTING"); break;
        case DASHBOARD_OTA_FAILED: snprintf(ota_text, sizeof(ota_text), "TRY AGAIN"); color = COLOR_AMBER; break;
        case DASHBOARD_OTA_DISABLED:
        default: snprintf(ota_text, sizeof(ota_text), "USB BRIDGE NEEDED"); color = COLOR_FOG; break;
        }
        lv_label_set_text(settings_ota_value, ota_text);
        lv_obj_set_style_text_color(settings_ota_value, color, 0);
    }
}

static void ota_setting_tapped(lv_event_t *event)
{
    if (lv_event_get_code(event) != LV_EVENT_CLICKED) return;
    screensaver_tick = lv_tick_get();
    if (settings_ota_state == DASHBOARD_OTA_AVAILABLE) {
        if (ota_install_callback != NULL && ota_install_callback()) {
            settings_ota_state = DASHBOARD_OTA_DOWNLOADING;
            settings_ota_progress = 0;
        }
    } else if (settings_ota_state == DASHBOARD_OTA_IDLE
        || settings_ota_state == DASHBOARD_OTA_UP_TO_DATE
        || settings_ota_state == DASHBOARD_OTA_FAILED) {
        if (ota_check_callback != NULL && ota_check_callback()) settings_ota_state = DASHBOARD_OTA_CHECKING;
    }
    refresh_settings_labels();
}

static void refresh_task_summaries(void)
{
    if (!latest_model_valid) {
        return;
    }
    const char *hidden = "Summary hidden by privacy setting";
    for (int index = 0; index < DASHBOARD_VISIBLE_TASKS && index < latest_model.task_count; ++index) {
        lv_label_set_text(
            task_summaries[index],
            current_settings.hide_task_summaries ? hidden : latest_model.tasks[index].summary
        );
    }
    for (int index = 0; index < CODEX_VISIBLE_TASKS && index < latest_model.task_count; ++index) {
        lv_label_set_text(
            codex_summaries[index],
            current_settings.hide_task_summaries ? hidden : latest_model.tasks[index].summary
        );
    }
}

static void screensaver_setting_tapped(lv_event_t *event)
{
    if (lv_event_get_code(event) != LV_EVENT_CLICKED) return;
    current_settings.screensaver_minutes = device_settings_next_screensaver(current_settings.screensaver_minutes);
    device_settings_save(&current_settings);
    refresh_settings_labels();
    lv_display_trigger_activity(ui_display);
}

static void display_off_setting_tapped(lv_event_t *event)
{
    if (lv_event_get_code(event) != LV_EVENT_CLICKED) return;
    current_settings.display_off_minutes = device_settings_next_display_off(current_settings.display_off_minutes);
    device_settings_save(&current_settings);
    refresh_settings_labels();
    lv_display_trigger_activity(ui_display);
}

static void privacy_setting_tapped(lv_event_t *event)
{
    if (lv_event_get_code(event) != LV_EVENT_CLICKED) return;
    current_settings.hide_task_summaries = !current_settings.hide_task_summaries;
    device_settings_save(&current_settings);
    refresh_settings_labels();
    refresh_task_summaries();
    lv_display_trigger_activity(ui_display);
}

static void clock_setting_tapped(lv_event_t *event)
{
    if (lv_event_get_code(event) != LV_EVENT_CLICKED) return;
    current_settings.use_24_hour_clock = !current_settings.use_24_hour_clock;
    device_settings_save(&current_settings);
    refresh_settings_labels();
    refresh_clock_labels();
    lv_display_trigger_activity(ui_display);
}

static void temperature_setting_tapped(lv_event_t *event)
{
    if (lv_event_get_code(event) != LV_EVENT_CLICKED) return;
    current_settings.use_fahrenheit = !current_settings.use_fahrenheit;
    device_settings_save(&current_settings);
    refresh_settings_labels();
    if (latest_weather_valid) render_weather(&latest_weather_model);
    else if (dashboard_weather_temperature_label != NULL) {
        lv_label_set_text(dashboard_weather_temperature_label, current_settings.use_fahrenheit ? "-- F" : "-- C");
    }
    lv_display_trigger_activity(ui_display);
}

static void focus_setting_tapped(lv_event_t *event)
{
    if (lv_event_get_code(event) != LV_EVENT_CLICKED) return;
    current_settings.focus_minutes = device_settings_next_focus(current_settings.focus_minutes);
    device_settings_save(&current_settings);
    if (!focus_running) {
        focus_remaining_seconds = (uint32_t)current_settings.focus_minutes * 60U;
    }
    refresh_settings_labels();
    refresh_focus_label();
    lv_display_trigger_activity(ui_display);
}

static void sleep_now_tapped(lv_event_t *event)
{
    if (lv_event_get_code(event) != LV_EVENT_RELEASED) return;
    lv_obj_remove_flag(screensaver, LV_OBJ_FLAG_HIDDEN);
    if (board_waveshare_5_set_backlight(false) == ESP_OK) {
        display_asleep = true;
    }
}

static void wifi_input_tapped(lv_event_t *event)
{
    if (lv_event_get_code(event) != LV_EVENT_FOCUSED) return;
    lv_obj_t *input = lv_event_get_target_obj(event);
    lv_keyboard_set_textarea(wifi_keyboard, input);
    lv_keyboard_set_mode(
        wifi_keyboard,
        input == wifi_password_input ? LV_KEYBOARD_MODE_TEXT_LOWER : LV_KEYBOARD_MODE_TEXT_LOWER
    );
}

static void wifi_setup_close(void)
{
    if (wifi_setup_overlay != NULL) lv_obj_add_flag(wifi_setup_overlay, LV_OBJ_FLAG_HIDDEN);
    lv_keyboard_set_textarea(wifi_keyboard, NULL);
    lv_textarea_set_text(wifi_password_input, "");
}

static void wifi_setup_action(lv_event_t *event)
{
    if (lv_event_get_code(event) != LV_EVENT_CLICKED) return;
    intptr_t action = (intptr_t)lv_event_get_user_data(event);
    if (action == 0) {
        wifi_setup_close();
        return;
    }
    const char *ssid = lv_textarea_get_text(wifi_ssid_input);
    const char *password = lv_textarea_get_text(wifi_password_input);
    if (strlen(ssid) == 0 || strlen(ssid) > 32 || strlen(password) < 8 || strlen(password) > 63) {
        lv_label_set_text(wifi_setup_status, "SSID: 1-32 chars  /  Password: 8-63 chars");
        lv_obj_set_style_text_color(wifi_setup_status, COLOR_AMBER, 0);
        return;
    }
    if (wifi_update_callback != NULL && wifi_update_callback(ssid, password)) {
        lv_label_set_text(wifi_setup_status, "Saved securely - reconnecting...");
        lv_obj_set_style_text_color(wifi_setup_status, COLOR_SIGNAL, 0);
        lv_textarea_set_text(wifi_password_input, "");
    } else {
        lv_label_set_text(wifi_setup_status, "Could not save Wi-Fi - USB recovery remains available");
        lv_obj_set_style_text_color(wifi_setup_status, COLOR_AMBER, 0);
    }
}

static void wifi_setup_tapped(lv_event_t *event)
{
    if (lv_event_get_code(event) != LV_EVENT_CLICKED) return;
    lv_label_set_text(wifi_setup_status, "2.4 GHz WPA2/WPA3 Personal / password stays on board");
    lv_obj_set_style_text_color(wifi_setup_status, COLOR_FOG, 0);
    lv_obj_remove_flag(wifi_setup_overlay, LV_OBJ_FLAG_HIDDEN);
    lv_obj_move_foreground(wifi_setup_overlay);
    size_t network_count = wifi_scan_callback != NULL
        ? wifi_scan_callback(wifi_network_ssids, 4)
        : 0;
    for (size_t index = 0; index < 4; ++index) {
        if (index < network_count) {
            lv_label_set_text(lv_obj_get_child(wifi_network_buttons[index], 0), wifi_network_ssids[index]);
            lv_obj_remove_flag(wifi_network_buttons[index], LV_OBJ_FLAG_HIDDEN);
        } else {
            lv_obj_add_flag(wifi_network_buttons[index], LV_OBJ_FLAG_HIDDEN);
        }
    }
    lv_obj_add_state(wifi_ssid_input, LV_STATE_FOCUSED);
    lv_keyboard_set_textarea(wifi_keyboard, wifi_ssid_input);
}

static void wifi_scan_refresh(lv_timer_t *timer)
{
    (void)timer;
    if (wifi_setup_overlay == NULL || lv_obj_has_flag(wifi_setup_overlay, LV_OBJ_FLAG_HIDDEN)) return;
    size_t network_count = wifi_scan_callback != NULL
        ? wifi_scan_callback(wifi_network_ssids, 4)
        : 0;
    for (size_t index = 0; index < 4; ++index) {
        if (index < network_count) {
            lv_label_set_text(lv_obj_get_child(wifi_network_buttons[index], 0), wifi_network_ssids[index]);
            lv_obj_remove_flag(wifi_network_buttons[index], LV_OBJ_FLAG_HIDDEN);
        } else {
            lv_obj_add_flag(wifi_network_buttons[index], LV_OBJ_FLAG_HIDDEN);
        }
    }
}

static void wifi_network_tapped(lv_event_t *event)
{
    if (lv_event_get_code(event) != LV_EVENT_CLICKED) return;
    int index = (int)(intptr_t)lv_event_get_user_data(event);
    if (index < 0 || index >= 4 || wifi_network_ssids[index][0] == 0) return;
    lv_textarea_set_text(wifi_ssid_input, wifi_network_ssids[index]);
    lv_obj_add_state(wifi_password_input, LV_STATE_FOCUSED);
    lv_keyboard_set_textarea(wifi_keyboard, wifi_password_input);
}

static void build_wifi_setup(lv_obj_t *screen)
{
    wifi_setup_overlay = lv_obj_create(screen);
    set_clean_box(wifi_setup_overlay, COLOR_CARBON, 0);
    lv_obj_set_size(wifi_setup_overlay, ILO_BOARD_WIDTH, ILO_BOARD_HEIGHT);
    lv_obj_center(wifi_setup_overlay);
    lv_obj_add_flag(wifi_setup_overlay, LV_OBJ_FLAG_HIDDEN);
    lv_obj_clear_flag(wifi_setup_overlay, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t *title = create_label(wifi_setup_overlay, "Connect this board to Wi-Fi", &lv_font_montserrat_20, COLOR_MIST);
    lv_obj_set_pos(title, 30, 20);
    wifi_setup_status = create_label(
        wifi_setup_overlay,
        "2.4 GHz WPA2/WPA3 Personal / password stays on board",
        &lv_font_montserrat_14,
        COLOR_FOG
    );
    lv_obj_set_pos(wifi_setup_status, 30, 56);

    wifi_ssid_input = lv_textarea_create(wifi_setup_overlay);
    lv_obj_set_size(wifi_ssid_input, 390, 58);
    lv_obj_set_pos(wifi_ssid_input, 30, 92);
    lv_textarea_set_one_line(wifi_ssid_input, true);
    lv_textarea_set_max_length(wifi_ssid_input, 32);
    lv_textarea_set_placeholder_text(wifi_ssid_input, "Wi-Fi network name (SSID)");
    lv_obj_add_event_cb(wifi_ssid_input, wifi_input_tapped, LV_EVENT_FOCUSED, NULL);

    wifi_password_input = lv_textarea_create(wifi_setup_overlay);
    lv_obj_set_size(wifi_password_input, 390, 58);
    lv_obj_set_pos(wifi_password_input, 30, 160);
    lv_textarea_set_one_line(wifi_password_input, true);
    lv_textarea_set_password_mode(wifi_password_input, true);
    lv_textarea_set_password_bullet(wifi_password_input, "*");
    lv_textarea_set_max_length(wifi_password_input, 63);
    lv_textarea_set_placeholder_text(wifi_password_input, "Wi-Fi password");
    lv_obj_add_event_cb(wifi_password_input, wifi_input_tapped, LV_EVENT_FOCUSED, NULL);

    for (int index = 0; index < 4; ++index) {
        wifi_network_buttons[index] = lv_button_create(wifi_setup_overlay);
        set_clean_box(wifi_network_buttons[index], COLOR_STEEL, 10);
        lv_obj_set_size(wifi_network_buttons[index], 250, 42);
        lv_obj_set_pos(wifi_network_buttons[index], 435 + ((index % 2) * 260), 160 + ((index / 2) * 48));
        lv_obj_add_event_cb(
            wifi_network_buttons[index],
            wifi_network_tapped,
            LV_EVENT_CLICKED,
            (void *)(intptr_t)index
        );
        lv_obj_t *label = create_label(wifi_network_buttons[index], "", &lv_font_montserrat_14, COLOR_MIST);
        lv_obj_set_width(label, 220);
        lv_label_set_long_mode(label, LV_LABEL_LONG_DOT);
        lv_obj_center(label);
        lv_obj_add_flag(wifi_network_buttons[index], LV_OBJ_FLAG_HIDDEN);
    }

    lv_obj_t *cancel = lv_button_create(wifi_setup_overlay);
    set_clean_box(cancel, COLOR_STEEL, 12);
    lv_obj_set_size(cancel, 140, 52);
    lv_obj_set_pos(cancel, 478, 97);
    lv_obj_add_event_cb(cancel, wifi_setup_action, LV_EVENT_CLICKED, (void *)0);
    lv_obj_t *cancel_label = create_label(cancel, "Cancel", &lv_font_montserrat_14, COLOR_MIST);
    lv_obj_center(cancel_label);

    lv_obj_t *save = lv_button_create(wifi_setup_overlay);
    set_clean_box(save, COLOR_SIGNAL, 12);
    lv_obj_set_size(save, 180, 52);
    lv_obj_set_pos(save, 630, 97);
    lv_obj_add_event_cb(save, wifi_setup_action, LV_EVENT_CLICKED, (void *)1);
    lv_obj_t *save_label = create_label(save, "Save & connect", &lv_font_montserrat_14, COLOR_CARBON);
    lv_obj_center(save_label);

    wifi_keyboard = lv_keyboard_create(wifi_setup_overlay);
    lv_obj_set_size(wifi_keyboard, 964, 330);
    lv_obj_align(wifi_keyboard, LV_ALIGN_BOTTOM_MID, 0, -10);
    lv_timer_create(wifi_scan_refresh, 2000, NULL);
}

static lv_obj_t *create_setting_row(
    lv_obj_t *parent,
    int y,
    const char *title,
    lv_event_cb_t callback,
    lv_obj_t **value_label
)
{
    lv_obj_t *button = lv_button_create(parent);
    set_clean_box(button, COLOR_STEEL, 12);
    lv_obj_set_size(button, 436, 62);
    lv_obj_set_pos(button, 22, y);
    lv_obj_add_event_cb(button, callback, LV_EVENT_ALL, NULL);
    lv_obj_t *label = create_label(button, title, &lv_font_montserrat_14, COLOR_MIST);
    lv_obj_align(label, LV_ALIGN_LEFT_MID, 16, 0);
    *value_label = create_label(button, "", &lv_font_montserrat_14, COLOR_SIGNAL);
    lv_obj_align(*value_label, LV_ALIGN_RIGHT_MID, -16, 0);
    return button;
}

static void create_compact_setting_row(
    lv_obj_t *parent,
    int y,
    const char *title,
    lv_event_cb_t callback,
    lv_obj_t **value_label
)
{
    lv_obj_t *button = lv_button_create(parent);
    set_clean_box(button, COLOR_STEEL, 10);
    lv_obj_set_size(button, 438, 42);
    lv_obj_set_pos(button, 20, y);
    lv_obj_add_event_cb(button, callback, LV_EVENT_ALL, NULL);
    lv_obj_t *label = create_label(button, title, &lv_font_montserrat_14, COLOR_MIST);
    lv_obj_align(label, LV_ALIGN_LEFT_MID, 14, 0);
    *value_label = create_label(button, "", &lv_font_montserrat_14, COLOR_SIGNAL);
    lv_obj_align(*value_label, LV_ALIGN_RIGHT_MID, -14, 0);
}

static void build_settings_page(lv_obj_t *page)
{
    lv_obj_t *display = create_card(page, 22, 8, 480, 386, 16);
    lv_obj_t *display_title = create_label(display, "DISPLAY", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_align(display_title, LV_ALIGN_TOP_LEFT, 18, 18);
    create_setting_row(display, 50, "Pulse screensaver", screensaver_setting_tapped, &settings_screensaver_value);
    create_setting_row(display, 120, "Display off", display_off_setting_tapped, &settings_display_off_value);
    lv_obj_t *sleep_value = NULL;
    create_setting_row(display, 190, "Turn display off now", sleep_now_tapped, &sleep_value);
    lv_label_set_text(sleep_value, "SLEEP");
    create_setting_row(display, 260, "Firmware update", ota_setting_tapped, &settings_ota_value);
    lv_obj_t *power_note = create_label(display, "Signed OTA / current slot remains safe until verification", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_align(power_note, LV_ALIGN_BOTTOM_LEFT, 18, -12);

    lv_obj_t *pulse = create_card(page, 518, 8, 478, 194, 16);
    lv_obj_t *pulse_title = create_label(pulse, "PULSE & UNITS", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_align(pulse_title, LV_ALIGN_TOP_LEFT, 18, 14);
    create_compact_setting_row(pulse, 42, "Clock", clock_setting_tapped, &settings_clock_value);
    create_compact_setting_row(pulse, 90, "Temperature", temperature_setting_tapped, &settings_temperature_value);
    create_compact_setting_row(pulse, 138, "Focus session", focus_setting_tapped, &settings_focus_value);

    lv_obj_t *privacy = create_card(page, 518, 214, 478, 104, 16);
    lv_obj_add_flag(privacy, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_event_cb(privacy, privacy_setting_tapped, LV_EVENT_CLICKED, NULL);
    lv_obj_t *privacy_icon = lv_image_create(privacy);
    lv_image_set_src(privacy_icon, &ilo_icon_48);
    lv_obj_align(privacy_icon, LV_ALIGN_LEFT_MID, 18, 0);
    lv_obj_t *privacy_text = create_label(
        privacy,
        "Task summaries\nTap to change board visibility",
        &lv_font_montserrat_14,
        COLOR_MIST
    );
    lv_obj_set_style_text_line_space(privacy_text, 8, 0);
    lv_obj_align(privacy_text, LV_ALIGN_LEFT_MID, 84, 0);
    settings_privacy_value = create_label(privacy, "VISIBLE", &lv_font_montserrat_14, COLOR_SIGNAL);
    lv_obj_align(settings_privacy_value, LV_ALIGN_RIGHT_MID, -20, 0);

    lv_obj_t *connections = create_card(page, 518, 330, 478, 64, 16);
    lv_obj_add_flag(connections, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_event_cb(connections, wifi_setup_tapped, LV_EVENT_CLICKED, NULL);
    lv_obj_t *connection_values = create_label(
        connections,
        "WI-FI  TAP TO CHANGE     MAC  PAIRED     WEATHER  DIRECT",
        &lv_font_montserrat_14,
        COLOR_MIST
    );
    lv_obj_align(connection_values, LV_ALIGN_TOP_MID, 0, 8);
    settings_x_news_value = create_label(connections, "X NEWS  WAITING FOR MAC", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_align(settings_x_news_value, LV_ALIGN_BOTTOM_LEFT, 16, -8);
    settings_versions_value = create_label(connections, "", &lv_font_montserrat_14, COLOR_CYAN);
    lv_obj_align(settings_versions_value, LV_ALIGN_BOTTOM_RIGHT, -16, -8);
    refresh_settings_labels();
}

static int active_page_index(void)
{
    lv_obj_t *active = lv_tileview_get_tile_active(tileview);
    for (int i = 0; i < PAGE_COUNT; ++i) {
        if (tiles[i] == active) {
            return i;
        }
    }
    return 0;
}

static int visible_page_index(int page)
{
    if (!x_news_page_enabled && page > PAGE_X_NEWS) {
        return page - 1;
    }
    return page;
}

static void configure_x_news_page(bool enabled)
{
    if (tileview == NULL || tiles[PAGE_X_NEWS] == NULL || nav_buttons[PAGE_X_NEWS] == NULL) {
        return;
    }
    if (navigation_configured && x_news_page_enabled == enabled) {
        return;
    }
    int active = active_page_index();
    x_news_page_enabled = enabled;
    navigation_configured = true;

    if (enabled) {
        lv_obj_remove_flag(tiles[PAGE_X_NEWS], LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_add_flag(tiles[PAGE_X_NEWS], LV_OBJ_FLAG_HIDDEN);
    }

    for (int page = 0; page < PAGE_COUNT; ++page) {
        int column = page == PAGE_X_NEWS && !enabled ? PAGE_SETTINGS : visible_page_index(page);
        lv_obj_set_x(tiles[page], lv_pct(column * 100));
    }

    int visible_count = enabled ? PAGE_COUNT : PAGE_COUNT - 1;
    int nav_width = visible_count == PAGE_COUNT ? 188 : 237;
    for (int page = 0; page < PAGE_COUNT; ++page) {
        if (page == PAGE_X_NEWS && !enabled) {
            lv_obj_add_flag(nav_buttons[page], LV_OBJ_FLAG_HIDDEN);
            continue;
        }
        lv_obj_remove_flag(nav_buttons[page], LV_OBJ_FLAG_HIDDEN);
        int visible_index = visible_page_index(page);
        lv_obj_set_width(nav_buttons[page], nav_width);
        lv_obj_set_x(nav_buttons[page], 22 + (visible_index * (nav_width + 10)));
    }

    if (!enabled && active == PAGE_X_NEWS) {
        active = PAGE_WEATHER;
    }
    lv_tileview_set_tile(tileview, tiles[active], LV_ANIM_OFF);
    update_page_chrome();
}

static void update_page_chrome(void)
{
    int active = active_page_index();
    lv_label_set_text(page_eyebrow_label, page_eyebrows[active]);
    lv_label_set_text(page_title_label, page_titles[active]);
    for (int i = 0; i < PAGE_COUNT; ++i) {
        bool selected = i == active;
        lv_obj_set_style_bg_color(nav_buttons[i], selected ? COLOR_STEEL : COLOR_CARBON, 0);
        lv_obj_set_style_text_color(nav_labels[i], selected ? COLOR_MIST : COLOR_FOG, 0);
    }
}

static void tile_changed(lv_event_t *event)
{
    if (lv_event_get_code(event) == LV_EVENT_VALUE_CHANGED) {
        update_page_chrome();
    }
}

static void nav_tapped(lv_event_t *event)
{
    if (lv_event_get_code(event) != LV_EVENT_CLICKED) {
        return;
    }
    int index = (int)(intptr_t)lv_event_get_user_data(event);
    if (index >= 0 && index < PAGE_COUNT && (index != PAGE_X_NEWS || x_news_page_enabled)) {
        lv_tileview_set_tile(tileview, tiles[index], LV_ANIM_ON);
    }
}

static void screensaver_tapped(lv_event_t *event)
{
    if (lv_event_get_code(event) == LV_EVENT_PRESSED) {
        board_waveshare_5_set_backlight(true);
        display_asleep = false;
        lv_display_trigger_activity(ui_display);
        lv_obj_add_flag(screensaver, LV_OBJ_FLAG_HIDDEN);
    }
}

static void screensaver_timer(lv_timer_t *timer)
{
    (void)timer;
    refresh_clock_labels();
    if (focus_running && focus_remaining_seconds > 0) {
        --focus_remaining_seconds;
        if (focus_remaining_seconds == 0) focus_running = false;
        refresh_focus_label();
    }
    uint32_t inactive = lv_display_get_inactive_time(ui_display);
    uint32_t saver_timeout = (uint32_t)current_settings.screensaver_minutes * MINUTE_MS;
    uint32_t off_timeout = (uint32_t)current_settings.display_off_minutes * MINUTE_MS;

    if (!display_asleep && off_timeout > 0 && inactive >= off_timeout) {
        lv_obj_remove_flag(screensaver, LV_OBJ_FLAG_HIDDEN);
        if (board_waveshare_5_set_backlight(false) == ESP_OK) {
            display_asleep = true;
        }
        return;
    }
    if (display_asleep) {
        return;
    }
    if (saver_timeout > 0 && inactive >= saver_timeout) {
        lv_obj_remove_flag(screensaver, LV_OBJ_FLAG_HIDDEN);
        ++screensaver_tick;
        if (screensaver_tick % 5 == 0 && screensaver_content != NULL) {
            static const int offsets[][2] = {
                { -160, -100 }, { 150, -80 }, { 130, 95 }, { -145, 90 }, { 0, 0 },
            };
            size_t index = (screensaver_tick / 5) % (sizeof(offsets) / sizeof(offsets[0]));
            lv_obj_align(screensaver_content, LV_ALIGN_CENTER, offsets[index][0], offsets[index][1]);
        }
    } else {
        lv_obj_add_flag(screensaver, LV_OBJ_FLAG_HIDDEN);
        screensaver_tick = 0;
    }
}

static void build_screensaver(lv_obj_t *screen)
{
    screensaver = lv_obj_create(screen);
    set_clean_box(screensaver, COLOR_CARBON, 0);
    lv_obj_set_size(screensaver, ILO_BOARD_WIDTH, ILO_BOARD_HEIGHT);
    lv_obj_center(screensaver);
    lv_obj_add_flag(screensaver, LV_OBJ_FLAG_CLICKABLE | LV_OBJ_FLAG_HIDDEN);
    lv_obj_clear_flag(screensaver, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_event_cb(screensaver, screensaver_tapped, LV_EVENT_PRESSED, NULL);

    screensaver_content = lv_obj_create(screensaver);
    lv_obj_set_style_bg_opa(screensaver_content, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(screensaver_content, 0, 0);
    lv_obj_set_size(screensaver_content, 420, 172);
    lv_obj_clear_flag(screensaver_content, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE);
    lv_obj_center(screensaver_content);

    lv_obj_t *icon = lv_image_create(screensaver_content);
    lv_image_set_src(icon, &ilo_icon_48);
    lv_obj_align(icon, LV_ALIGN_LEFT_MID, 16, 0);
    lv_obj_t *pulse = create_label(screensaver_content, "ILO / PULSE", &lv_font_montserrat_20, COLOR_SIGNAL);
    lv_obj_align(pulse, LV_ALIGN_TOP_LEFT, 92, 7);
    screensaver_clock_label = create_label(screensaver_content, "--:--", &lv_font_montserrat_28, COLOR_MIST);
    lv_obj_align(screensaver_clock_label, LV_ALIGN_TOP_LEFT, 92, 38);
    screensaver_date_label = create_label(screensaver_content, "TIME SYNC NEEDED", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_align(screensaver_date_label, LV_ALIGN_TOP_LEFT, 92, 82);
    lv_obj_t *wake = create_label(screensaver_content, "Touch to wake", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_align(wake, LV_ALIGN_LEFT_MID, 112, 48);
    screensaver_status_dot = lv_obj_create(screensaver_content);
    set_clean_box(screensaver_status_dot, COLOR_FOG, LV_RADIUS_CIRCLE);
    lv_obj_set_size(screensaver_status_dot, 10, 10);
    lv_obj_align(screensaver_status_dot, LV_ALIGN_LEFT_MID, 92, 48);

    lv_timer_create(screensaver_timer, 1000, NULL);
    refresh_clock_labels();
}

static void build_ui(void)
{
    lv_obj_t *screen = lv_screen_active();
    set_clean_box(screen, COLOR_CARBON, 0);
    lv_obj_set_scrollbar_mode(screen, LV_SCROLLBAR_MODE_OFF);

    work_pulse_rail = lv_obj_create(screen);
    set_clean_box(work_pulse_rail, COLOR_SIGNAL, 0);
    lv_obj_set_size(work_pulse_rail, 6, ILO_BOARD_HEIGHT);
    lv_obj_align(work_pulse_rail, LV_ALIGN_TOP_LEFT, 0, 0);

    lv_obj_t *header = lv_obj_create(screen);
    set_clean_box(header, COLOR_CARBON, 0);
    lv_obj_set_size(header, ILO_BOARD_WIDTH - 40, 68);
    lv_obj_align(header, LV_ALIGN_TOP_LEFT, 22, 0);

    brand_icon = lv_image_create(header);
    lv_image_set_src(brand_icon, &ilo_icon_48);
    lv_image_set_scale(brand_icon, 192);
    lv_obj_align(brand_icon, LV_ALIGN_LEFT_MID, 0, 0);

    page_eyebrow_label = create_label(header, page_eyebrows[0], &lv_font_montserrat_14, COLOR_SIGNAL);
    lv_obj_set_pos(page_eyebrow_label, 50, 9);
    page_title_label = create_label(header, page_titles[0], &lv_font_montserrat_20, COLOR_MIST);
    lv_obj_set_pos(page_title_label, 50, 31);

    connection_label = lv_label_create(header);
    lv_label_set_text(connection_label, "Mac not configured");
    lv_obj_set_style_text_color(connection_label, COLOR_FOG, 0);
    lv_obj_set_style_text_font(connection_label, &lv_font_montserrat_14, 0);
    lv_obj_align(connection_label, LV_ALIGN_RIGHT_MID, -92, 0);
    header_clock_label = create_label(header, "--:--", &lv_font_montserrat_14, COLOR_MIST);
    lv_obj_align(header_clock_label, LV_ALIGN_RIGHT_MID, 0, 0);

    tileview = lv_tileview_create(screen);
    set_clean_box(tileview, COLOR_CARBON, 0);
    lv_obj_set_size(tileview, ILO_BOARD_WIDTH - 6, 474);
    lv_obj_set_pos(tileview, 6, 68);
    lv_obj_set_scrollbar_mode(tileview, LV_SCROLLBAR_MODE_OFF);
    lv_obj_add_event_cb(tileview, tile_changed, LV_EVENT_VALUE_CHANGED, NULL);
    tiles[0] = lv_tileview_add_tile(tileview, 0, 0, LV_DIR_RIGHT);
    tiles[1] = lv_tileview_add_tile(tileview, 1, 0, (lv_dir_t)(LV_DIR_LEFT | LV_DIR_RIGHT));
    tiles[2] = lv_tileview_add_tile(tileview, 2, 0, (lv_dir_t)(LV_DIR_LEFT | LV_DIR_RIGHT));
    tiles[3] = lv_tileview_add_tile(tileview, 3, 0, (lv_dir_t)(LV_DIR_LEFT | LV_DIR_RIGHT));
    tiles[4] = lv_tileview_add_tile(tileview, 4, 0, LV_DIR_LEFT);
    for (int i = 0; i < PAGE_COUNT; ++i) {
        set_clean_box(tiles[i], COLOR_CARBON, 0);
        lv_obj_set_scrollbar_mode(tiles[i], LV_SCROLLBAR_MODE_OFF);
    }

    lv_obj_t *attention = lv_obj_create(tiles[0]);
    set_clean_box(attention, COLOR_SLATE, 18);
    lv_obj_set_size(attention, 238, 410);
    lv_obj_set_pos(attention, 22, 8);

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

    lv_obj_t *mac_power_title = create_label(attention, "MACBOOK POWER", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_set_pos(mac_power_title, 20, 154);
    mac_power_percent_label = create_label(attention, "--", &lv_font_montserrat_28, COLOR_MIST);
    lv_obj_set_pos(mac_power_percent_label, 20, 186);
    mac_power_state_label = create_label(attention, "Waiting for Mac", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_set_width(mac_power_state_label, 198);
    lv_label_set_long_mode(mac_power_state_label, LV_LABEL_LONG_DOT);
    lv_obj_set_pos(mac_power_state_label, 20, 230);

    lv_obj_t *weather_divider = lv_obj_create(attention);
    set_clean_box(weather_divider, COLOR_STEEL, 0);
    lv_obj_set_size(weather_divider, 198, 1);
    lv_obj_set_pos(weather_divider, 20, 270);

    dashboard_weather_icon_box = lv_obj_create(attention);
    set_clean_box(dashboard_weather_icon_box, COLOR_STEEL, 14);
    lv_obj_set_size(dashboard_weather_icon_box, 50, 50);
    lv_obj_set_pos(dashboard_weather_icon_box, 20, 302);
    dashboard_weather_icon_label = create_label(
        dashboard_weather_icon_box,
        LV_SYMBOL_GPS,
        &lv_font_montserrat_20,
        COLOR_FOG
    );
    lv_obj_center(dashboard_weather_icon_label);

    dashboard_weather_location_label = create_label(attention, "WEATHER", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_set_width(dashboard_weather_location_label, 128);
    lv_label_set_long_mode(dashboard_weather_location_label, LV_LABEL_LONG_DOT);
    lv_obj_set_pos(dashboard_weather_location_label, 82, 282);
    dashboard_weather_temperature_label = create_label(attention, "-- C", &lv_font_montserrat_28, COLOR_MIST);
    lv_obj_set_pos(dashboard_weather_temperature_label, 82, 307);
    dashboard_weather_condition_label = create_label(attention, "Location needed", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_set_width(dashboard_weather_condition_label, 128);
    lv_label_set_long_mode(dashboard_weather_condition_label, LV_LABEL_LONG_DOT);
    lv_obj_set_pos(dashboard_weather_condition_label, 82, 345);
    dashboard_weather_state_label = create_label(attention, "SETUP", &lv_font_montserrat_14, COLOR_AMBER);
    lv_obj_set_pos(dashboard_weather_state_label, 20, 374);

    lv_obj_t *work_title = lv_label_create(tiles[0]);
    lv_label_set_text(work_title, "Active work");
    lv_obj_set_style_text_color(work_title, COLOR_MIST, 0);
    lv_obj_set_style_text_font(work_title, &lv_font_montserrat_20, 0);
    lv_obj_set_pos(work_title, 286, 14);

    for (int i = 0; i < DASHBOARD_VISIBLE_TASKS; ++i) {
        task_rows[i] = lv_obj_create(tiles[0]);
        set_clean_box(task_rows[i], COLOR_SLATE, 14);
        lv_obj_set_size(task_rows[i], 714, 80);
        lv_obj_set_pos(task_rows[i], 286, 54 + (i * 88));
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
        lv_obj_set_width(task_summaries[i], 640);
        lv_label_set_long_mode(task_summaries[i], LV_LABEL_LONG_DOT);
        lv_obj_set_style_text_color(task_summaries[i], COLOR_FOG, 0);
        lv_obj_set_style_text_font(task_summaries[i], &lv_font_montserrat_14, 0);
        lv_obj_align(task_summaries[i], LV_ALIGN_BOTTOM_LEFT, 42, -10);
    }

    lv_obj_t *focus = create_card(tiles[0], 286, 326, 714, 72, 14);
    lv_obj_add_flag(focus, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_event_cb(focus, focus_tapped, LV_EVENT_CLICKED, NULL);
    focus_timer_label = create_label(focus, "", &lv_font_montserrat_20, COLOR_MIST);
    lv_obj_align(focus_timer_label, LV_ALIGN_LEFT_MID, 18, 0);
    lv_obj_t *focus_note = create_label(focus, "LOCAL ONLY", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_align(focus_note, LV_ALIGN_RIGHT_MID, -18, 0);
    refresh_focus_label();

    build_codex_page(tiles[1]);
    build_x_news_page(tiles[2]);
    build_weather_page(tiles[3]);
    build_settings_page(tiles[4]);

    for (int i = 0; i < PAGE_COUNT; ++i) {
        nav_buttons[i] = lv_button_create(screen);
        set_clean_box(nav_buttons[i], i == 0 ? COLOR_STEEL : COLOR_CARBON, LV_RADIUS_CIRCLE);
        lv_obj_set_size(nav_buttons[i], 188, 42);
        lv_obj_set_pos(nav_buttons[i], 22 + (i * 198), 550);
        lv_obj_add_event_cb(nav_buttons[i], nav_tapped, LV_EVENT_CLICKED, (void *)(intptr_t)i);
        nav_labels[i] = create_label(
            nav_buttons[i],
            page_titles[i],
            &lv_font_montserrat_14,
            i == 0 ? COLOR_MIST : COLOR_FOG
        );
        lv_obj_center(nav_labels[i]);
    }

    configure_x_news_page(false);

    build_screensaver(screen);

    boot_ring_outer = lv_obj_create(screen);
    lv_obj_remove_style_all(boot_ring_outer);
    lv_obj_set_size(boot_ring_outer, 112, 112);
    lv_obj_set_style_radius(boot_ring_outer, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_border_width(boot_ring_outer, 2, 0);
    lv_obj_set_style_border_color(boot_ring_outer, COLOR_SIGNAL, 0);
    lv_obj_set_style_bg_opa(boot_ring_outer, LV_OPA_TRANSP, 0);
    lv_obj_set_style_opa(boot_ring_outer, LV_OPA_TRANSP, 0);
    lv_obj_clear_flag(boot_ring_outer, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE);
    lv_obj_center(boot_ring_outer);

    boot_ring_inner = lv_obj_create(screen);
    lv_obj_remove_style_all(boot_ring_inner);
    lv_obj_set_size(boot_ring_inner, 90, 90);
    lv_obj_set_style_radius(boot_ring_inner, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_border_width(boot_ring_inner, 2, 0);
    lv_obj_set_style_border_color(boot_ring_inner, COLOR_SIGNAL, 0);
    lv_obj_set_style_bg_opa(boot_ring_inner, LV_OPA_TRANSP, 0);
    lv_obj_set_style_opa(boot_ring_inner, LV_OPA_TRANSP, 0);
    lv_obj_clear_flag(boot_ring_inner, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE);
    lv_obj_center(boot_ring_inner);

    boot_scan_line = lv_obj_create(screen);
    set_clean_box(boot_scan_line, COLOR_MIST, 2);
    lv_obj_set_size(boot_scan_line, 0, 3);
    lv_obj_set_style_opa(boot_scan_line, LV_OPA_70, 0);
    lv_obj_clear_flag(boot_scan_line, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE);
    lv_obj_center(boot_scan_line);

    boot_beacon_icon = lv_image_create(screen);
    lv_image_set_src(boot_beacon_icon, &ilo_icon_48);
    lv_image_set_scale(boot_beacon_icon, 256);
    lv_obj_set_style_opa(boot_beacon_icon, LV_OPA_TRANSP, 0);
    lv_obj_clear_flag(boot_beacon_icon, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_center(boot_beacon_icon);

    static const lv_point_t particle_positions[3] = {
        { 628, 180 }, { 470, 414 }, { 650, 394 }
    };
    static const int32_t particle_sizes[3] = { 8, 7, 6 };
    for (int i = 0; i < 3; ++i) {
        boot_particles[i] = lv_obj_create(screen);
        set_clean_box(boot_particles[i], COLOR_SIGNAL, LV_RADIUS_CIRCLE);
        lv_obj_set_size(boot_particles[i], particle_sizes[i], particle_sizes[i]);
        lv_obj_set_pos(boot_particles[i], particle_positions[i].x, particle_positions[i].y);
        lv_obj_set_style_opa(boot_particles[i], LV_OPA_TRANSP, 0);
        lv_obj_clear_flag(boot_particles[i], LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE);
    }
    update_page_chrome();
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
        .buffer_size = ILO_BOARD_WIDTH * ILO_BOARD_HEIGHT,
        .double_buffer = true,
        .trans_size = 0,
        .hres = ILO_BOARD_WIDTH,
        .vres = ILO_BOARD_HEIGHT,
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

    ui_display = display;
    current_settings = device_settings_load();
    clock_utc_offset_seconds = current_settings.clock_utc_offset_seconds;
    strlcpy(
        clock_timezone_abbreviation,
        current_settings.clock_timezone_abbreviation,
        sizeof(clock_timezone_abbreviation)
    );
    focus_remaining_seconds = (uint32_t)current_settings.focus_minutes * 60U;
    build_ui();
    build_wifi_setup(lv_screen_active());
    lvgl_port_unlock();
    return ESP_OK;
}

esp_err_t dashboard_ui_present_boot(void)
{
    if (ui_display == NULL || work_pulse_rail == NULL || boot_beacon_icon == NULL ||
        boot_ring_inner == NULL || boot_ring_outer == NULL || boot_scan_line == NULL) {
        return ESP_ERR_INVALID_STATE;
    }
    for (int i = 0; i < 3; ++i) {
        if (boot_particles[i] == NULL) return ESP_ERR_INVALID_STATE;
    }

    lvgl_port_lock(0);
    lv_obj_set_width(work_pulse_rail, 6);
    lv_image_set_scale(boot_beacon_icon, 256);
    lv_obj_set_style_opa(boot_beacon_icon, LV_OPA_TRANSP, 0);
    set_boot_ring_size(boot_ring_inner, 90);
    lv_obj_set_style_opa(boot_ring_inner, LV_OPA_TRANSP, 0);
    set_boot_ring_size(boot_ring_outer, 112);
    lv_obj_set_style_opa(boot_ring_outer, LV_OPA_TRANSP, 0);
    set_boot_scan_width(boot_scan_line, 0);
    for (int i = 0; i < 3; ++i) {
        lv_obj_set_style_opa(boot_particles[i], LV_OPA_TRANSP, 0);
    }
    lv_refr_now(ui_display);

    esp_err_t status = board_waveshare_5_set_backlight(true);
    if (status == ESP_OK) {
        start_boot_animation();
    } else {
        lv_obj_set_width(work_pulse_rail, 6);
        remove_boot_effects();
    }
    lvgl_port_unlock();
    return status;
}

void dashboard_ui_set_model(const dashboard_model_t *model)
{
    if (model == NULL || attention_count_label == NULL) {
        return;
    }
    lvgl_port_lock(0);
    latest_model = *model;
    latest_model_valid = true;
    if (model->host_time_available) {
        set_clock_timezone_locked(model->utc_offset_seconds, model->timezone_abbreviation);
    }
    configure_x_news_page(model->x_news_enabled);
    refresh_settings_labels();
    if (mac_power_percent_label != NULL && mac_power_state_label != NULL) {
        if (model->mac_power_available) {
            char percent[8];
            snprintf(percent, sizeof(percent), "%u%%", (unsigned int)model->mac_power_percent);
            lv_label_set_text(mac_power_percent_label, percent);
            const char *state = "On battery";
            lv_color_t color = COLOR_MIST;
            switch (model->mac_power_state) {
            case DASHBOARD_MAC_POWER_CHARGING:
                state = "Charging";
                color = COLOR_SIGNAL;
                break;
            case DASHBOARD_MAC_POWER_ADAPTER:
                state = "Power adapter";
                color = COLOR_SIGNAL;
                break;
            case DASHBOARD_MAC_POWER_FULL:
                state = "Fully charged";
                color = COLOR_SIGNAL;
                break;
            case DASHBOARD_MAC_POWER_BATTERY:
            default:
                color = model->mac_power_percent <= 20 ? COLOR_AMBER : COLOR_MIST;
                break;
            }
            lv_label_set_text(mac_power_state_label, state);
            lv_obj_set_style_text_color(mac_power_percent_label, color, 0);
            lv_obj_set_style_text_color(mac_power_state_label, color, 0);
        } else {
            lv_label_set_text(mac_power_percent_label, "--");
            lv_label_set_text(mac_power_state_label, "Power unavailable");
            lv_obj_set_style_text_color(mac_power_percent_label, COLOR_FOG, 0);
            lv_obj_set_style_text_color(mac_power_state_label, COLOR_FOG, 0);
        }
    }
    int attention_count = 0;
    for (int i = 0; i < model->task_count && i < DASHBOARD_MAX_TASKS; ++i) {
        if (model->tasks[i].attention != DASHBOARD_ATTENTION_NONE) {
            ++attention_count;
        }
    }
    for (int i = 0; i < DASHBOARD_VISIBLE_TASKS; ++i) {
        if (i >= model->task_count) {
            lv_obj_add_flag(task_rows[i], LV_OBJ_FLAG_HIDDEN);
            continue;
        }
        const dashboard_task_t *task = &model->tasks[i];
        lv_obj_remove_flag(task_rows[i], LV_OBJ_FLAG_HIDDEN);
        lv_label_set_text(task_titles[i], task->title);
        lv_label_set_text(
            task_summaries[i],
            current_settings.hide_task_summaries ? "Summary hidden by privacy setting" : task->summary
        );
        lv_color_t dot = COLOR_STEEL;
        if (task->attention != DASHBOARD_ATTENTION_NONE) {
            dot = COLOR_AMBER;
        } else if (task->state == DASHBOARD_TASK_ACTIVE) {
            dot = COLOR_SIGNAL;
        }
        lv_obj_set_style_bg_color(task_dots[i], dot, 0);
    }
    for (int i = 0; i < CODEX_VISIBLE_TASKS; ++i) {
        if (i >= model->task_count) {
            lv_obj_add_flag(codex_rows[i], LV_OBJ_FLAG_HIDDEN);
            continue;
        }
        const dashboard_task_t *task = &model->tasks[i];
        lv_obj_remove_flag(codex_rows[i], LV_OBJ_FLAG_HIDDEN);
        lv_label_set_text(codex_titles[i], task->title);
        lv_label_set_text(
            codex_summaries[i],
            current_settings.hide_task_summaries ? "Summary hidden by privacy setting" : task->summary
        );
        lv_color_t dot = COLOR_STEEL;
        if (task->attention != DASHBOARD_ATTENTION_NONE) {
            dot = COLOR_AMBER;
        } else if (task->state == DASHBOARD_TASK_ACTIVE) {
            dot = COLOR_SIGNAL;
        }
        lv_obj_set_style_bg_color(codex_dots[i], dot, 0);
    }
    if (codex_selected_task_id[0] != 0 && selected_codex_task() == NULL) {
        codex_selected_task_id[0] = 0;
        codex_continue_armed = false;
        codex_continue_in_flight = false;
        codex_result_visible = false;
    }
    if (codex_result_visible && lv_tick_elaps(codex_result_started_tick) >= CODEX_RESULT_HOLD_MS) {
        codex_result_visible = false;
    }
    if (!codex_result_visible) {
        render_codex_detail();
    }
    if (!x_news_refresh_in_flight && x_news_pull_distance == 0) {
        if (x_news_result_visible && lv_tick_elaps(x_news_result_started_tick) < X_NEWS_RESULT_HOLD_MS) {
            // Keep a terminal refresh result readable across the next snapshot.
        } else {
            x_news_result_visible = false;
            show_model_x_news_status();
        }
    }
    if (x_news_scroll_hint != NULL) {
        if (model->news_count > 3) {
            char scroll_hint[32];
            snprintf(scroll_hint, sizeof(scroll_hint), "SWIPE UP  %d STORIES", model->news_count);
            lv_label_set_text(x_news_scroll_hint, scroll_hint);
            lv_obj_remove_flag(x_news_scroll_hint, LV_OBJ_FLAG_HIDDEN);
            lv_obj_set_scrollbar_mode(x_news_scroll, LV_SCROLLBAR_MODE_ON);
        } else {
            lv_obj_add_flag(x_news_scroll_hint, LV_OBJ_FLAG_HIDDEN);
            lv_obj_set_scrollbar_mode(x_news_scroll, LV_SCROLLBAR_MODE_OFF);
        }
    }
    for (int i = 0; i < X_NEWS_VISIBLE_STORIES; ++i) {
        if (i >= model->news_count) {
            lv_obj_add_flag(x_news_rows[i], LV_OBJ_FLAG_HIDDEN);
            continue;
        }
        const dashboard_news_story_t *story = &model->news[i];
        lv_obj_remove_flag(x_news_rows[i], LV_OBJ_FLAG_HIDDEN);
        lv_label_set_text(x_news_titles[i], story->headline);
        lv_label_set_text(x_news_summaries[i], story->summary);
        char meta[48];
        snprintf(meta, sizeof(meta), "%s / %s / %s", story->category, story->confidence, story->handle);
        lv_label_set_text(x_news_meta[i], meta);
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
    if (screensaver_status_dot != NULL) {
        lv_obj_set_style_bg_color(screensaver_status_dot, color, 0);
    }
    lvgl_port_unlock();
}

void dashboard_ui_set_x_news_refresh_callback(dashboard_x_news_refresh_callback_t callback)
{
    x_news_refresh_callback = callback;
}

void dashboard_ui_set_ota_callbacks(dashboard_ota_callback_t check_callback, dashboard_ota_callback_t install_callback)
{
    ota_check_callback = check_callback;
    ota_install_callback = install_callback;
}

void dashboard_ui_set_ota_status(dashboard_ota_state_t state, const char *version, uint8_t progress_percent)
{
    lvgl_port_lock(0);
    settings_ota_state = state;
    strlcpy(settings_ota_version, version != NULL ? version : "", sizeof(settings_ota_version));
    settings_ota_progress = progress_percent > 100 ? 100 : progress_percent;
    refresh_settings_labels();
    lvgl_port_unlock();
}

void dashboard_ui_set_wifi_update_callback(dashboard_wifi_update_callback_t callback)
{
    wifi_update_callback = callback;
}

void dashboard_ui_set_wifi_scan_callback(dashboard_wifi_scan_callback_t callback)
{
    wifi_scan_callback = callback;
}

void dashboard_ui_set_codex_continue_callback(dashboard_codex_continue_callback_t callback)
{
    codex_continue_callback = callback;
}

void dashboard_ui_set_codex_continue_state(dashboard_codex_continue_state_t state)
{
    if (codex_detail_status == NULL) return;
    const char *text = "Codex did not accept the request";
    lv_color_t color = COLOR_AMBER;
    switch (state) {
    case DASHBOARD_CODEX_CONTINUE_SENDING:
        text = "Sending fixed action to paired Mac...";
        color = COLOR_SIGNAL;
        break;
    case DASHBOARD_CODEX_CONTINUE_ACCEPTED:
        text = "Sent - Codex is continuing";
        color = COLOR_SIGNAL;
        break;
    case DASHBOARD_CODEX_CONTINUE_UNAVAILABLE:
        text = "Task control is unavailable on this Mac";
        break;
    case DASHBOARD_CODEX_CONTINUE_BUSY:
        text = "Codex is busy - try again shortly";
        color = COLOR_CYAN;
        break;
    case DASHBOARD_CODEX_CONTINUE_REJECTED:
        text = "Task changed and is no longer eligible";
        break;
    case DASHBOARD_CODEX_CONTINUE_FAILED:
    default:
        break;
    }
    lvgl_port_lock(0);
    codex_continue_in_flight = state == DASHBOARD_CODEX_CONTINUE_SENDING;
    codex_continue_armed = false;
    codex_result_visible = state != DASHBOARD_CODEX_CONTINUE_SENDING;
    if (codex_result_visible) codex_result_started_tick = lv_tick_get();
    lv_label_set_text(codex_detail_status, text);
    lv_obj_set_style_text_color(codex_detail_status, color, 0);
    set_codex_button_visible(codex_hold_button, false);
    set_codex_button_visible(codex_confirm_button, false);
    lvgl_port_unlock();
}

void dashboard_ui_set_x_news_refresh_state(dashboard_x_news_refresh_state_t state)
{
    if (x_news_status_label == NULL) return;
    const char *text = "NO VERIFIED UPDATE ACCEPTED";
    lv_color_t color = COLOR_AMBER;
    switch (state) {
    case DASHBOARD_X_NEWS_REFRESH_FETCHING:
        text = "FETCHING LATEST AI NEWS...";
        color = COLOR_SIGNAL;
        break;
    case DASHBOARD_X_NEWS_REFRESH_UPDATED:
        text = "LATEST VERIFIED STORIES READY";
        color = COLOR_SIGNAL;
        break;
    case DASHBOARD_X_NEWS_REFRESH_DISABLED:
        text = "ENABLE X NEWS ON THE MAC FIRST";
        break;
    case DASHBOARD_X_NEWS_REFRESH_COOLDOWN:
        text = "REFRESH COOLDOWN - TRY LATER";
        break;
    case DASHBOARD_X_NEWS_REFRESH_BUSY:
        text = "NEWS REFRESH ALREADY RUNNING";
        color = COLOR_CYAN;
        break;
    case DASHBOARD_X_NEWS_REFRESH_FAILED:
    default:
        break;
    }
    lvgl_port_lock(0);
    x_news_refresh_in_flight = state == DASHBOARD_X_NEWS_REFRESH_FETCHING;
    x_news_result_visible = state != DASHBOARD_X_NEWS_REFRESH_FETCHING;
    if (x_news_result_visible) x_news_result_started_tick = lv_tick_get();
    lv_label_set_text(x_news_status_label, text);
    lv_obj_set_style_text_color(x_news_status_label, color, 0);
    switch (state) {
    case DASHBOARD_X_NEWS_REFRESH_FETCHING:
        show_x_news_empty_activity(
            "Fetching latest AI + robotics news",
            "Grok via Mac  /  validating citations and timestamps\nThis can take a minute",
            COLOR_MIST,
            true
        );
        break;
    case DASHBOARD_X_NEWS_REFRESH_UPDATED:
        show_x_news_empty_activity(
            "Verified brief ready",
            "Syncing the latest accepted stories from your Mac",
            COLOR_SIGNAL,
            false
        );
        break;
    case DASHBOARD_X_NEWS_REFRESH_COOLDOWN:
        show_x_news_empty_activity(
            "Refresh available soon",
            "The 15-minute safety cooldown prevents duplicate Grok requests",
            COLOR_CYAN,
            false
        );
        break;
    case DASHBOARD_X_NEWS_REFRESH_BUSY:
        show_x_news_empty_activity(
            "A refresh is already running",
            "Your Mac is still validating the current request",
            COLOR_CYAN,
            true
        );
        break;
    case DASHBOARD_X_NEWS_REFRESH_DISABLED:
        show_x_news_empty_activity(
            "X News is off on this Mac",
            "Enable it once in the ILO Board companion to continue",
            COLOR_AMBER,
            false
        );
        break;
    case DASHBOARD_X_NEWS_REFRESH_FAILED:
    default:
        show_x_news_empty_activity(
            "No verified update accepted",
            "Nothing unsafe was cached  /  pull down to try again later",
            COLOR_AMBER,
            false
        );
        break;
    }
    lvgl_port_unlock();
}

static const char *weather_condition(int code)
{
    if (code == 0) return "Clear";
    if (code <= 3) return "Partly cloudy";
    if (code == 45 || code == 48) return "Fog";
    if (code >= 51 && code <= 57) return "Drizzle";
    if (code >= 61 && code <= 67) return "Rain";
    if (code >= 71 && code <= 77) return "Snow";
    if (code >= 80 && code <= 82) return "Rain showers";
    if (code == 85 || code == 86) return "Snow showers";
    if (code >= 95) return "Thunderstorm";
    return "Mixed conditions";
}

static const char *dashboard_weather_icon(int code)
{
    if (code == 0) return LV_SYMBOL_OK;
    if (code <= 3 || code == 45 || code == 48) return LV_SYMBOL_IMAGE;
    if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return LV_SYMBOL_TINT;
    if ((code >= 71 && code <= 77) || code == 85 || code == 86) return LV_SYMBOL_BULLET;
    if (code >= 95) return LV_SYMBOL_CHARGE;
    return LV_SYMBOL_IMAGE;
}

static double display_temperature(float celsius)
{
    return current_settings.use_fahrenheit ? ((double)celsius * 9.0 / 5.0) + 32.0 : (double)celsius;
}

static const char *temperature_unit(void)
{
    return current_settings.use_fahrenheit ? "F" : "C";
}

static void render_dashboard_weather(const weather_model_t *model)
{
    if (model == NULL || dashboard_weather_location_label == NULL) return;
    const bool has_values = model->state == WEATHER_STATE_LIVE || model->state == WEATHER_STATE_STALE;
    const char *location = model->location[0] != 0 ? model->location : "Weather";
    const char *state = "OFFLINE";
    const char *condition = "Forecast unavailable";
    const char *icon = LV_SYMBOL_GPS;
    lv_color_t color = COLOR_FOG;

    if (model->state == WEATHER_STATE_LIVE) {
        state = "LIVE";
        color = COLOR_SIGNAL;
    } else if (model->state == WEATHER_STATE_STALE) {
        state = "STALE";
        color = COLOR_AMBER;
    } else if (model->state == WEATHER_STATE_LOADING) {
        state = "UPDATING";
        condition = "Fetching forecast";
        icon = LV_SYMBOL_REFRESH;
        color = COLOR_CYAN;
    } else if (model->state == WEATHER_STATE_NOT_CONFIGURED) {
        state = "SETUP";
        condition = "Location needed";
        color = COLOR_AMBER;
    }

    if (has_values) {
        char temperature[24];
        snprintf(
            temperature,
            sizeof(temperature),
            "%.0f %s",
            display_temperature(model->temperature_c),
            temperature_unit()
        );
        lv_label_set_text(dashboard_weather_temperature_label, temperature);
        condition = weather_condition(model->weather_code);
        icon = dashboard_weather_icon(model->weather_code);
    } else {
        lv_label_set_text(
            dashboard_weather_temperature_label,
            current_settings.use_fahrenheit ? "-- F" : "-- C"
        );
    }
    lv_label_set_text(dashboard_weather_location_label, location);
    lv_label_set_text(dashboard_weather_icon_label, icon);
    lv_label_set_text(dashboard_weather_condition_label, condition);
    lv_label_set_text(dashboard_weather_state_label, state);
    lv_obj_set_style_bg_color(dashboard_weather_icon_box, color, 0);
    lv_obj_set_style_text_color(
        dashboard_weather_icon_label,
        model->state == WEATHER_STATE_LIVE ? COLOR_CARBON : COLOR_MIST,
        0
    );
    lv_obj_set_style_text_color(dashboard_weather_state_label, color, 0);
}

static void render_weather(const weather_model_t *model)
{
    if (model == NULL || weather_location_label == NULL) return;
    render_dashboard_weather(model);
    lv_label_set_text(weather_location_label, model->location[0] != 0 ? model->location : "Weather");

    const char *state_text = "OFFLINE";
    lv_color_t state_color = COLOR_FOG;
    switch (model->state) {
    case WEATHER_STATE_LIVE:
        state_text = "LIVE";
        state_color = COLOR_SIGNAL;
        break;
    case WEATHER_STATE_STALE:
        state_text = "STALE";
        state_color = COLOR_AMBER;
        break;
    case WEATHER_STATE_LOADING:
        state_text = "UPDATING";
        state_color = COLOR_CYAN;
        break;
    case WEATHER_STATE_NOT_CONFIGURED:
        state_text = "SETUP NEEDED";
        state_color = COLOR_AMBER;
        break;
    case WEATHER_STATE_ERROR:
    default:
        state_text = "OFFLINE";
        break;
    }
    lv_label_set_text(weather_state_label, state_text);
    lv_obj_set_style_text_color(weather_state_label, state_color, 0);

    if (model->state == WEATHER_STATE_LIVE || model->state == WEATHER_STATE_STALE) {
        char text[96];
        snprintf(text, sizeof(text), "%.0f %s", display_temperature(model->temperature_c), temperature_unit());
        lv_label_set_text(weather_temperature_label, text);
        lv_label_set_text(weather_condition_label, weather_condition(model->weather_code));
        snprintf(
            text,
            sizeof(text),
            "Feels %.0f %s  /  Wind %.1f m/s",
            display_temperature(model->apparent_c),
            temperature_unit(),
            (double)model->wind_ms
        );
        lv_label_set_text(weather_details_label, text);
        static const char *day_names[WEATHER_FORECAST_DAYS] = { "TODAY", "TOMORROW", "+2 DAYS" };
        for (int index = 0; index < WEATHER_FORECAST_DAYS && index < model->day_count; ++index) {
            snprintf(
                text,
                sizeof(text),
                "%s\n%s    %.0f %s - %.0f %s",
                day_names[index],
                weather_condition(model->days[index].weather_code),
                display_temperature(model->days[index].maximum_c),
                temperature_unit(),
                display_temperature(model->days[index].minimum_c),
                temperature_unit()
            );
            lv_label_set_text(weather_day_labels[index], text);
        }
    } else if (model->state == WEATHER_STATE_NOT_CONFIGURED) {
        lv_label_set_text(weather_temperature_label, current_settings.use_fahrenheit ? "-- F" : "-- C");
        lv_label_set_text(weather_condition_label, "Choose a weather location");
        lv_label_set_text(weather_details_label, "Use Mac companion location or USB setup");
    } else if (model->state == WEATHER_STATE_ERROR) {
        lv_label_set_text(weather_temperature_label, current_settings.use_fahrenheit ? "-- F" : "-- C");
        lv_label_set_text(weather_condition_label, "Forecast unavailable");
        lv_label_set_text(weather_details_label, "Retrying automatically in 1 minute");
    }
}

void dashboard_ui_set_weather(const weather_model_t *model)
{
    if (model == NULL || weather_location_label == NULL) return;
    lvgl_port_lock(0);
    latest_weather_model = *model;
    latest_weather_valid = true;
    if ((!latest_model_valid || !latest_model.host_time_available)
        && (model->state == WEATHER_STATE_LIVE || model->state == WEATHER_STATE_STALE)
        && model->timezone_abbreviation[0] != 0) {
        set_clock_timezone_locked(model->utc_offset_seconds, model->timezone_abbreviation);
    }
    render_weather(model);
    lvgl_port_unlock();
}

esp_err_t dashboard_ui_capture_rgb565(uint8_t **pixels, size_t *size)
{
    if (pixels == NULL || size == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    *pixels = NULL;
    *size = 0;
    if (ui_display == NULL) {
        return ESP_ERR_INVALID_STATE;
    }

    const size_t row_bytes = ILO_BOARD_WIDTH * 2;
    const size_t capture_size = row_bytes * ILO_BOARD_HEIGHT;
    uint8_t *capture = heap_caps_malloc(capture_size, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (capture == NULL) {
        return ESP_ERR_NO_MEM;
    }
    if (!lvgl_port_lock(1000)) {
        heap_caps_free(capture);
        return ESP_ERR_TIMEOUT;
    }

    lv_refr_now(ui_display);
    lv_draw_buf_t *draw_buffer = lv_display_get_buf_active(ui_display);
    bool valid = draw_buffer != NULL
        && draw_buffer->data != NULL
        && draw_buffer->header.cf == LV_COLOR_FORMAT_RGB565
        && draw_buffer->header.w == ILO_BOARD_WIDTH
        && draw_buffer->header.h == ILO_BOARD_HEIGHT
        && draw_buffer->header.stride >= row_bytes
        && draw_buffer->data_size >= draw_buffer->header.stride * ILO_BOARD_HEIGHT;
    if (valid) {
        for (size_t row = 0; row < ILO_BOARD_HEIGHT; ++row) {
            memcpy(capture + (row * row_bytes), draw_buffer->data + (row * draw_buffer->header.stride), row_bytes);
        }
    }
    lvgl_port_unlock();

    if (!valid) {
        heap_caps_free(capture);
        return ESP_ERR_INVALID_SIZE;
    }
    *pixels = capture;
    *size = capture_size;
    return ESP_OK;
}
