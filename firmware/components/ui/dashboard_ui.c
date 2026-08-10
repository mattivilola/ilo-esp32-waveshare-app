#include "dashboard_ui.h"

#include <string.h>

#include "esp_heap_caps.h"
#include <stdio.h>
#include <stdint.h>
#include <time.h>

#include "esp_check.h"
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
#define DASHBOARD_VISIBLE_TASKS 3
#define CODEX_VISIBLE_TASKS 3
#define X_NEWS_VISIBLE_STORIES 3
#define MINUTE_MS 60000U

static lv_obj_t *connection_label;
static lv_obj_t *attention_count_label;
static lv_obj_t *attention_hint_label;
static lv_obj_t *task_rows[DASHBOARD_MAX_TASKS];
static lv_obj_t *task_titles[DASHBOARD_MAX_TASKS];
static lv_obj_t *task_summaries[DASHBOARD_MAX_TASKS];
static lv_obj_t *task_dots[DASHBOARD_MAX_TASKS];
static lv_obj_t *codex_rows[CODEX_VISIBLE_TASKS];
static lv_obj_t *codex_titles[CODEX_VISIBLE_TASKS];
static lv_obj_t *codex_summaries[CODEX_VISIBLE_TASKS];
static lv_obj_t *codex_dots[CODEX_VISIBLE_TASKS];
static lv_obj_t *x_news_status_label;
static lv_obj_t *x_news_empty_card;
static lv_obj_t *x_news_rows[X_NEWS_VISIBLE_STORIES];
static lv_obj_t *x_news_titles[X_NEWS_VISIBLE_STORIES];
static lv_obj_t *x_news_summaries[X_NEWS_VISIBLE_STORIES];
static lv_obj_t *x_news_meta[X_NEWS_VISIBLE_STORIES];
static lv_obj_t *page_eyebrow_label;
static lv_obj_t *page_title_label;
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
static bool display_asleep;
static bool consuming_wake_touch;
static uint32_t screensaver_tick;
static uint32_t focus_remaining_seconds;
static bool focus_running;
static int32_t clock_utc_offset_seconds;
static char clock_timezone_abbreviation[8] = "UTC";
static weather_model_t latest_weather_model;
static bool latest_weather_valid;

static void render_weather(const weather_model_t *model);

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

