#ifdef _USE_PROTO
#pragma prototyped
#endif

/*
 * Kathleen Fisher, Robert Gruber
 * AT&T Labs Research
 */

#ifndef __PEBC_INT_H__
#define __PEBC_INT_H__

#ifndef __PADS_H__
#error Pebc_int.h is intended to be included from pads.h, do not include it directly
#endif

/* ================================================================================
 * READ
 */

/* ================================================================================
 * EBC, BCD, and SBL, and SBH ENCODINGS OF INTEGERS
 *   (VARIABLE NUMBER OF DIGITS/BYTES)
 *
 * These functions parse signed or unsigned EBCDIC numeric (ebc_), BCD (bcd_),
 * SBL (sbl_) or SBH (sbh_) encoded integers with a specified number of digits
 * (for ebc_ and bcd_) or number of bytes (for sbl_ and sbh_).
 *
 * EBC INTEGER ENCODING (Pebc_int64_read / Pebc_uint64_read):
 *
 *   Each byte on disk encodes one digit (in low 4 bits).  For signed
 *   values, the final byte encodes the sign (high 4 bits == 0xD for negative).
 *   A signed or unsigned 5 digit value is encoded in 5 bytes.
 *
 * BCD INTEGER ENCODING (Pbcd_int_read / Pbcd_uint_read):
 *
 *   Each byte on disk encodes two digits, 4 bits per digit.  For signed
 *   values, a negative number is encoded by having number of digits be odd
 *   so that the remaining low 4 bits in the last byte are available for the sign.
 *   (low 4 bits == 0xD for negative).
 *   A signed or unsigned 5 digit value is encoded in 3 bytes, where the unsigned
 *   value ignores the final 4 bits and the signed value uses them to get the sign.
 *
 * SBL (Serialized Binary, Low-Order Byte First) INTEGER ENCODING
 *   (Psbl_int_read / Psbl_uint_read):
 *
 *   For a K-byte SBL encoding, the first byte on disk is treated 
 *   as the low order byte of a K byte value.
 *
 * SBH (Serialized Binary, High-Order Byte First) INTEGER ENCODING
 *   (Psbh_int_read / Psbh_uint_read):
 *
 *   For a K-byte SBH encoding, the first byte on disk is treated 
 *   as the high order byte of a K byte value.
 * 
 * For SBL and SBH, each byte is moved to the in-memory target integer unchanged.
 * Whether the result is treated as a signed or unsigned number depends on the target type.
 *
 * Note that SBL and SBH differ from the COMMON WIDTH BINARY (B) read functions above
 * in 3 ways: (1) SBL and SBH support any number of bytes between 1 and 8,
 * while B only supports 1, 2, 4, and 8; (2) with SBL and SBH you specify the target
 * type independently of the num_bytes; (3) SBL and SBH explicitly state the
 * byte ordering, while B uses the pads->disc->d_endian setting to determine the
 * byte ordering of the data.
 *
 * FOR ALL TYPES
 * =============
 *
 * The legal range of values for num_digits (for EBC/BCD) or num_bytes (for SB)
 * depends on target type:
 *    
 * Type        num_digits    num_bytes Min/Max values
 * ----------- ----------    --------- ----------------------------
 * Pint8       1-3           1-1       P_MIN_INT8  / P_MAX_INT8
 * Puint8      1-3           1-1       0           / P_MAX_UINT8
 * Pint16      1-5           1-2       P_MIN_INT16 / P_MAX_INT16
 * Puint16     1-5           1-2       0           / P_MAX_UINT16
 * Pint32      1-10/11**     1-4       P_MIN_INT32 / P_MAX_INT32
 * Puint32     1-10          1-4       0           / P_MAX_UINT32
 * Pint64      1-19          1-8       P_MIN_INT64 / P_MAX_INT64
 * Puint64     1-20          1-8       0           / P_MAX_UINT64
 * 
 * N.B.: num_digits must be odd if the value on disk can be negative.
 *
 * ** For Pbcd_int32_read only, even though the min and max int32 have 10 digits, we allow
 * num_digits == 11 due to the fact that 11 is required for a 10 digit negative value
 * (an actual 11 digit number would cause a range error, so the leading digit must be 0).
 * 
 * For all cases, if the specified number of bytes is NOT available:
 *    + pd->loc.b/e set to elt/char position of start/end of the 'too small' field
 *    + IO cursor is not advanced
 *    + if P_Test_NotIgnore(*m), pd->errCode set to P_WIDTH_NOT_AVAILABLE,
 *         pd->nerr set to 1, and an error is reported
 *
 * Otherwise, the IO cursor is always advanced.  There are 3 error cases that
 * can occur even though the IO cursor advances:
 *
 * If num_digits or num_bytes is not a legal choice for the target type and
 * sign of the value:
 *    + pd->loc.b/e set to elt/char position at the start/end of the field
 *    + if P_Test_NotIgnore(*m), pd->errCode set to P_BAD_PARAM,
 *         pd->nerr set to 1, and an error is reported
 *
 * If the specified bytes make up an integer that does not fit in the target type,
 * or if the actual value is not in the min/max range, then:
 *    + pd->loc.b/e set to elt/char position at the start/end of the field
 *    + if P_Test_NotIgnore(*m), pd->errCode set to P_RANGE,
 *         pd->nerr set to 1, and an error is reported
 *
 * If the specified bytes are not legal EBC/BCD integer bytes, then 
 *    + pd->loc.b/e set to elt/char position at the start/end of the field
 *    + if P_Test_NotIgnore(*m), pd->errCode set to P_INVALID_EBC_NUM or P_INVALID_BCD_NUM,
 *         pd->nerr set to 1, and an error is reported
 */

