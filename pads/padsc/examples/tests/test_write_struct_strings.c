#include "libpadsc.h"
#include "struct_strings.h"
#define FILENAME  "../../data/ex_data.struct_strings_write"

PDC_error_t my_string_inv_val(PDC_t *pdc, void *ed_void, void *val_void, void **type_args) {
  PDC_base_ed *ed  = (PDC_base_ed*)ed_void;
  PDC_string  *val = (PDC_string*)val_void;
  if (ed->errCode == PDC_USER_CONSTRAINT_VIOLATION) {
    PDC_string_Cstr_copy(pdc, val, "BAD_LEN", 7);
  } else {
    PDC_string_Cstr_copy(pdc, val, "INV_STR", 7);
  }
  return PDC_OK;
}

PDC_error_t my_string_fw_inv_val(PDC_t *pdc, void *ed_void, void *val_void, void **type_args) {
  PDC_base_ed *ed    = (PDC_base_ed*)ed_void;
  PDC_string  *val   = (PDC_string*)val_void;
  size_t      *width = type_args[0];
  if (ed->errCode == PDC_USER_CONSTRAINT_VIOLATION) {
    PDC_string_Cstr_copy(pdc, val, "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", *width);
  } else {
    PDC_string_Cstr_copy(pdc, val, "x---------------------------------------------------------", *width);
  }
  return PDC_OK;
}

int main(int argc, char** argv) {
  PDC_t*         pdc;
  test           rep;
  test_ed        ed = {0};
  const char    *fname = FILENAME;

  if (argc == 2) {
    fname = argv[1];
  }

  test_init(pdc, &rep);
  if (PDC_ERR == PDC_open(&pdc,0,0)) {
    error(2, "*** PDC_open failed ***");
    exit(-1);
  }

  pdc->disc->inv_valfn_map = PDC_inv_valfn_map_create(pdc); /* only needed if no map installed yet */ 
#if 1
  PDC_set_inv_valfn(pdc, pdc->disc->inv_valfn_map, "PDC_string", my_string_inv_val);
  PDC_set_inv_valfn(pdc, pdc->disc->inv_valfn_map, "PDC_string_FW", my_string_fw_inv_val);
#endif

  if (strcasecmp(fname, "stdin") == 0) {
    error(0, "Data file = standard in\n");
    if (PDC_ERR == PDC_IO_set(pdc, sfstdin)) {
      error(2, "*** PDC_IO_set(sfstdin) failed ***");
      exit(-1);
    }
  } else {
    error(0, "Data file = %s\n", fname);
    if (PDC_ERR == PDC_IO_fopen(pdc, (char*)fname)) {
      error(2, "*** PDC_IO_fopen failed ***");
      exit(-1);
    }
  }

  /*
   * Try to read each line of data
   */
  while (!PDC_IO_at_EOF(pdc)) {
    error(0, "\ncalling testtwo_read");
    if (PDC_OK == test_read(pdc, 0, &ed, &rep)) {
      /* do something with the data */
      error(2, "test_read returned: s1 %.*s  s2 %.*s", rep.s1.len, rep.s1.str, rep.s2.len, rep.s2.str);
      test_write2io(pdc, sfstdout, &ed, &rep);
    } else {
      error(2, "test_read returned: error");
      test_write2io(pdc, sfstdout, &ed, &rep);
    }
  }
  error(0, "\nFound eof");

  if (PDC_ERR == PDC_IO_close(pdc)) {
    error(2, "*** PDC_IO_close failed ***");
    exit(-1);
  }

  if (PDC_ERR == PDC_close(pdc)) {
    error(2, "*** PDC_close failed ***");
    exit(-1);
  }

  return 0;
}
