// #define MAX_RECS 20
#define IO_DISC_MK P_fwrec_noseek_make(0, 450, 0)
#define PADS_TY(suf) cpy_rps ## suf
#define PPADS_TY(pref) pref ## cpy_rps

#include "cpyrecgen_rps.h"
#include "template/accum_report.h"