#if P_CONFIG_READ_FUNCTIONS > 0
#if P_CONFIG_EBC_INT > 0  || P_CONFIG_EBC_FPOINT > 0
Perror_t Pebc_int8_read   (P_t *pads, const Pbase_m *m,
			   Pbase_pd *pd, Pint8 *res_out, Puint32 num_digits);
Perror_t Pebc_int16_read  (P_t *pads, const Pbase_m *m,
			   Pbase_pd *pd, Pint16 *res_out, Puint32 num_digits);
Perror_t Pebc_int32_read  (P_t *pads, const Pbase_m *m,
			   Pbase_pd *pd, Pint32 *res_out, Puint32 num_digits);
Perror_t Pebc_int64_read  (P_t *pads, const Pbase_m *m,
			   Pbase_pd *pd, Pint64 *res_out, Puint32 num_digits);

Perror_t Pebc_uint8_read  (P_t *pads, const Pbase_m *m,
			   Pbase_pd *pd, Puint8 *res_out, Puint32 num_digits);
Perror_t Pebc_uint16_read (P_t *pads, const Pbase_m *m,
			   Pbase_pd *pd, Puint16 *res_out, Puint32 num_digits);
Perror_t Pebc_uint32_read (P_t *pads, const Pbase_m *m,
			   Pbase_pd *pd, Puint32 *res_out, Puint32 num_digits);
Perror_t Pebc_uint64_read (P_t *pads, const Pbase_m *m,
			   Pbase_pd *pd, Puint64 *res_out, Puint32 num_digits);
#endif
#endif

/* ================================================================================
 * WRITE
 */

#if P_CONFIG_WRITE_FUNCTIONS > 0
#if P_CONFIG_EBC_INT > 0 || P_CONFIG_EBC_FPOINT > 0
ssize_t Pebc_int8_write2io  (P_t *pads, Sfio_t *io, Pbase_pd *pd, Pint8   *val, Puint32 num_digits);
ssize_t Pebc_int16_write2io (P_t *pads, Sfio_t *io, Pbase_pd *pd, Pint16  *val, Puint32 num_digits);
ssize_t Pebc_int32_write2io (P_t *pads, Sfio_t *io, Pbase_pd *pd, Pint32  *val, Puint32 num_digits);
ssize_t Pebc_int64_write2io (P_t *pads, Sfio_t *io, Pbase_pd *pd, Pint64  *val, Puint32 num_digits);
						  			                          
ssize_t Pebc_uint8_write2io (P_t *pads, Sfio_t *io, Pbase_pd *pd, Puint8  *val, Puint32 num_digits);
ssize_t Pebc_uint16_write2io(P_t *pads, Sfio_t *io, Pbase_pd *pd, Puint16 *val, Puint32 num_digits);
ssize_t Pebc_uint32_write2io(P_t *pads, Sfio_t *io, Pbase_pd *pd, Puint32 *val, Puint32 num_digits);
ssize_t Pebc_uint64_write2io(P_t *pads, Sfio_t *io, Pbase_pd *pd, Puint64 *val, Puint32 num_digits);

