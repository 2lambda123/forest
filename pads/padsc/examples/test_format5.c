#include "libpadsc.h"
#include "format5.h"

int main(int argc, char** argv) {
  PDC_t*          pdc;
  call_em         cem = {PDC_CheckAndSet, PDC_CheckAndSet};
  call_ed         ced;
  call            cdata;

  /* Open pdc handle */
  if (PDC_ERROR == PDC_open(0, &pdc)) {
    error(2, "*** PDC_open failed ***");
    exit(-1);
  }

  /* Open output file */
  if (PDC_ERROR == PDC_IO_fopen(pdc, "../ex_data.format5", 0)) {
    error(2, "*** PDC_IO_fopen failed ***");
    exit(-1);
  }

  /*
   * Try to read each line of data
   */
  while (!PDC_IO_peek_EOF(pdc, 0)) {
    PDC_error_t res;
    int i;
    res= call_read(pdc, &cem, &ced, &cdata, 0);

    if (res == PDC_OK) {
      printf("Record okay:\t");
    } else {
      printf("Record not okay:\t");
    }
    printf("x = %d\t", cdata.x);
    switch (cdata.pn.tag ){
    case code : 
	printf("tagged as code: %d\n",cdata.pn.val.code );
	break;
    case pn :
	printf("tagged as phone number: %d\n", cdata.pn.val.pn);
	break;
    default:
	printf("bogus tag. \n");
	break;      
    }
  }

  if (PDC_ERROR == PDC_IO_fclose(pdc, 0)) {
    error(2, "*** PDC_IO_fclose failed ***");
    exit(-1);
  }

  if (PDC_ERROR == PDC_close(pdc, 0)) {
    error(2, "*** PDC_close failed ***");
    exit(-1);
  }

  return 0;
}
