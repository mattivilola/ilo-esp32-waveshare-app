#pragma once

#include <stdbool.h>

#include "lvgl.h"

// Creates the fixed right-third pet panel. The returned object is not clickable,
// so the parent screensaver continues to own the wake touch.
lv_obj_t *lando_screensaver_create(lv_obj_t *parent);

// Animation is explicitly paused whenever the saver is hidden or the backlight
// is off, keeping frame swaps out of the normal dashboard rendering path.
void lando_screensaver_set_active(bool active);
