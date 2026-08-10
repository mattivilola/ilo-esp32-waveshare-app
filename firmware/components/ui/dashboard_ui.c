#include "dashboard_ui.h"

#include <stdio.h>
#include <stdint.h>

#include "esp_check.h"
#include "esp_lvgl_port.h"
#include "lvgl.h"
#include "board_waveshare_5.h"
#include "ilo_icon_48.h"

#define COLOR_CARBON  lv_color_hex(0x0A0F14)
#define COLOR_SLATE   lv_color_hex(0x131B22)
#define COLOR_STEEL   lv_color_hex(0x24313C)
#define COLOR_SIGNAL  lv_color_hex(0x65E5B8)
#define COLOR_AMBER   lv_color_hex(0xFFB55A)
#define COLOR_MIST    lv_color_hex(0xF3F7F8)
#define COLOR_FOG     lv_color_hex(0x8EA2B2)
#define COLOR_CYAN    lv_color_hex(0x37B3D9)

#define PAGE_COUNT 4
#define DASHBOARD_VISIBLE_TASKS 4
#define CODEX_VISIBLE_TASKS 3
#define SCREENSAVER_TIMEOUT_MS 120000

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
static lv_obj_t *page_eyebrow_label;
static lv_obj_t *page_title_label;
static lv_obj_t *tileview;
static lv_obj_t *tiles[PAGE_COUNT];
static lv_obj_t *nav_buttons[PAGE_COUNT];
static lv_obj_t *nav_labels[PAGE_COUNT];
static lv_obj_t *screensaver;
static lv_obj_t *screensaver_status_dot;
static lv_display_t *ui_display;

