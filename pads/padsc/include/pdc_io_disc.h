#pragma prototyped
/*
 * PDC io discipline header file
 * 
 * Kathleen Fisher, Robert Gruber
 * AT&T Labs Research
 */

#ifndef __PDC_IO_DISC_H__
#define __PDC_IO_DISC_H__

#include "libpadsc.h"

/* ================================================================================ */
/* THE IO DISCIPLINE
 *
 * Type PDC_IO_disc_t is used to control the 'raw' reading of data
 * from a file or from some other data source.  
 *
 * Implementations of the standard IO disciplines can be found in
 * libpadsc/default_io_disc.c.  Anyone planning to implement a new IO
 * discipline should consult default_io_disc.c.
 *
 * From a user standpoint, what is needed is knowledge about how to
 * install different disciplines.  The standard disciplines are
 * installed by making an instance of an IO discipline using one
 * of the following make functions, and then either passing 
 * the resulting handle either to PDC_open or to PDC_set_IO_disc.
 *
 * Note that there are two versions of each kind of IO discipline:
 *    fwrec and fwrec_noseek
 *    nlrec and nlrec_noseek
 *    norec and norec_noseek
 * The noseek versions do not require that the sfio stream
 * be seekable, while the other versions do.  
 */

PDC_IO_disc_t * PDC_fwrec_make(size_t leader_len, size_t data_len, size_t trailer_len);
/* Instantiates an instance of fwrec, a discipline for fixed-width
 * records.  data_len specifies the number of data bytes per record,
 * while leader_len and trailer_len specifies the number of bytes that
 * occur before and after the data bytes within each record (either or
 * both can be zero).  Thus the total record size in bytes is the sum
 * of the 3 arguments.  
 */

PDC_IO_disc_t * PDC_nlrec_make(size_t block_size_hint);
/* Instantiates an instance of nlrec, a discipline for
 * newline-terminated variable-width records.  block_size_hint is a
 * hint as to what block size to use, if the discipline chooses to do
 * fixed block-sized reads 'under the covers'.  It may be ignored by
 * the discipline.
 */

PDC_IO_disc_t * PDC_norec_make(size_t block_size_hint);
/* Instantiates an instance of norec, a raw bytes discipline that
 * does not use EOR.  block_size_hint is a hint as to what block size
 * to use, if the discipline chooses to do fixed block-sized reads
 * 'under the covers'.  It may be ignored by the discipline.
 */

PDC_IO_disc_t * PDC_fwrec_noseek_make(size_t leader_len, size_t data_len, size_t trailer_len);
/* Instantiates an instance of fwrec_noseek, a version of norec
 * that does not require that the sfio stream is seekable.
 */

PDC_IO_disc_t * PDC_nlrec_noseek_make(size_t block_size_hint);
/* Instantiates an instance of nlrec_noseek, a version of norec
 * that does not require that the sfio stream is seekable.
 */

PDC_IO_disc_t * PDC_norec_noseek_make(size_t block_size_hint);
/* Instantiates an instance of norec_noseek, a version of norec
 * that does not require that the sfio stream is seekable.
 */

/* PDC_IO_elt_t: used for list of input records managed by the io discipline.
 * The io discipline maintains a doubly-linked list of these records using the
 * prev/next fields, where the head of the list is always a 'dummy' record
 * that is not used except as a placeholder for managing the list.
 *
 * There are two extra data fields:
 *   disc_ptr, disc_off: (optionally) used by the io discipline;
 *                        ignored by the main library code
 */

/* type PDC_IO_elt_t: */
struct PDC_IO_elt_s {
  PDC_IO_elt_t     *prev;
  PDC_IO_elt_t     *next;
  char             *begin;
  char             *end;
  size_t           len;
  int              eor;
  int              eof;
  size_t           num;
  const char       *unit;
  void             *disc_ptr;
  Sfoff_t          disc_off;
};

/* Function types needed for the IO discipline: */

typedef PDC_error_t (*PDC_IO_unmake_fn)    (PDC_t *pdc, PDC_IO_disc_t* io_disc);
typedef PDC_error_t (*PDC_IO_sfopen_fn)    (PDC_t *pdc, PDC_IO_disc_t* io_disc, Sfio_t *sfio, PDC_IO_elt_t *head);
typedef PDC_error_t (*PDC_IO_sfclose_fn)   (PDC_t *pdc, PDC_IO_disc_t* io_disc, PDC_IO_elt_t *io_cur_elt, size_t remain);
typedef PDC_error_t (*PDC_IO_read_fn)      (PDC_t *pdc, PDC_IO_disc_t* io_disc, PDC_IO_elt_t *io_cur_elt, size_t remain,
					    PDC_IO_elt_t **next_elt_out);

/* type PDC_IO_disc_t: */
struct PDC_IO_disc_s {
  /* state */
  const char          *name;       /* short IO discipline name */
  const char          *descr;      /* short IO discipline description */
  int                 uses_eor;    /* discipline uses EOR? */
  void                *data;       /* discipline-specific data */
  /* functions */
  PDC_IO_unmake_fn    unmake_fn;   /* pairs with this discipline's make routine */
  PDC_IO_sfopen_fn    sfopen_fn;   /* Sfio-based open */
  PDC_IO_sfclose_fn   sfclose_fn;  /* Sfio-based close */
  PDC_IO_read_fn      read_fn;     /* read */
};

/* ================================================================================ */
/* Helper macros */

#define PDC_SOME_ELTS(head) (head->next != head)
#define PDC_FIRST_ELT(head) (head->next)
#define PDC_LAST_ELT(head)  (head->prev)

#define PDC_REMOVE_ELT(elt) do { \
  PDC_IO_elt_t *tmp = (elt); \
  tmp->prev->next = tmp->next; \
  tmp->next->prev = tmp->prev; \
} while (0)

#define PDC_APPEND_ELT(head, elt) do { \
  PDC_IO_elt_t *tmp = (elt); \
  tmp->prev = head->prev; \
  tmp->next = head; \
  tmp->prev->next = tmp; \
  tmp->next->prev = tmp; \
} while (0)

#define PDC_PREPEND_ELT(head, elt) do { \
  PDC_IO_elt_t *tmp = (elt); \
  tmp->prev = head; \
  tmp->next = head->next; \
  tmp->prev->next = tmp; \
  tmp->next->prev = tmp; \
} while (0)

/* ================================================================================ */

#endif /*  __PDC_IO_DISC_H__  */