ssize_t Pebc_int8_write_xml_2io  (P_t *pads, Sfio_t *io, Pbase_pd *pd, Pint8   *val, const char *tag, int indent, Puint32 num_digits);
ssize_t Pebc_int16_write_xml_2io (P_t *pads, Sfio_t *io, Pbase_pd *pd, Pint16  *val, const char *tag, int indent, Puint32 num_digits);
ssize_t Pebc_int32_write_xml_2io (P_t *pads, Sfio_t *io, Pbase_pd *pd, Pint32  *val, const char *tag, int indent, Puint32 num_digits);
ssize_t Pebc_int64_write_xml_2io (P_t *pads, Sfio_t *io, Pbase_pd *pd, Pint64  *val, const char *tag, int indent, Puint32 num_digits);
						       								                    
ssize_t Pebc_uint8_write_xml_2io (P_t *pads, Sfio_t *io, Pbase_pd *pd, Puint8  *val, const char *tag, int indent, Puint32 num_digits);
ssize_t Pebc_uint16_write_xml_2io(P_t *pads, Sfio_t *io, Pbase_pd *pd, Puint16 *val, const char *tag, int indent, Puint32 num_digits);
ssize_t Pebc_uint32_write_xml_2io(P_t *pads, Sfio_t *io, Pbase_pd *pd, Puint32 *val, const char *tag, int indent, Puint32 num_digits);
ssize_t Pebc_uint64_write_xml_2io(P_t *pads, Sfio_t *io, Pbase_pd *pd, Puint64 *val, const char *tag, int indent, Puint32 num_digits);

ssize_t Pebc_int8_write2buf  (P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, Pbase_pd *pd, Pint8   *val, Puint32 num_digits);
ssize_t Pebc_int16_write2buf (P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, Pbase_pd *pd, Pint16  *val, Puint32 num_digits);
ssize_t Pebc_int32_write2buf (P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, Pbase_pd *pd, Pint32  *val, Puint32 num_digits);
ssize_t Pebc_int64_write2buf (P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, Pbase_pd *pd, Pint64  *val, Puint32 num_digits);

ssize_t Pebc_uint8_write2buf (P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, Pbase_pd *pd, Puint8  *val, Puint32 num_digits);
ssize_t Pebc_uint16_write2buf(P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, Pbase_pd *pd, Puint16 *val, Puint32 num_digits);
ssize_t Pebc_uint32_write2buf(P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, Pbase_pd *pd, Puint32 *val, Puint32 num_digits);
ssize_t Pebc_uint64_write2buf(P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, Pbase_pd *pd, Puint64 *val, Puint32 num_digits);

ssize_t Pebc_int8_write_xml_2buf  (P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, Pbase_pd *pd, Pint8   *val, const char *tag, int indent, Puint32 num_digits);
ssize_t Pebc_int16_write_xml_2buf (P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, Pbase_pd *pd, Pint16  *val, const char *tag, int indent, Puint32 num_digits);
ssize_t Pebc_int32_write_xml_2buf (P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, Pbase_pd *pd, Pint32  *val, const char *tag, int indent, Puint32 num_digits);
ssize_t Pebc_int64_write_xml_2buf (P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, Pbase_pd *pd, Pint64  *val, const char *tag, int indent, Puint32 num_digits);
										          									  
ssize_t Pebc_uint8_write_xml_2buf (P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, Pbase_pd *pd, Puint8  *val, const char *tag, int indent, Puint32 num_digits);
ssize_t Pebc_uint16_write_xml_2buf(P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, Pbase_pd *pd, Puint16 *val, const char *tag, int indent, Puint32 num_digits);
ssize_t Pebc_uint32_write_xml_2buf(P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, Pbase_pd *pd, Puint32 *val, const char *tag, int indent, Puint32 num_digits);
ssize_t Pebc_uint64_write_xml_2buf(P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, Pbase_pd *pd, Puint64 *val, const char *tag, int indent, Puint32 num_digits);

ssize_t Pebc_int8_fmt2buf  (P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, int *requested_out, const char *delims,
			       Pbase_m *m, Pbase_pd *pd, Pint8  *rep, Puint32 num_digits);
ssize_t Pebc_int8_fmt2buf_final  (P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, int *requested_out, const char *delims,
				  Pbase_m *m, Pbase_pd *pd, Pint8  *rep, Puint32 num_digits);
ssize_t Pebc_int16_fmt2buf (P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, int *requested_out, const char *delims,
			       Pbase_m *m, Pbase_pd *pd, Pint16 *rep, Puint32 num_digits);
ssize_t Pebc_int16_fmt2buf_final (P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, int *requested_out, const char *delims,
				  Pbase_m *m, Pbase_pd *pd, Pint16 *rep, Puint32 num_digits);
