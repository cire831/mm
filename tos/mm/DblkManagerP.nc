/*
 * Copyright (c) 2018, Miles Maltbie, Eric B. Decker
 * Copyright (c) 2017, Eric B. Decker
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

/*
 * DblkManager.nc - Simple Data Block storage.
 *
 * FileManager will tell us where the Data Area lives (start/end).  The
 * first sector is reserved for the DataManager Directory which is
 * reserved.
 *
 * On boot the DblkManager will keep track of its limits (start/end) and
 * which data block to use next.  On Boot it will use a binary search to
 * find the first empty data block within the Dblk Area.
 */

#include <panic.h>
#include <platform_panic.h>
#include <sd.h>

typedef enum {
  DMS_IDLE = 0,                         /* doing nothing */
  DMS_REQUEST,                          /* resource requested */
  DMS_START,                            /* read first block, chk empty */
  DMS_SCAN,                             /* scanning for 1st blank */
  DMS_LAST_PREV_SYNC,                   /* find last prev sync    */
  DMS_LAST_RECORD_SEARCH,               /* find last used recnum  */
  DMS_MULTI_BLK_RECSUM
} dm_state_t;


#ifndef PANIC_DM
enum {
  __pcode_dm = unique(UQ_PANIC_SUBSYS)
};

#define PANIC_DM __pcode_dm
#endif

#define RESYNC_FAIL 0x666

module DblkManagerP {
  provides {
    interface Boot        as Booted;    /* signals OutBoot */
    interface DblkManager;
  }
  uses {
    interface Boot;                     /* incoming boot signal */
    interface FileSystem;
    interface SDread;
    interface SDraw;
    interface SSWrite as SSW;
    interface Resource as SDResource;
    interface Panic;
  }
}

