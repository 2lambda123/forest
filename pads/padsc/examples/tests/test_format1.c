#include "libpadsc.h"
#include "format1.h"

/* XXX_REMOVE NEXT 2 LINES: */
#include "libpadsc-internal.h"
#define test_m_init(pdc, mask_ptr, base_mask) PDCI_fill_mask((PDC_base_m*)mask_ptr, base_mask, sizeof(*(mask_ptr)))

int main(int argc, char** argv) {
  PDC_t*          pdc;
  PDC_disc_t      mydisc = PDC_default_disc;
  test            f1data;
  test_acc        accum;
  test_ed         ed = {0};
  test_m          m;

  mydisc.flags |= PDC_WSPACE_OK;

  if (PDC_ERR == PDC_open(&pdc,&mydisc,0)) {
    error(2, "*** PDC_open failed ***");
    exit(-1);
  }
  if (PDC_ERR == PDC_IO_fopen(pdc, "../../data/ex_data.format1")) {
    error(2, "*** PDC_IO_fopen failed ***");
    exit(-1);
  }

  /* init mask -- must do this! */
  test_m_init(pdc, &m, PDC_CheckAndSet);

  error(0, "\ninit the accum");
  if (PDC_ERR == test_acc_init(pdc, &accum)) {
    error(2, "** init failed **");
    exit(-1);
  }

  /*
   * Try to read each line of data
   */
  while (!PDC_IO_at_EOF(pdc)) {
    error(0, "\ncalling test_read");
    if (PDC_OK == test_read(pdc, &m, &ed, &f1data)) {
      /* do something with the data */
      error(2, "test_read returned: id %d  ts %d", f1data.id, f1data.ts);
      if (PDC_ERR == test_acc_add(pdc, &accum, &ed, &f1data)) {
	error(0, "** accum_add failed **");
      }
    } else {
      error(2, "test_read returned: error");
      if (PDC_ERR == test_acc_add(pdc, &accum, &ed, &f1data)) {
	error(0, "** accum_add failed **");
      }
    }
  }
  error(0, "\nFound eof");

  if (PDC_ERR == test_acc_report(pdc, "entire struct", 0, 0, &accum)) {
    error(0, "** accum_report failed **");
  }

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
