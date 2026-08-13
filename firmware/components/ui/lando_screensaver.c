#include "lando_screensaver.h"

#include <stddef.h>
#include <stdint.h>

#include "lando_screensaver_asset.h"

#define LANDO_PANEL_WIDTH 340
#define LANDO_PANEL_HEIGHT 600
#define LANDO_PANEL_X 684
#define LANDO_IMAGE_X ((LANDO_PANEL_WIDTH - LANDO_SCREENSAVER_FRAME_WIDTH) / 2)
#define LANDO_IMAGE_Y 174

#define LANDO_COLOR_PANEL lv_color_hex(LANDO_SCREENSAVER_PANEL_COLOR_HEX)
#define LANDO_COLOR_DIVIDER lv_color_hex(0x5C6870)
#define LANDO_COLOR_SIGNAL lv_color_hex(0x65E5B8)
#define LANDO_COLOR_MIST lv_color_hex(0xF3F7F8)
#define LANDO_COLOR_FOG lv_color_hex(0xB8C3CA)

typedef enum {
    LANDO_ANIMATION_IDLE,
    LANDO_ANIMATION_WAVE,
} lando_animation_t;

extern const uint8_t lando_asset_start[] asm("_binary_lando_screensaver_rgb565_start");
extern const uint8_t lando_asset_end[] asm("_binary_lando_screensaver_rgb565_end");

static lv_image_dsc_t lando_frames[LANDO_SCREENSAVER_FRAME_COUNT];
static lv_obj_t *lando_image;
static lv_obj_t *lando_status_label;
static lv_timer_t *lando_timer;
static lando_animation_t lando_animation;
static uint8_t lando_frame;
static uint8_t lando_idle_loops;
static uint8_t lando_wave_interval_index;
static bool lando_active;
static bool lando_asset_valid;

static const uint16_t idle_durations[LANDO_SCREENSAVER_IDLE_COUNT] = {
    280, 110, 110, 140, 140, 320,
};

static const uint16_t wave_durations[LANDO_SCREENSAVER_WAVE_COUNT] = {
    140, 140, 140, 280,
};

// Roughly 13-22 seconds between gestures, without a random-number dependency.
static const uint8_t wave_intervals[] = { 12, 17, 14, 20 };

static lv_obj_t *create_label(
    lv_obj_t *parent,
    const char *text,
    const lv_font_t *font,
    lv_color_t color
)
{
    lv_obj_t *label = lv_label_create(parent);
    lv_label_set_text(label, text);
    lv_obj_set_style_text_font(label, font, 0);
    lv_obj_set_style_text_color(label, color, 0);
    lv_obj_clear_flag(label, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE);
    return label;
}

static bool prepare_frames(void)
{
    size_t asset_bytes = (size_t)(lando_asset_end - lando_asset_start);
    if (asset_bytes != LANDO_SCREENSAVER_ASSET_BYTES) {
        return false;
    }
    for (size_t index = 0; index < LANDO_SCREENSAVER_FRAME_COUNT; ++index) {
        lando_frames[index] = (lv_image_dsc_t) {
            .header.magic = LV_IMAGE_HEADER_MAGIC,
            .header.cf = LV_COLOR_FORMAT_RGB565,
            .header.flags = 0,
            .header.w = LANDO_SCREENSAVER_FRAME_WIDTH,
            .header.h = LANDO_SCREENSAVER_FRAME_HEIGHT,
            .header.stride = LANDO_SCREENSAVER_FRAME_WIDTH * 2,
            .data_size = LANDO_SCREENSAVER_FRAME_BYTES,
            .data = lando_asset_start + (index * LANDO_SCREENSAVER_FRAME_BYTES),
        };
    }
    return true;
}

static void show_frame(size_t index)
{
    if (!lando_asset_valid || lando_image == NULL || index >= LANDO_SCREENSAVER_FRAME_COUNT) {
        return;
    }
    lv_image_set_src(lando_image, &lando_frames[index]);
}

static void start_idle(void)
{
    lando_animation = LANDO_ANIMATION_IDLE;
    lando_frame = 0;
    show_frame(LANDO_SCREENSAVER_IDLE_START);
    if (lando_status_label != NULL) {
        lv_label_set_text(lando_status_label, "KEEPING WATCH");
    }
    lv_timer_set_period(lando_timer, idle_durations[0]);
}

static void start_wave(void)
{
    lando_animation = LANDO_ANIMATION_WAVE;
    lando_frame = 0;
    show_frame(LANDO_SCREENSAVER_WAVE_START);
    if (lando_status_label != NULL) {
        lv_label_set_text(lando_status_label, "WAVING HELLO");
    }
    lv_timer_set_period(lando_timer, wave_durations[0]);
}

