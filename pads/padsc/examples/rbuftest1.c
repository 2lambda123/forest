/*
 *  rbuftest1: Test rbufs
 */

#include "libpadsc-internal.h" /* for testing - normally do not include internal */

int main(int argc, char** argv) {
  int             err, i;
  PDC_t*          pdc;
  RMM_t*          rmm_z;
  RMM_t*          rmm_nz;
  RMM_t*          mgr;
  RBuf_t*         rbuf1;
  RBuf_t*         rbuf2;
  void*           buf1;
  void*           buf2;
  void*           buf2b;
  PDC_int32*      ar1;
  PDC_int8*       ar2;
  PDC_disc_t      my_disc = PDC_default_disc;

  if (PDC_ERR == PDC_open(0, &pdc)) {
    error(2, "*** PDC_open failed ***");
    exit(-1);
  }
  rmm_z = PDC_rmm_zero(pdc, 0);
  rmm_nz = PDC_rmm_nozero(pdc, 0);

  if (!(rbuf1 = RMM_new_rbuf(rmm_z))) {
    error(2, "*** RMM_new_rbuf on rmm_z failed ***");
    exit(-1);
  }
  if (!(rbuf2 = RMM_new_rbuf(rmm_nz))) {
    error(2, "*** RMM_new_rbuf on rmm_nz failed ***");
    exit(-1);
  }
  if (err = RBuf_reserve(rbuf1, &buf1, sizeof(PDC_int32), 5, 10)) {
    error(2, "*** rbuf1 reserve failed with err= %d ***", err);
    exit(-1);
  }
  ar1 = (PDC_int32*)buf1;
  if (err = RBuf_reserve(rbuf2, &buf2, sizeof(PDC_int8), 5, 0)) {
    error(2, "*** rbuf2 reserve failed with err= %d ***", err);
    exit(-1);
  }
  ar2 = (PDC_int8*)buf2;


  error(0, "Walking zerod data array");
  for (i = 0; i < 5; i++) {
    error(0, "ar1[%d] = %d", i, ar1[i]);
  }
  error(0, "Walking non-zerod data array");
  for (i = 0; i < 5; i++) {
    error(0, "ar2[%d] = %d", i, ar2[i]);
  }
  error(0, "Growing zerod array from 5 to 20 elts, one increment at a time");
  for (i = 5; i < 20; i++) {
    if (err = RBuf_reserve(rbuf1, &buf1, sizeof(PDC_int32), i+1, 10)) {
      error(2, "*** rbuf1 reserve failed with err= %d ***", err);
      exit(-1);
    }
    ar1 = (PDC_int32*)buf1;
    error(0, "ar1[%d] = %d", i, ar1[i]);
  }
  error(0, "Growing non-zerod array from 5 to 20 elts, one increment at a time");
  for (i = 5; i < 20; i++) {
    if (err = RBuf_reserve(rbuf2, &buf2, sizeof(PDC_int8), i+1, 0)) {
      error(2, "*** rbuf2 reserve failed with err= %d ***", err);
      exit(-1);
    }
    ar2 = (PDC_int8*)buf2;
    error(0, "ar2[%d] = %d", i, ar2[i]);
  }
  error(0, "Calling RMM_free on rbuf1 (should cause 2 mem frees)");
  err = RMM_free_rbuf(rbuf1);
  error(0, "=> RMM_rbuf_free on rbuf1 result: err= %d ***", err);

  error(0, "Calling RMM_free on rbuf1 (should do nothing)");
  err = RMM_free_rbuf(rbuf1);
  error(0, "=> RMM_rbuf_free on rbuf1 result: err= %d ***", err);

  error(0, "Calling RMM_free_keep_buf on rbuf2 (should cause 1 mem free)");
  err = RMM_free_rbuf_keep_buf(rbuf2, &buf2b, &mgr);
  error(0, "=> RMM_rbuf_free_keep_buf on rbuf2 result: err= %d ***", err);
  if (buf2b != buf2) {
    error(2, "*** unexpected: buf2b != buf2");
  }
  if (mgr != rmm_nz) {
    error(2, "*** unexpected: mgr != rmm_nz");
  }

  error(0, "Calling RMM_free_keep_buf on rbuf2 (should do nothing)");
  err = RMM_free_rbuf_keep_buf(rbuf2, 0, 0);
  error(0, "=> RMM_rbuf_free_keep_buf on rbuf2 result: err= %d ***", err);

  error(0, "Calling RMM_free_buf on rbuf2's buffer (should cause 1 mem free)");
  err = RMM_free_buf(mgr, buf2b);
  error(0, "=> RMM_free_buf on rbuf2's buffer result: err= %d ***", err);

  if (PDC_ERR == PDC_close(pdc, &my_disc)) {
    error(2, "*** PDC_close failed ***");
    exit(-1);
  }
  return 0;
}