implementation {

#define DM_SIG 0x55422455

  norace struct {
    uint32_t dm_sig_a;

    /*
     * dblk_lower is where the directory lives.
     * data starts at lower+1 when that sector has been written.
     *
     * file offsets are file relative so the first record in the
     *   first data sector is at file offset 0x200 which lives in
     *   absolute sector (fo / 512) + lower.
     */
    uint32_t dblk_lower;                /* inclusive  */
                                        /* lower is where dir is */
    /* next blk_id to write */
    uint32_t dblk_nxt;                  /* 0 means full          */
    uint32_t dblk_upper;                /* inclusive  */

    /* last record number used */
    uint32_t dm_sig_b;
  } dmc;

  dm_state_t   dm_state;
  uint8_t     *dm_buf;
  uint32_t     lower, cur_blk, upper;
  bool         do_erase = 0;

  /*
   * global persistant variables needed by resync/restart code
   */
  dt_header_t  dt_header;
  int32_t      remaining_bytes;
  uint32_t     resync_blk;
  uint32_t     dblk_count;
  uint32_t     Bytes2BufLimit;
  uint32_t     blk_num;
  uint8_t     *data_ptr;
  uint16_t     partial_checksum;
  uint16_t     multiblk_expected_checksum;
  uint32_t     expected_recnum;

  uint32_t     candidate_recnum;           /* inits to 0 */
  uint32_t     candidate_last_sync_offset; /* inits to 0 */
  datetime_t   candidate_datetime;         /* inits to 0 */

  /* forward references */
  uint32_t get_sync_dblk(dt_sync_t *dt_sync_ptr);
  bool     search_for_last_record(uint32_t i);
  uint32_t search_for_resync();

  void dm_panic(uint8_t where, parg_t p0, parg_t p1) {
    call Panic.panic(PANIC_DM, where, p0, p1, 0, 0);
  }


  event void Boot.booted() {
    error_t err;

#ifdef DBLK_ERASE_ENABLE
    /*
     * FS.erase is split phase and will grab the SD,  We will wait on the
     * erase when we request.  The FS/erase will complete and then we
     * will get the grant.
     */
    nop();                              /* BRK */
    if (do_erase) {
      do_erase = 0;
      call FileSystem.erase(FS_LOC_DBLK);
    }
#endif

    lower = call FileSystem.area_start(FS_LOC_DBLK);
    upper = call FileSystem.area_end(FS_LOC_DBLK);
    if (!lower || !upper || upper < lower) {
      dm_panic(1, lower, upper);
      return;
    }
    dmc.dm_sig_a = dmc.dm_sig_b = DM_SIG;


    /* first sector is dblk directory, reserved */
    dmc.dblk_lower = lower;
    dmc.dblk_nxt   = lower + 1;
    dmc.dblk_upper = upper;
    dm_state = DMS_REQUEST;
    if ((err = call SDResource.request()))
      dm_panic(2, err, 0);
    return;
  }


  event void SDResource.granted() {
    error_t err;

    nop();                              /* BRK */
    if (dm_state != DMS_REQUEST) {
      dm_panic(3, dm_state, 0);
      return;
    }

    dm_state = DMS_START;
    dm_buf = call SSW.get_temp_buf();
    if (!dm_buf) {
      dm_panic(4, (parg_t) dm_buf, 0);
      return;
    }
    if ((err = call SDread.read(dmc.dblk_nxt, dm_buf))) {
      dm_panic(5, err, 0);
      return;
    }
  }


  event void SDread.readDone(uint32_t blk_id, uint8_t *read_buf, error_t err) {
    uint8_t    *dp;
    bool        empty;
    uint32_t i;

    nop();                              /* BRK */
    dp = dm_buf;
    if (err || dp == NULL || dp != read_buf) {
      call Panic.panic(PANIC_DM, 6, err, (parg_t) dp, (parg_t) read_buf, 0);
      return;
    }

    switch(dm_state) {
      default:
        dm_panic(7, dm_state, 0);
        return;

      case DMS_START:
        /*
         * if blk is erased, we use the following:
         *
         * o dmc.dblk_nxt has been already set to dir + 1, correct
         * o candidate_recnum is 0, will be incremented to 1 before use.
         * o candidate_last_sync_offset is 0, no previous SYNC
         * o candidate_datetime is 0, no known datetime.  We want to access
         *   the datetime code to get current datetime if any.
         */
        if (call SDraw.chk_erased(dp))
          break;

        lower = dmc.dblk_nxt;
        upper = dmc.dblk_upper;

        cur_blk = (upper - lower)/2 + lower;
        if (cur_blk == lower)
          cur_blk = lower = upper;

        dm_state = DMS_SCAN;
        if ((err = call SDread.read(cur_blk, dp)))
          dm_panic(8, err, 0);
        return;

      case DMS_SCAN:
        empty = call SDraw.chk_erased(dp);
        if (empty)
          upper = cur_blk;
        else
          lower = cur_blk;

        if (lower >= upper) {
          /*
           * if empty we be good.  Otherwise no available storage.
           */
          if (empty) {
            nop();                              /* BRK */
            dmc.dblk_nxt = cur_blk;
            dblk_count = dmc.dblk_nxt;
            dm_state = DMS_LAST_PREV_SYNC;
            resync_blk = dmc.dblk_nxt - 1;
            if ((err = call SDread.read(resync_blk, dm_buf)))
              dm_panic(7, err, 0);
            return;
          }
          dm_panic(9, (parg_t) cur_blk, 0);
          return;
        }

        /*
         * haven't looked at all the blocks.  try again
         */
        cur_blk = (upper - lower)/2 + lower;
        if (cur_blk == lower)
          cur_blk = lower = upper;
        if ((err = call SDread.read(cur_blk, dp)))
          dm_panic(10, err, 0);
        return;

      case DMS_LAST_PREV_SYNC:
        nop();                              /* BRK */
        i = search_for_resync();
        if (i != RESYNC_FAIL)
          if (search_for_last_record(i))
            break;
        if (i == RESYNC_FAIL && resync_blk == dblk_count) {

          if (resync_blk == dmc.dblk_nxt) {
            resync_blk = dmc.dblk_nxt - 8;
            dblk_count = dmc.dblk_nxt - 1;
          }

          if (resync_blk == dmc.dblk_nxt - 1) {
            dblk_count = dmc.dblk_nxt - 9;
            resync_blk = dmc.dblk_nxt - 16;
          }

          if (resync_blk == dmc.dblk_nxt - 9)
            break;

          if (resync_blk < dmc.dblk_lower)
            break;
          if ((err = call SDread.read(resync_blk, dm_buf)))
            dm_panic(7, err, 0);
          return;
        }
        return;

      case DMS_LAST_RECORD_SEARCH:
        search_for_last_record(0);
        return;

      case DMS_MULTI_BLK_RECSUM:
        data_ptr = dm_buf;

        if(remaining_bytes >= SD_BLOCKSIZE) {
          Bytes2BufLimit = SD_BLOCKSIZE;
          if(remaining_bytes == SD_BLOCKSIZE)
            blk_num = 0;
          else
            blk_num++;
        } else {
          Bytes2BufLimit = remaining_bytes;
          remaining_bytes -= Bytes2BufLimit;
          blk_num = 0;
          if (multiblk_expected_checksum == partial_checksum)
            candidate_recnum = expected_recnum;
          break;
        }
    }

    dm_state = DMS_IDLE;

    /*
     * signal OutBoot first, then release the SD
     *
     * If the next module in the sequenced boot chain wants to
     * use the SD it will issue a request, which will queue them up.
     * Then when we release, it will get the SD without powering the
     * SD down.
     */
    nop();                              /* BRK */
    call Collect.setLastRecNum(candidate_recnum);
    call Collect.setLastSyncOffset(candidate_last_sync_offset);
    signal Booted.booted();
    call SDResource.release();
  }


  bool recsum_valid_p(dt_header_t* record_ptr) {
    uint8_t * data = (uint8_t *)record_ptr;
    uint16_t expected_checksum = (record_ptr->recsum);
    uint16_t checksum = 0;
    uint32_t i;

    record_ptr->recsum = 0;
    for (i = 0; i < (record_ptr->len); i++) {
      checksum += data[i];
    }
    nop();                              /* BRK */
    if(checksum != expected_checksum)
      return FALSE;
    return TRUE;
  }


  void recsum_multi_blk_p() {
    uint8_t * data = (uint8_t *)data_ptr;
    uint16_t checksum = 0;
    uint32_t i;
    error_t err;

    for (i = 0; i < Bytes2BufLimit; i++) {
      checksum += data[i];
    }

    nop();                              /* BRK */
    partial_checksum += checksum;
    if (blk_num) {
      dm_state = DMS_MULTI_BLK_RECSUM;
      if ((err = call SDread.read(blk_num, dm_buf)))
        dm_panic(8, err, 0);
    }
    return;
  }


  uint32_t search_for_resync() {
    uint8_t    *dp = dm_buf;
    uint32_t i;
    dt_sync_t *dt_sync_ptr;
    error_t err;

    for (i = 0; i < 512; i+=4) {
      dt_sync_ptr = (dt_sync_t*)&dp[i];

      if ((dt_sync_ptr->sync_majik == SYNC_MAJIK &&
           dt_sync_ptr->dtype == DT_SYNC &&
           dt_sync_ptr->len == sizeof(dt_sync_t)) ||
          (dt_sync_ptr->sync_majik == SYNC_MAJIK &&
           dt_sync_ptr->dtype == DT_REBOOT &&
           dt_sync_ptr->len == sizeof(dt_dump_reboot_t))) {
        nop();                              /* BRK */
        if (recsum_valid_p((dt_header_t*)dt_sync_ptr)) {
          candidate_recnum = dt_sync_ptr->recnum;

          /* figure out file offset of this sync record */
          candidate_last_sync_offset = 0;

          /* candidate_datetime = 10 byte copy */

          i += dt_sync_ptr->len;
          return i;
        }
      }
    }
    dm_state = DMS_LAST_PREV_SYNC;

    resync_blk++;

    if (resync_blk == dmc.dblk_nxt)
      return RESYNC_FAIL;

    if ((err = call SDread.read(resync_blk, dp)))
      dm_panic(7, err, 0);
    return RESYNC_FAIL;
  }


  bool search_for_last_record(uint32_t i) {
    error_t err = 0;
    uint8_t *dp = dm_buf;
    uint32_t number_sectors_to_advance;
    dt_header_t* record_header = (dt_header_t*)&dp[i];
    dt_header_t* prev_record = 0;

    nop();                              /* BRK */
    while (record_header->dtype > DT_NONE && record_header->dtype <= DT_MAX) {
      if(record_header->len < (SD_BLOCKSIZE - i)) {
        if (recsum_valid_p(record_header)) {
          prev_record = record_header;
          i+=record_header->len;
          record_header = (dt_header_t*)&dp[i];
        }
      } else {
        break;
      }
    }
    if (record_header->dtype <= DT_NONE || record_header->dtype > DT_MAX) {
      nop();                              /* BRK */
      if (prev_record != 0 && recsum_valid_p(prev_record))
        candidate_recnum = prev_record->recnum;
      return FALSE;
    }
    if (record_header->len > (SD_BLOCKSIZE -i)) {
      remaining_bytes = record_header->len - (SD_BLOCKSIZE - i);
      number_sectors_to_advance = remaining_bytes / SD_BLOCKSIZE;
      resync_blk += number_sectors_to_advance + 1;
      if (resync_blk > dmc.dblk_nxt)
        dm_panic(7, err, 0);
      if (resync_blk == dmc.dblk_nxt) {
        Bytes2BufLimit = (record_header->len - remaining_bytes);
        blk_num = resync_blk -= number_sectors_to_advance;
        data_ptr = (uint8_t *)record_header;
        expected_recnum = record_header->recnum;
        multiblk_expected_checksum = (record_header->recsum);
        record_header->recsum = 0;
        recsum_multi_blk_p();
      }
      resync_blk++;
      dm_state = DMS_LAST_RECORD_SEARCH;
      if ((err = call SDread.read(resync_blk, dp)))
        dm_panic(8, err, 0);
      return FALSE;
    }
    resync_blk++;
    dm_state = DMS_LAST_RECORD_SEARCH;
    if ((err = call SDread.read(resync_blk, dp)))
      dm_panic(8, err, 0);
    return TRUE;
  }


  async command uint32_t DblkManager.get_dblk_low() {
    return dmc.dblk_lower;
  }


  async command uint32_t DblkManager.get_dblk_high() {
    return dmc.dblk_upper;
  }


  async command uint32_t DblkManager.get_dblk_nxt() {
    return dmc.dblk_nxt;
  }


  async command uint32_t DblkManager.dblk_nxt_offset() {
    if (dmc.dblk_nxt)
      return (dmc.dblk_nxt - dmc.dblk_lower) << SD_BLOCKSIZE_NBITS;
    return 0;
  }


  async command uint32_t DblkManager.adv_dblk_nxt() {
    atomic {
      if (dmc.dblk_nxt) {
        dmc.dblk_nxt++;
        if (dmc.dblk_nxt > dmc.dblk_upper)
          dmc.dblk_nxt = 0;
      }
    }
    return dmc.dblk_nxt;
  }


  event void FileSystem.eraseDone(uint8_t which) { }


  async event void Panic.hook() { }
}
