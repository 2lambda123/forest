#define DEF_INPUT_FILE "../../data/ex_data.struct"

#define EXTRA_GOOD_READ_CODE do { \
  error(2, "testtwo_read returned: id %d  ts %d  f %d ", rep.header.id, rep.header.ts, rep.f); \
} while (0)

#define EXTRA_BAD_READ_CODE do { \
  error(2, "testtwo_read returned: error"); \
} while (0)

#define PADS_TY(suf) testtwo ## suf
#define PPADS_TY(pref) pref ## testtwo
#include "struct.h"
#include "template/accum_report.h"

