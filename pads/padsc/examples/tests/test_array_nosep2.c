#define DEF_INPUT_FILE "../../data/array_nosep2"

#define EXTRA_GOOD_READ_CODE do { \
      error(2, "entry_read returned array of length: %d", rep.length); \
} while (0)

#define EXTRA_BAD_READ_CODE do { \
      error(2, "entry_read returned: error"); \
} while (0)

#define PADS_TY(suf) entry ## suf
#define PPADS_TY(pref) pref ## entry

#include "array_nosep2.h"
#include "template/accum_report.h"

