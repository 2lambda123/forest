#ifdef _USE_PROTO
#pragma prototyped
#endif
/*
 * PDC io discipline header file
 * 
 * Kathleen Fisher, Robert Gruber
 * AT&T Labs Research
 */

#ifndef __PADSC_H__
#error "Do not include pdc_io_disc.h directly -- include padsc.h instead"
#endif

#ifndef __PDC_IO_DISC_H__
#define __PDC_IO_DISC_H__

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
 *    ctrec and ctrec_noseek
 *    vlrec and vlrec_noseek
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

PDC_IO_disc_t * PDC_fwrec_noseek_make(size_t leader_len, size_t data_len, size_t trailer_len);
/* Instantiates an instance of fwrec_noseek, a version of norec
 * that does not require that the sfio stream is seekable.
 */

PDC_IO_disc_t * PDC_ctrec_make(PDC_byte termChar, size_t block_size_hint);
/* Instantiates an instance of ctrec, a discipline for
 * character-terminated variable-width records. termChar is the
 * character that marks the end of a record. block_size_hint is a
 * hint as to what block size to use, if the discipline chooses to do
 * fixed block-sized reads 'under the covers'.  It may be ignored by
 * the discipline.
 * 
 * For ASCII newline-terminated records use, '\n' or PDC_ASCII_NEWLINE
 * as the term character.  For EBCDIC newline-terminated records, use
 * PDC_EBCDIC_NEWLINE as the term character.
 */

PDC_IO_disc_t * PDC_ctrec_noseek_make(PDC_byte termChar, size_t block_size_hint);
/* Instantiates an instance of ctrec_noseek, a version of norec
 * that does not require that the sfio stream is seekable.
 */

PDC_IO_disc_t * PDC_vlrec_make(int blocked, size_t avg_rlen_hint);
/* Instantiates an instance of vlrec, a discipline for IBM-style
 * variable-length records with record length specified at the start
 * of each record.  If blocked is set (!= 0) then the records are
 * grouped into blocks, where each block has a length given at the
 * start of each block.  avg_rlen_hint is a hint as to what the
 * average record length is, to help the discipline allocate memory.
 * It should include the 4 bytes at the start of each record used for
 * the record length.  It may be ignored by the discipline.
 */

PDC_IO_disc_t * PDC_vlrec_noseek_make(int blocked, size_t avg_rlen_hint);
/* Instantiates an instance of vlrec_noseek, a version of vlrec
 * that does not require that the sfio stream is seekable.
 */

PDC_IO_disc_t * PDC_norec_make(size_t block_size_hint);
/* Instantiates an instance of norec, a raw bytes discipline that
 * does not use records.  block_size_hint is a hint as to what block size
 * to use, if the discipline chooses to do fixed block-sized reads
 * 'under the covers'.  It may be ignored by the discipline.
 */

PDC_IO_disc_t * PDC_norec_noseek_make(size_t block_size_hint);
/* Instantiates an instance of norec_noseek, a version of norec
 * that does not require that the sfio stream is seekable.
 */

/* Shorthands for calling corresponding ctrec make functions with '\n' as termChar: */
#define PDC_nlrec_make(block_size_hint)         PDC_ctrec_make('\n', block_size_hint)
#define PDC_nlrec_noseek_make(block_size_hint)  PDC_ctrec_noseek_make('\n', block_size_hint)

/* PDC_IO_elt_t: used for list of input records managed by the io
 * discipline.  The io discipline maintains a doubly-linked list of
 * these records using the prev/next fields, where the head of the
 * list is always a 'dummy' record that is not used except as a
 * placeholder for managing the list.
 * 
 * XXX_TODOC: begin, end, etc.
 *
 * There are two extra data fields:
 *   disc_ptr, disc_off: (optionally) used by the io discipline;
 *                        ignored by the main library code
 */

/* type PDC_IO_elt_t: */
struct PDC_IO_elt_s {
  PDC_IO_elt_t     *prev;
  PDC_IO_elt_t     *next;
  PDC_byte         *begin;
  PDC_byte         *end;
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
typedef PDC_error_t (*PDC_IO_read_fn)      (PDC_t *pdc, PDC_IO_disc_t* io_disc, PDC_IO_elt_t *io_cur_elt,
					    PDC_IO_elt_t **next_elt_out);
typedef ssize_t     (*PDC_IO_rec_close_fn) (PDC_t *pdc, PDC_IO_disc_t* io_disc, PDC_byte *buf,
					    PDC_byte *rec_start, size_t num_bytes);
typedef ssize_t     (*PDC_IO_blk_close_fn) (PDC_t *pdc, PDC_IO_disc_t* io_disc, PDC_byte *buf,
					    PDC_byte *blk_start, size_t num_bytes, PDC_uint32 num_recs);

/* type PDC_IO_disc_t: */
struct PDC_IO_disc_s {
  /* state */
  const char           *name;          /* short IO discipline name */
  const char           *descr;         /* short IO discipline description */
  int                   rec_based;     /* discipline is record-based? */
  int                   has_rblks;     /* discipline supports blocks of records? */
  size_t                rec_obytes;    /* bytes used for record open marker (0 if not used) */
  size_t                rec_cbytes;    /* bytes used for record close marker (0 if not used) */
  size_t                blk_obytes;    /* bytes used for block open marker (0 if not used) */
  size_t                blk_cbytes;    /* bytes used for block close marker (0 if not used) */
  void                 *data;          /* discipline-specific data */
  /* functions */
  PDC_IO_unmake_fn      unmake_fn;     /* pairs with this discipline's make routine */
  PDC_IO_sfopen_fn      sfopen_fn;     /* Sfio-based open */
  PDC_IO_sfclose_fn     sfclose_fn;    /* Sfio-based close */
  PDC_IO_read_fn        read_fn;       /* read */
  PDC_IO_rec_close_fn   rec_close_fn;  /* fill in record markers for an output record */
  PDC_IO_blk_close_fn   blk_close_fn;  /* fill in block markers for an output block */
};

/* ================================================================================ */

#endif /*  __PDC_IO_DISC_H__  */
