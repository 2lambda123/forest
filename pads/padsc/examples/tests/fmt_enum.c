#define DEF_INPUT_FILE "../../data/enum"

#define PADS_TY(suf) orderStates ## suf
#define PPADS_TY(pref) pref ## orderStates
#define DELIMS ":,"
#include "enum.h"
#include "template/read_format.h"

