#pragma once
#include <stddef.h>
#include <string.h>

static inline const char *WGTypeUnqualified(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) ++type;
    return type ? type : "";
}

static inline unsigned WGIntegerWidth(const char *raw) {
    const char *type = WGTypeUnqualified(raw);
    if (!strcmp(type, "I") || !strcmp(type, "i")) return 4;
    if (!strcmp(type, "Q") || !strcmp(type, "q")) return 8;
    if (!strcmp(type, "L") || !strcmp(type, "l")) return sizeof(long);
    return 0;
}

static inline int WGIsBool(const char *raw) {
    const char *type = WGTypeUnqualified(raw);
    return !strcmp(type, "B") || !strcmp(type, "c");
}
