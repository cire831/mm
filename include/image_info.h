/*
 * Copyright (c) 2017-2018, 2020 Eric B. Decker
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 * See COPYING in the top level directory of this source tree.
 *
 * Contact: Eric B. Decker <cire831@gmail.com>
 */

#ifndef __IMAGE_INFO_H__
#define __IMAGE_INFO_H__

#define IMAGE_INFO_SIG  0x33275401

/*
 * IMAGE_META_OFFSET is the offset into the image where
 * image_info lives in the image.  It directly follows
 * the exception vectors which are 0x140 bytes long.
 *
 * If the interrupt vector length changes, this value will have to
 * change.
 */
#define IMAGE_META_OFFSET 0x140
#define IMAGE_MIN_BASIC   (IMAGE_META_OFFSET + sizeof(image_info_basic_t))
#define IMAGE_MIN_SIZE    1024
#define IMAGE_MAX_SIZE    (128 * 1024)

typedef struct {                        /* little endian order  */
  uint16_t build;                       /* that's native for us */
  uint8_t  minor;
  uint8_t  major;
} image_ver_t;

typedef struct {
  uint8_t  hw_rev;
  uint8_t  hw_model;
} hw_ver_t;


/*
 * Image description structure
 *
 * fields with 'b' filled in by build process (make)
 * fields with 's' filled in by 'stamp' program after building.
 *
 * image_info_basic is the minimum needs to correctly identify the incoming
 * image when being downloaded.  Still hasn't been verified (we need all
 * the image bytes to do that).  But we need basic information about the
 * version etc to decide that the file coming in is indeed the file being
 * written.
 *
 * NOTE: currently it is really NICE (required?) for the Vector Table and
 * image_info_basic to fit into one sector.  This will be really handy with
 * ImageManagerMap file write.  The requirement is for image_info_basic to
 * be contiguous in one cached sector.  Currently this is the first sector,
 * which includes the VectorTable and image_info_basic.
 *
 * Basic is a static structure with reserved fields for future expansion.
 *
 * Plus is human readable identification that uses TLVs to indicate what is
 * being described.  This allows easy future expansion by defining new TLVs.
 *
 * When a panic occurs, Image_Info is embedded in the panic information that
 * is written out.  The Plus area is sized such that the PanicHdr0 data fits
 * in a 512 byte sector.
 */

#define IMAGE_INFO_PLUS_SIZE 300

enum {
  IIP_TLV_END       = 0,
  IIP_TLV_DESC      = 1,
  IIP_TLV_REPO0     = 2,
  IIP_TLV_URL0      = 3,
  IIP_TLV_REPO1     = 4,
  IIP_TLV_URL1      = 5,
  IIP_TLV_STAMP     = 6,
};

typedef struct {
  uint8_t        type;                  /* IIP_TLV values            */
  uint8_t        len;
  uint8_t        data[];                /* always a printable string */
} image_info_plus_tlv_t;

typedef image_info_plus_tlv_t iip_tlv_t;

typedef struct {
  uint32_t    ii_sig;                   /*  b  must be IMAGE_INFO_SIG to be valid */
  uint32_t    image_start;              /*  b  where this binary loads            */
  uint32_t    image_length;             /*  b  byte length of entire image        */
  image_ver_t ver_id;                   /*  b  version string of this build       */
  uint32_t    image_chk;                /*  s  simple checksum over entire image  */
  hw_ver_t    hw_ver;                   /*  b  2 byte hw_ver                      */
  uint16_t    plus_len;                 /*  b  2 byte plus block size             */
  uint8_t     reserved[8];              /*  b  reserved                           */
} image_info_basic_t;


/*
 * the tlv_block (plus) immediately follows the basic block.  The length of
 * the tlv_block is stored as basic->plus_len.  All tlvs present
 * have to completely fit inside of the tlv_block.
 */

typedef struct {
  uint8_t     tlv_block[IMAGE_INFO_PLUS_SIZE];
} image_info_plus_t;


typedef struct {
  image_info_basic_t iib;
  image_info_plus_t  iip;
} image_info_t;

/*
 * 'binfin' (tools/utils/binfin) is used to fill in the following cells:
 *
 *      o image_chk
 *      o image_desc
 *      o repo0_desc
 *      o url0_desc
 *      o repo1_desc
 *      o url1_desc
 *      o stamp_date
 *
 * image_desc is a general string (null terminated) that can be used to
 * indicate what this image is, released, development, etc.  It is an
 * arbitrary string provided to binfin and placed into image_desc.
 *
 * url{0,1} are descriptor strings identifying the URLs of the repositories.
 *
 * repo{0,1} are descriptor strings that identify the code repositories
 * used to build this image.
 *
 * each descriptor is generated using:
 *
 *      git describe --all --long --dirty
 *
 * SHA information is abbreviated to 7 digits (default).  This should work
 * for both the MamMark as well as the Prod/tinyos-main repositories.  There
 * is enough additional information to enable finding where on the tree this
 * code base was built from.
 *
 * If the descriptor becomes larger than ID_MAX, characters can be removed
 * from the front of the string, typically <name>/ can be removed safely.
 *
 * Descriptors are NUL terminated.  The NUL byte is included in ID_MAX.
 *
 * stamp_date is a NUL terminated string that contains the date (UTC)
 * this image was stamped by binfin.  Typically this will be when the
 * image was built.  stamp_date gets filled in with
 *
 *                  "date -u +%Y/%m/%d-%H:%M:%S".
 *
 * After filling in image_desc, repository{0,1}, and stamp_date, image_chk
 * must be recomputed.  Image_chk starts as zero, and the 32 bit byte by
 * byte checksum is computed then placed into image_chk.
 *
 * To verify the image_chk, first it must be copied out (saved), zeroed,
 * and the checksum computed then compared against the saved value.
 *
 * TLVs in the info_plus area: image_desc, repo_desc{0,1}, url{0,1}, and
 * stamp_date must be filled in prior to computing the value of image_chk.
 */

#endif  /* __IMAGE_INFO_H__ */