static void attention_tapped(lv_event_t *event)
{
    if (lv_event_get_code(event) != LV_EVENT_CLICKED || attention_hint_label == NULL) {
        return;
    }
    lv_label_set_text(attention_hint_label, "Touch input ready\nActions stay on Mac");
    lv_obj_set_style_text_color(attention_hint_label, COLOR_SIGNAL, 0);
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
        lv_obj_add_flag(codex_rows[i], LV_OBJ_FLAG_HIDDEN);

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

    lv_obj_t *safety = create_card(page, 702, 48, 294, 332, 16);
    lv_obj_t *safety_title = create_label(safety, "SAFETY BOUNDARY", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_align(safety_title, LV_ALIGN_TOP_LEFT, 18, 18);
    lv_obj_t *readonly = create_label(safety, "READ ONLY", &lv_font_montserrat_28, COLOR_SIGNAL);
    lv_obj_align(readonly, LV_ALIGN_TOP_LEFT, 18, 55);
    lv_obj_t *explanation = create_label(
        safety,
        "Recent task history is safe to show.\nApprovals, answers and commands\nstay on the Mac.",
        &lv_font_montserrat_14,
        COLOR_FOG
    );
    lv_obj_set_style_text_line_space(explanation, 7, 0);
    lv_obj_align(explanation, LV_ALIGN_TOP_LEFT, 18, 110);
    lv_obj_t *capability = create_label(
        safety,
        "APP SERVER       LOCAL\nDESKTOP TASKS    HISTORY\nREMOTE ACTIONS   OFF",
        &lv_font_montserrat_14,
        COLOR_MIST
    );
    lv_obj_set_style_text_line_space(capability, 9, 0);
    lv_obj_align(capability, LV_ALIGN_BOTTOM_LEFT, 18, -20);
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
    weather_details_label = create_label(now, "Direct Wi-Fi · Mac not required", &lv_font_montserrat_14, COLOR_FOG);
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

static void build_x_news_page(lv_obj_t *page)
{
    lv_obj_t *title = create_label(page, "AI + humanoid robotics", &lv_font_montserrat_20, COLOR_MIST);
    lv_obj_set_pos(title, 22, 8);
    x_news_status_label = create_label(page, "WAITING FOR VERIFIED MAC FEED", &lv_font_montserrat_14, COLOR_AMBER);
    lv_obj_align(x_news_status_label, LV_ALIGN_TOP_RIGHT, -22, 12);

    for (int i = 0; i < X_NEWS_VISIBLE_STORIES; ++i) {
        x_news_rows[i] = create_card(page, 22, 50 + (i * 112), 974, 102, 14);
        lv_obj_add_flag(x_news_rows[i], LV_OBJ_FLAG_HIDDEN);
        x_news_titles[i] = create_label(x_news_rows[i], "", &lv_font_montserrat_14, COLOR_MIST);
        lv_obj_set_width(x_news_titles[i], 700);
        lv_label_set_long_mode(x_news_titles[i], LV_LABEL_LONG_DOT);
        lv_obj_align(x_news_titles[i], LV_ALIGN_TOP_LEFT, 18, 16);
        x_news_summaries[i] = create_label(x_news_rows[i], "", &lv_font_montserrat_14, COLOR_FOG);
        lv_obj_set_width(x_news_summaries[i], 700);
        lv_label_set_long_mode(x_news_summaries[i], LV_LABEL_LONG_DOT);
        lv_obj_align(x_news_summaries[i], LV_ALIGN_BOTTOM_LEFT, 18, -16);
        x_news_meta[i] = create_label(x_news_rows[i], "", &lv_font_montserrat_14, COLOR_SIGNAL);
        lv_obj_set_width(x_news_meta[i], 220);
        lv_label_set_long_mode(x_news_meta[i], LV_LABEL_LONG_DOT);
        lv_obj_align(x_news_meta[i], LV_ALIGN_RIGHT_MID, -18, 0);
        lv_obj_set_style_text_align(x_news_meta[i], LV_TEXT_ALIGN_RIGHT, 0);
    }

    x_news_empty_card = create_card(page, 22, 50, 974, 326, 16);
    lv_obj_t *empty_title = create_label(x_news_empty_card, "No verified stories cached", &lv_font_montserrat_28, COLOR_MIST);
    lv_obj_align(empty_title, LV_ALIGN_CENTER, 0, -42);
    lv_obj_t *empty_help = create_label(
        x_news_empty_card,
        "Enable the optional Grok adapter on the Mac, then run\n./tools/host x-news refresh --allow-grok-tools",
        &lv_font_montserrat_14,
        COLOR_FOG
    );
    lv_obj_set_style_text_align(empty_help, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_text_line_space(empty_help, 8, 0);
    lv_obj_align(empty_help, LV_ALIGN_CENTER, 0, 24);
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
    lv_obj_t *power_note = create_label(
        display,
        "This 5B exposes binary backlight on/off, not PWM.\nWake touch is consumed to prevent accidental actions.",
        &lv_font_montserrat_14,
        COLOR_FOG
    );
    lv_obj_set_style_text_line_space(power_note, 7, 0);
    lv_obj_align(power_note, LV_ALIGN_BOTTOM_LEFT, 18, -20);

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
    lv_obj_t *connection_values = create_label(
        connections,
        "WI-FI  KNOWN     MAC  PAIRED     WEATHER  DIRECT",
        &lv_font_montserrat_14,
        COLOR_MIST
    );
    lv_obj_center(connection_values);
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
    if (index >= 0 && index < PAGE_COUNT) {
        lv_tileview_set_tile_by_index(tileview, (uint32_t)index, 0, LV_ANIM_ON);
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
    lv_obj_set_size(screensaver_content, 460, 190);
    lv_obj_clear_flag(screensaver_content, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE);
    lv_obj_center(screensaver_content);

    lv_obj_t *icon = lv_image_create(screensaver_content);
    lv_image_set_src(icon, &ilo_icon_48);
    lv_obj_align(icon, LV_ALIGN_CENTER, -180, -42);
    lv_obj_t *pulse = create_label(screensaver_content, "ILO / PULSE", &lv_font_montserrat_20, COLOR_SIGNAL);
    lv_obj_align(pulse, LV_ALIGN_CENTER, -70, -54);
    screensaver_clock_label = create_label(screensaver_content, "--:--", &lv_font_montserrat_28, COLOR_MIST);
    lv_obj_align(screensaver_clock_label, LV_ALIGN_CENTER, 62, -4);
    screensaver_date_label = create_label(screensaver_content, "TIME SYNC NEEDED", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_align(screensaver_date_label, LV_ALIGN_CENTER, 62, 36);
    lv_obj_t *wake = create_label(screensaver_content, "Touch to wake", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_align(wake, LV_ALIGN_CENTER, 62, 72);
    screensaver_status_dot = lv_obj_create(screensaver_content);
    set_clean_box(screensaver_status_dot, COLOR_FOG, LV_RADIUS_CIRCLE);
    lv_obj_set_size(screensaver_status_dot, 10, 10);
    lv_obj_align(screensaver_status_dot, LV_ALIGN_CENTER, -84, 72);

    lv_timer_create(screensaver_timer, 1000, NULL);
    refresh_clock_labels();
}

static void build_ui(void)
{
    lv_obj_t *screen = lv_screen_active();
    set_clean_box(screen, COLOR_CARBON, 0);
    lv_obj_set_scrollbar_mode(screen, LV_SCROLLBAR_MODE_OFF);

    lv_obj_t *rail = lv_obj_create(screen);
    set_clean_box(rail, COLOR_SIGNAL, 0);
    lv_obj_set_size(rail, 6, ILO_BOARD_HEIGHT);
    lv_obj_align(rail, LV_ALIGN_LEFT_MID, 0, 0);

    lv_obj_t *header = lv_obj_create(screen);
    set_clean_box(header, COLOR_CARBON, 0);
    lv_obj_set_size(header, ILO_BOARD_WIDTH - 40, 68);
    lv_obj_align(header, LV_ALIGN_TOP_LEFT, 22, 0);

    lv_obj_t *brand_icon = lv_image_create(header);
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
    tiles[3] = lv_tileview_add_tile(tileview, 3, 0, LV_DIR_LEFT);
    for (int i = 0; i < PAGE_COUNT; ++i) {
        set_clean_box(tiles[i], COLOR_CARBON, 0);
        lv_obj_set_scrollbar_mode(tiles[i], LV_SCROLLBAR_MODE_OFF);
    }

    lv_obj_t *attention = lv_obj_create(tiles[0]);
    set_clean_box(attention, COLOR_SLATE, 18);
    lv_obj_set_size(attention, 238, 410);
    lv_obj_set_pos(attention, 22, 8);
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

    build_screensaver(screen);
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
    focus_remaining_seconds = (uint32_t)current_settings.focus_minutes * 60U;
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
    latest_model = *model;
    latest_model_valid = true;
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
    if (x_news_status_label != NULL) {
        if (model->news_count > 0) {
            char status[40];
            snprintf(status, sizeof(status), "%u VERIFIED STORIES", (unsigned int)model->news_count);
            lv_label_set_text(x_news_status_label, status);
            lv_obj_set_style_text_color(x_news_status_label, COLOR_SIGNAL, 0);
            if (x_news_empty_card != NULL) lv_obj_add_flag(x_news_empty_card, LV_OBJ_FLAG_HIDDEN);
        } else {
            lv_label_set_text(x_news_status_label, "WAITING FOR VERIFIED MAC FEED");
            lv_obj_set_style_text_color(x_news_status_label, COLOR_AMBER, 0);
            if (x_news_empty_card != NULL) lv_obj_remove_flag(x_news_empty_card, LV_OBJ_FLAG_HIDDEN);
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
        snprintf(meta, sizeof(meta), "%s · %s · %s", story->category, story->confidence, story->handle);
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

static double display_temperature(float celsius)
{
    return current_settings.use_fahrenheit ? ((double)celsius * 9.0 / 5.0) + 32.0 : (double)celsius;
}

static const char *temperature_unit(void)
{
    return current_settings.use_fahrenheit ? "F" : "C";
}

static void render_weather(const weather_model_t *model)
{
    if (model == NULL || weather_location_label == NULL) return;
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
        lv_label_set_text(weather_condition_label, "Add location over USB");
        lv_label_set_text(weather_details_label, "Run ./tools/board provision");
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
    if ((model->state == WEATHER_STATE_LIVE || model->state == WEATHER_STATE_STALE)
        && model->timezone_abbreviation[0] != 0) {
        clock_utc_offset_seconds = model->utc_offset_seconds;
        strlcpy(
            clock_timezone_abbreviation,
            model->timezone_abbreviation,
            sizeof(clock_timezone_abbreviation)
        );
        refresh_clock_labels();
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
