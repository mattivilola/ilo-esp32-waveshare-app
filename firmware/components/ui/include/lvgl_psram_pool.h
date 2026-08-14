#pragma once

#include <stddef.h>

#include "esp_heap_caps.h"

// LVGL invokes this once during lv_init(). Requiring SPIRAM keeps its complete
// object/text pool away from the internal DMA-capable heap needed by Wi-Fi.
#define LV_MEM_POOL_ALLOC(size) \
    heap_caps_malloc((size), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT)