static void animation_tick(lv_timer_t *timer)
{
    if (!lando_active || !lando_asset_valid) {
        lv_timer_pause(timer);
        return;
    }

    if (lando_animation == LANDO_ANIMATION_WAVE) {
        ++lando_frame;
        if (lando_frame >= LANDO_SCREENSAVER_WAVE_COUNT) {
            start_idle();
            return;
        }
        show_frame(LANDO_SCREENSAVER_WAVE_START + lando_frame);
        lv_timer_set_period(timer, wave_durations[lando_frame]);
        return;
    }

    ++lando_frame;
    if (lando_frame >= LANDO_SCREENSAVER_IDLE_COUNT) {
        lando_frame = 0;
        ++lando_idle_loops;
        uint8_t interval = wave_intervals[
            lando_wave_interval_index % (sizeof(wave_intervals) / sizeof(wave_intervals[0]))
        ];
        if (lando_idle_loops >= interval) {
            lando_idle_loops = 0;
            ++lando_wave_interval_index;
            start_wave();
            return;
        }
    }
    show_frame(LANDO_SCREENSAVER_IDLE_START + lando_frame);
    lv_timer_set_period(timer, idle_durations[lando_frame]);
}

lv_obj_t *lando_screensaver_create(lv_obj_t *parent)
{
    lv_obj_t *panel = lv_obj_create(parent);
    lv_obj_set_size(panel, LANDO_PANEL_WIDTH, LANDO_PANEL_HEIGHT);
    lv_obj_set_pos(panel, LANDO_PANEL_X, 0);
    lv_obj_set_style_bg_color(panel, LANDO_COLOR_PANEL, 0);
    lv_obj_set_style_bg_opa(panel, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(panel, 0, 0);
    lv_obj_set_style_radius(panel, 0, 0);
    lv_obj_set_style_pad_all(panel, 0, 0);
    lv_obj_clear_flag(panel, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE);

    lv_obj_t *divider = lv_obj_create(panel);
    lv_obj_set_size(divider, 2, LANDO_PANEL_HEIGHT);
    lv_obj_set_pos(divider, 0, 0);
    lv_obj_set_style_bg_color(divider, LANDO_COLOR_DIVIDER, 0);
    lv_obj_set_style_bg_opa(divider, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(divider, 0, 0);
    lv_obj_set_style_radius(divider, 0, 0);
    lv_obj_clear_flag(divider, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE);

    lv_obj_t *eyebrow = create_label(panel, "ILO PET", &lv_font_montserrat_14, LANDO_COLOR_SIGNAL);
    lv_obj_set_pos(eyebrow, 34, 42);
    lv_obj_t *name = create_label(panel, "LANDO", &lv_font_montserrat_28, LANDO_COLOR_MIST);
    lv_obj_set_pos(name, 34, 68);
    lv_obj_t *identity = create_label(panel, "BORDER COLLIE / AWAKE", &lv_font_montserrat_14, LANDO_COLOR_FOG);
    lv_obj_set_pos(identity, 34, 111);

    lando_asset_valid = prepare_frames();
    if (lando_asset_valid) {
        lando_image = lv_image_create(panel);
        lv_obj_set_pos(lando_image, LANDO_IMAGE_X, LANDO_IMAGE_Y);
        lv_obj_clear_flag(lando_image, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE);
        show_frame(LANDO_SCREENSAVER_IDLE_START);
    }

    lv_obj_t *status_dot = lv_obj_create(panel);
    lv_obj_set_size(status_dot, 10, 10);
    lv_obj_set_pos(status_dot, 78, 434);
    lv_obj_set_style_bg_color(status_dot, lando_asset_valid ? LANDO_COLOR_SIGNAL : LANDO_COLOR_FOG, 0);
    lv_obj_set_style_bg_opa(status_dot, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(status_dot, 0, 0);
    lv_obj_set_style_radius(status_dot, LV_RADIUS_CIRCLE, 0);
    lv_obj_clear_flag(status_dot, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE);
    lando_status_label = create_label(
        panel,
        lando_asset_valid ? "KEEPING WATCH" : "ASSET OFFLINE",
        &lv_font_montserrat_14,
        LANDO_COLOR_MIST
    );
    lv_obj_set_pos(lando_status_label, 98, 428);

    lv_obj_t *hint = create_label(panel, "A quiet companion for deep work.", &lv_font_montserrat_14, LANDO_COLOR_FOG);
    lv_obj_set_width(hint, 272);
    lv_obj_set_style_text_align(hint, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_pos(hint, 34, 482);

    lando_timer = lv_timer_create(animation_tick, idle_durations[0], NULL);
    lv_timer_pause(lando_timer);
    return panel;
}

void lando_screensaver_set_active(bool active)
{
    if (lando_timer == NULL || lando_active == active) {
        return;
    }
    lando_active = active;
    if (!active || !lando_asset_valid) {
        lv_timer_pause(lando_timer);
        return;
    }
    lando_idle_loops = 0;
    start_idle();
    lv_timer_resume(lando_timer);
}
