#define PADS_TY(suf) dns_msg ## suf

#include "dns.h"


////////////////////////////////////////////////////////////////////////////////
#ifndef EXTRA_READ_ARGS
#  define EXTRA_READ_ARGS
#endif

#ifndef DEF_INPUT_FILE
#  define DEF_INPUT_FILE "/dev/stdin"
#endif


int main(int argc, char** argv) {
  P_t              *pads;
  Pio_disc_t       *my_iodisc;
  Pdisc_t           my_disc = Pdefault_disc;
  PADS_TY()         rep;
  PADS_TY(_pd)      pd;
  PADS_TY(_m)       m;
  PADS_TY(_acc)     acc;
  char             *fileName = 0;

#ifdef WSPACE_OK
  my_disc.flags |= (Pflags_t)P_WSPACE_OK;
#endif

  my_iodisc = P_norec_make(0);
  if (!my_iodisc) {
    error(ERROR_FATAL, "\nFailed to install IO discipline norec");
  } else {
    error(0, "\nInstalled IO discipline norec");
  }
  
  if (argc == 2) {
    fileName = argv[1];
    error(0, "Data file = %s\n", fileName);
  } else {
    fileName = DEF_INPUT_FILE;
    error(0, "Data file = %s\n", DEF_INPUT_FILE);
  }

  if (P_ERR == P_open(&pads, &my_disc, my_iodisc)) {
    error(ERROR_FATAL, "*** P_open failed ***");
  }

  if (P_ERR == P_io_fopen(pads, fileName)) {
    error(ERROR_FATAL, "*** P_io_fopen failed ***");
  }

  if (P_ERR == PADS_TY(_init)(pads, &rep)) {
    error(ERROR_FATAL, "*** representation initialization failed ***");
  }

  if (P_ERR == PADS_TY(_pd_init)(pads, &pd)) {
    error(ERROR_FATAL, "*** parse description initialization failed ***");
  }

  if (P_ERR == PADS_TY(_acc_init)(pads, &acc)) {
    error(ERROR_FATAL, "*** accumulator initialization failed ***");
  }

  /* init mask -- must do this! */
  PADS_TY(_m_init)(pads, &m, P_CheckAndSet);

  /*
   * Try to read each line of data
   */
  while (!P_io_at_eof(pads)) {
    if (P_OK != PADS_TY(_read)(pads, &m, EXTRA_READ_ARGS &pd, &rep)) {
#ifdef EXTRA_BAD_READ_CODE
      EXTRA_BAD_READ_CODE;
#else
      error(2, "read returned error");
#endif
    }
#ifdef EXTRA_GOOD_READ_CODE
    else {
      EXTRA_GOOD_READ_CODE;
    }
#endif
    /* accum both good and bad vals */
    if (P_ERR == PADS_TY(_acc_add)(pads, &acc, &pd, &rep)) {
      error(ERROR_FATAL, "*** accumulator add failed ***");
    }
  }
  if (P_ERR == PADS_TY(_acc_report)(pads, "", 0, 0, &acc)) {
    error(ERROR_FATAL, "** accum_report failed **");
  }

  if (P_ERR == P_io_close(pads)) {
    error(ERROR_FATAL, "*** P_io_close failed ***");
  }

  if (P_ERR == PADS_TY(_cleanup)(pads, &rep)) {
    error(ERROR_FATAL, "** representation cleanup failed **");
  }

  if (P_ERR == PADS_TY(_pd_cleanup)(pads, &pd)) {
    error(ERROR_FATAL, "** parse descriptor cleanup failed **");
  }

  if (P_ERR == PADS_TY(_acc_cleanup)(pads, &acc)) {
    error(ERROR_FATAL, "** accumulator cleanup failed **");
  }

  if (P_ERR == P_close(pads)) {
    error(ERROR_FATAL, "*** P_close failed ***");
  }

  return 0;
}