static const char *page_eyebrows[PAGE_COUNT] = {
    "ILO / WORK PULSE", "ILO / CODEX", "ILO / WEATHER", "ILO / SETTINGS"
};
static const char *page_titles[PAGE_COUNT] = {
    "Dashboard", "Codex", "Weather", "Settings"
};

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
    lv_obj_t *location = create_label(page, "Helsinki", &lv_font_montserrat_20, COLOR_MIST);
    lv_obj_set_pos(location, 22, 8);
    lv_obj_t *sample = create_label(page, "SAMPLE DATA", &lv_font_montserrat_14, COLOR_AMBER);
    lv_obj_set_pos(sample, 130, 12);
    lv_obj_t *direct = create_label(page, "Direct Wi-Fi capable", &lv_font_montserrat_14, COLOR_SIGNAL);
    lv_obj_align(direct, LV_ALIGN_TOP_RIGHT, -22, 12);

    lv_obj_t *now = create_card(page, 22, 52, 350, 230, 16);
    lv_obj_t *now_label = create_label(now, "NOW", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_align(now_label, LV_ALIGN_TOP_LEFT, 18, 18);
    lv_obj_t *temperature = create_label(now, "14 C", &lv_font_montserrat_28, COLOR_MIST);
    lv_obj_align(temperature, LV_ALIGN_TOP_LEFT, 18, 66);
    lv_obj_t *condition = create_label(now, "Light rain", &lv_font_montserrat_20, COLOR_CYAN);
    lv_obj_align(condition, LV_ALIGN_TOP_LEFT, 18, 118);
    lv_obj_t *details = create_label(now, "Feels 12 C  /  Wind 5 m/s", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_align(details, LV_ALIGN_BOTTOM_LEFT, 18, -18);

    lv_obj_t *hours = create_card(page, 388, 52, 608, 230, 16);
    lv_obj_t *hours_title = create_label(hours, "NEXT HOURS", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_align(hours_title, LV_ALIGN_TOP_LEFT, 18, 18);
    lv_obj_t *hour_values = create_label(
        hours,
        "NOW       11        12        13        14\n 14 C      15 C      16 C      16 C      15 C",
        &lv_font_montserrat_14,
        COLOR_MIST
    );
    lv_obj_set_style_text_line_space(hour_values, 18, 0);
    lv_obj_align(hour_values, LV_ALIGN_TOP_LEFT, 18, 62);
    lv_obj_t *transition = create_label(hours, "Rain eases around 13:00", &lv_font_montserrat_14, COLOR_CYAN);
    lv_obj_align(transition, LV_ALIGN_BOTTOM_LEFT, 18, -22);

    lv_obj_t *today = create_card(page, 22, 298, 314, 96, 14);
    lv_obj_t *today_text = create_label(today, "TODAY\nRain         16 C - 10 C", &lv_font_montserrat_14, COLOR_MIST);
    lv_obj_set_style_text_line_space(today_text, 10, 0);
    lv_obj_align(today_text, LV_ALIGN_LEFT_MID, 18, 0);
    lv_obj_t *tomorrow = create_card(page, 352, 298, 308, 96, 14);
    lv_obj_t *tomorrow_text = create_label(tomorrow, "TUE\nCloudy      18 C - 11 C", &lv_font_montserrat_14, COLOR_MIST);
    lv_obj_set_style_text_line_space(tomorrow_text, 10, 0);
    lv_obj_align(tomorrow_text, LV_ALIGN_LEFT_MID, 18, 0);
    lv_obj_t *later = create_card(page, 676, 298, 320, 96, 14);
    lv_obj_t *later_text = create_label(later, "WED\nClear       20 C - 12 C", &lv_font_montserrat_14, COLOR_MIST);
    lv_obj_set_style_text_line_space(later_text, 10, 0);
    lv_obj_align(later_text, LV_ALIGN_LEFT_MID, 18, 0);
}

static void build_settings_page(lv_obj_t *page)
{
    lv_obj_t *display = create_card(page, 22, 8, 480, 386, 16);
    lv_obj_t *display_title = create_label(display, "DISPLAY", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_align(display_title, LV_ALIGN_TOP_LEFT, 18, 18);
    lv_obj_t *display_values = create_label(
        display,
        "Brightness                  72%\n\nIdle dim                 2 minutes\n\nScreen off              10 minutes\n\nScreensaver            Pulse clock",
        &lv_font_montserrat_14,
        COLOR_MIST
    );
    lv_obj_set_style_text_line_space(display_values, 8, 0);
    lv_obj_align(display_values, LV_ALIGN_TOP_LEFT, 18, 58);
    lv_obj_t *power_note = create_label(
        display,
        "Backlight dim/off saves power.\nHardware controls await board verification.",
        &lv_font_montserrat_14,
        COLOR_FOG
    );
    lv_obj_set_style_text_line_space(power_note, 7, 0);
    lv_obj_align(power_note, LV_ALIGN_BOTTOM_LEFT, 18, -20);

    lv_obj_t *connections = create_card(page, 518, 8, 478, 258, 16);
    lv_obj_t *connection_title = create_label(connections, "CONNECTIONS", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_align(connection_title, LV_ALIGN_TOP_LEFT, 18, 18);
    lv_obj_t *connection_values = create_label(
        connections,
        "Wi-Fi                  KNOWN NETWORK\n\nMac companion          PAIRED\n\nWeather              DIRECT READY",
        &lv_font_montserrat_14,
        COLOR_MIST
    );
    lv_obj_set_style_text_line_space(connection_values, 8, 0);
    lv_obj_align(connection_values, LV_ALIGN_TOP_LEFT, 18, 58);
    lv_obj_t *wifi_note = create_label(
        connections,
        "Wi-Fi password changes stay in secure USB setup.",
        &lv_font_montserrat_14,
        COLOR_FOG
    );
    lv_obj_align(wifi_note, LV_ALIGN_BOTTOM_LEFT, 18, -18);

    lv_obj_t *privacy = create_card(page, 518, 282, 478, 112, 16);
    lv_obj_t *privacy_icon = lv_image_create(privacy);
    lv_image_set_src(privacy_icon, &ilo_icon_48);
    lv_obj_align(privacy_icon, LV_ALIGN_LEFT_MID, 18, 0);
    lv_obj_t *privacy_text = create_label(
        privacy,
        "Privacy mode\nTask summaries visible",
        &lv_font_montserrat_14,
        COLOR_MIST
    );
    lv_obj_set_style_text_line_space(privacy_text, 8, 0);
    lv_obj_align(privacy_text, LV_ALIGN_LEFT_MID, 84, 0);
    lv_obj_t *privacy_state = create_label(privacy, "ON", &lv_font_montserrat_14, COLOR_SIGNAL);
    lv_obj_align(privacy_state, LV_ALIGN_RIGHT_MID, -20, 0);
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
        lv_display_trigger_activity(ui_display);
        lv_obj_add_flag(screensaver, LV_OBJ_FLAG_HIDDEN);
    }
}

static void screensaver_timer(lv_timer_t *timer)
{
    (void)timer;
    uint32_t inactive = lv_display_get_inactive_time(ui_display);
    if (inactive >= SCREENSAVER_TIMEOUT_MS) {
        lv_obj_remove_flag(screensaver, LV_OBJ_FLAG_HIDDEN);
    } else if (inactive < 1000) {
        lv_obj_add_flag(screensaver, LV_OBJ_FLAG_HIDDEN);
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

    lv_obj_t *icon = lv_image_create(screensaver);
    lv_image_set_src(icon, &ilo_icon_48);
    lv_obj_align(icon, LV_ALIGN_CENTER, -92, -20);
    lv_obj_t *pulse = create_label(screensaver, "ILO / PULSE", &lv_font_montserrat_28, COLOR_MIST);
    lv_obj_align(pulse, LV_ALIGN_CENTER, 36, -30);
    lv_obj_t *wake = create_label(screensaver, "Touch to wake", &lv_font_montserrat_14, COLOR_FOG);
    lv_obj_align(wake, LV_ALIGN_CENTER, 36, 14);
    screensaver_status_dot = lv_obj_create(screensaver);
    set_clean_box(screensaver_status_dot, COLOR_FOG, LV_RADIUS_CIRCLE);
    lv_obj_set_size(screensaver_status_dot, 10, 10);
    lv_obj_align(screensaver_status_dot, LV_ALIGN_CENTER, -22, 62);

    lv_timer_create(screensaver_timer, 1000, NULL);
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
    lv_obj_align(connection_label, LV_ALIGN_RIGHT_MID, 0, 0);

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

    build_codex_page(tiles[1]);
    build_weather_page(tiles[2]);
    build_settings_page(tiles[3]);

    for (int i = 0; i < PAGE_COUNT; ++i) {
        nav_buttons[i] = lv_button_create(screen);
        set_clean_box(nav_buttons[i], i == 0 ? COLOR_STEEL : COLOR_CARBON, LV_RADIUS_CIRCLE);
        lv_obj_set_size(nav_buttons[i], 238, 42);
        lv_obj_set_pos(nav_buttons[i], 22 + (i * 248), 550);
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
        lv_label_set_text(task_summaries[i], task->summary);
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
        lv_label_set_text(codex_summaries[i], task->summary);
        lv_color_t dot = COLOR_STEEL;
        if (task->attention != DASHBOARD_ATTENTION_NONE) {
            dot = COLOR_AMBER;
        } else if (task->state == DASHBOARD_TASK_ACTIVE) {
            dot = COLOR_SIGNAL;
        }
        lv_obj_set_style_bg_color(codex_dots[i], dot, 0);
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