ssize_t Pebc_int32_fmt2buf (P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, int *requested_out, const char *delims,
			       Pbase_m *m, Pbase_pd *pd, Pint32 *rep, Puint32 num_digits);
ssize_t Pebc_int32_fmt2buf_final (P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, int *requested_out, const char *delims,
				  Pbase_m *m, Pbase_pd *pd, Pint32 *rep, Puint32 num_digits);
ssize_t Pebc_int64_fmt2buf (P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, int *requested_out, const char *delims,
			       Pbase_m *m, Pbase_pd *pd, Pint64 *rep, Puint32 num_digits);
ssize_t Pebc_int64_fmt2buf_final (P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, int *requested_out, const char *delims,
				  Pbase_m *m, Pbase_pd *pd, Pint64 *rep, Puint32 num_digits);

ssize_t Pebc_uint8_fmt2buf (P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, int *requested_out, const char *delims,
			       Pbase_m *m, Pbase_pd *pd, Puint8  *rep, Puint32 num_digits);
ssize_t Pebc_uint8_fmt2buf_final (P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, int *requested_out, const char *delims,
				  Pbase_m *m, Pbase_pd *pd, Puint8  *rep, Puint32 num_digits);
ssize_t Pebc_uint16_fmt2buf(P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, int *requested_out, const char *delims,
			       Pbase_m *m, Pbase_pd *pd, Puint16 *rep, Puint32 num_digits);
ssize_t Pebc_uint16_fmt2buf_final(P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, int *requested_out, const char *delims,
				  Pbase_m *m, Pbase_pd *pd, Puint16 *rep, Puint32 num_digits);
ssize_t Pebc_uint32_fmt2buf(P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, int *requested_out, const char *delims,
			       Pbase_m *m, Pbase_pd *pd, Puint32 *rep, Puint32 num_digits);
ssize_t Pebc_uint32_fmt2buf_final(P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, int *requested_out, const char *delims,
				  Pbase_m *m, Pbase_pd *pd, Puint32 *rep, Puint32 num_digits);
ssize_t Pebc_uint64_fmt2buf(P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, int *requested_out, const char *delims,
			       Pbase_m *m, Pbase_pd *pd, Puint64 *rep, Puint32 num_digits);
ssize_t Pebc_uint64_fmt2buf_final(P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, int *requested_out, const char *delims,
				  Pbase_m *m, Pbase_pd *pd, Puint64 *rep, Puint32 num_digits);

ssize_t Pebc_int8_fmt2io   (P_t *pads, Sfio_t *io, int *requested_out, const char *delims,
			       Pbase_m *m, Pbase_pd *pd, Pint8  *rep, Puint32 num_digits);
ssize_t Pebc_int16_fmt2io  (P_t *pads, Sfio_t *io, int *requested_out, const char *delims,
			       Pbase_m *m, Pbase_pd *pd, Pint16 *rep, Puint32 num_digits);
ssize_t Pebc_int32_fmt2io  (P_t *pads, Sfio_t *io, int *requested_out, const char *delims,
			       Pbase_m *m, Pbase_pd *pd, Pint32 *rep, Puint32 num_digits);
ssize_t Pebc_int64_fmt2io  (P_t *pads, Sfio_t *io, int *requested_out, const char *delims,
			       Pbase_m *m, Pbase_pd *pd, Pint64 *rep, Puint32 num_digits);

ssize_t Pebc_uint8_fmt2io  (P_t *pads, Sfio_t *io, int *requested_out, const char *delims,
			       Pbase_m *m, Pbase_pd *pd, Puint8  *rep, Puint32 num_digits);
ssize_t Pebc_uint16_fmt2io (P_t *pads, Sfio_t *io, int *requested_out, const char *delims,
			       Pbase_m *m, Pbase_pd *pd, Puint16 *rep, Puint32 num_digits);
ssize_t Pebc_uint32_fmt2io (P_t *pads, Sfio_t *io, int *requested_out, const char *delims,
			       Pbase_m *m, Pbase_pd *pd, Puint32 *rep, Puint32 num_digits);
ssize_t Pebc_uint64_fmt2io (P_t *pads, Sfio_t *io, int *requested_out, const char *delims,
			       Pbase_m *m, Pbase_pd *pd, Puint64 *rep, Puint32 num_digits);
#endif
#endif  /*  P_CONFIG_WRITE_FUNCTIONS > 0  */

#endif /*  __PEBC_INT_H__  */

