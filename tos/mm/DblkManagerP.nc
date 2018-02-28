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

  /*
   * SYNC searching is different from LAST RECORD search because
   * the syncs are marshalled (small enough) while RECORDS are large.
   * internal sync search state is handled by search_for_sync.
   */
  DMS_LAST_PREV_SYNC,                   /* find last prev sync    */
  DMS_LAST_RECORD_SEARCH,               /* find last used recnum  */
  DMS_MULTI_BLK_RECSUM
} dm_state_t;


typedef enum {
  DMR_IDLE = 0,                         /* doing nothing */
  DMR_1_SECTOR,                         /* last 1 sector search */
  DMR_8_SECTOR,                         /* last 8 sectors search */
  DMR_16_SECTOR,                        /* last 16 sectors search */
  DMR_FAIL,                             /* no records found */
} dm_restart_t;


typedef enum {
  SFS_NONE                 = 0,
  SFS_OUT_OF_DATA,

  SFS_CORRUPT_SYNC,
  SFS_SYNC_RECORD_NOTFOUND,

  SFS_VALID_SYNC,
} search_for_sync_t;


#ifndef PANIC_DM
enum {
  __pcode_dm = unique(UQ_PANIC_SUBSYS)
};

#define PANIC_DM __pcode_dm
#endif

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
    interface Collect;
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

    uint32_t dm_sig_b;
  } dmc;

  dm_restart_t restart_state;
  dm_state_t   dm_state;
  uint8_t     *dm_buf;
  uint32_t     lower, cur_blk, upper;
  bool         do_erase = 0;
  uint32_t     cur_working_idx;

  /*
   * global persistant variables needed by resync/restart code
   */
  uint8_t      dt_header_copy[sizeof(dt_dump_reboot_t)] __attribute__ ((aligned (4)));
  int32_t      remaining_bytes;
  uint32_t     resync_blk;                /* inits to 0 */
  uint32_t     resync_limit;
  uint32_t     Bytes2BufLimit;
  uint32_t     blk_num;
  uint8_t     *data_ptr;
  uint16_t     partial_checksum;
  uint16_t     multiblk_expected_checksum;
  uint32_t     expected_recnum;

  /* control cells for sync search and sync's that span a blk boundary */
  /* see search_for_sync for details */
  uint32_t     sync_copy_remaining;
  uint32_t     sync_copy_len;

  uint32_t     candidate_recnum;           /* inits to 0 */
  uint32_t     candidate_last_sync_offset; /* inits to 0 */
  datetime_t   candidate_datetime;         /* inits to 0 */
  bool record_found;

  /* forward references */
  uint32_t          get_sync_dblk(dt_sync_t *dt_sync_ptr);
  bool              search_for_last_record();
  search_for_sync_t search_for_sync();
  bool              next_scan_sector();
  void              recsum_multi_blk_p();
  bool              validate_sync();


  void dm_panic(uint8_t where, parg_t p0, parg_t p1) {
    call Panic.panic(PANIC_DM, where, p0, p1, 0, 0);
  }


  /*
   * Initialize for last_sync/last_rec scanning.  Start with the very
   * last sector.  Most likely it will have a SYNC if a system flush
   * was done.
   */
  void init_sync_scan() {
    dmc.dblk_nxt = cur_blk;
    resync_limit = dmc.dblk_nxt;
    restart_state = DMR_1_SECTOR;
    resync_blk = dmc.dblk_nxt - 1;
    record_found = FALSE;
  }


  event void Boot.booted() {
    error_t err;

#ifdef DBLK_ERASE_ENABLE
    /*
     * FS.erase is split phase and will grab the SD,  We will wait on the
     * erase when we request.  The FS/erase will complete and then we
     * will get the grant.
     */
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
    if ((err = call SDread.read(dmc.dblk_nxt, dm_buf)))
      dm_panic(5, err, 0);
  }


  event void SDread.readDone(uint32_t blk_id, uint8_t *read_buf, error_t err) {
    uint8_t    *dp;
    bool        empty;
    uint32_t   sync_state;

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
            /*
             * Initially, go back one sector before read,
             * to check for sync/reboot record
             */

            /* search last sector for sync/reboot record */
            init_sync_scan();
            dm_state = DMS_LAST_PREV_SYNC;
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
        /*
         * Initialization of cur_working_idx. Sync offset is a mirror of buf_offset.
         * Used for keeping track of index position while searching for syncs.
         */

        /*
         * Sector number of ((resync_block - dblk_low) * 512) + sync offset = file position
         */
        if (cur_working_idx == 0) {
          nop();                              /* BRK */
          sync_state = search_for_sync();
        }
        /*
         * when sync record is found,
         * search for last data record.
         */

        if (sync_state != SFS_SYNC_RECORD_NOTFOUND) {
          if (resync_blk == resync_limit) {
            nop();                              /* BRK */
            dm_state = DMS_LAST_RECORD_SEARCH;
            if(!search_for_last_record())
              break;
          } else {
            sync_state = search_for_sync();
          }
        }

        /*
         * resync_limit keeps track of which sectors have been read.
         * makes sure the same sector is not read twice.
         */
        if (sync_state == SFS_SYNC_RECORD_NOTFOUND) {
          nop();
          nop();
          nop();                              /* BRK */
          if (resync_blk == resync_limit) {
            if(record_found == TRUE) {
              nop();
              nop();
              nop();                              /* BRK */
              dm_state = DMS_LAST_RECORD_SEARCH;
              if(!search_for_last_record())
                break;
            } else {
              /*
               * Routine to search previous sectors for sync/reboot record.
               * Program keeps track of which sectors have been read,
               * Checks previous 8 sectors first, then 16 sectors back.
               */
              nop();
              nop();
              nop();                              /* BRK */
              next_scan_sector();

              if (resync_blk == 0) {
                cur_working_idx = 0;
                break;
              }
            }
          } else {
            sync_state = search_for_sync();
          }
        }
        if ((err = call SDread.read(resync_blk, dm_buf)))
          dm_panic(7, err, 0);
        return;

      case DMS_LAST_RECORD_SEARCH:
        nop();
        nop();
        nop();                              /* BRK */
        if(!search_for_last_record())
          break;

        if ((err = call SDread.read(resync_blk, dm_buf)))
          dm_panic(7, err, 0);
        return;

      case DMS_MULTI_BLK_RECSUM:
        data_ptr = dm_buf;

        recsum_multi_blk_p();

        if(remaining_bytes >= SD_BLOCKSIZE) {
          nop();
          nop();
          nop();                              /* BRK */
          Bytes2BufLimit = SD_BLOCKSIZE;
          if(remaining_bytes == SD_BLOCKSIZE)
            blk_num = 0;
          else
            blk_num++;
        } else {
          nop();
          nop();
          nop();                              /* BRK */
          Bytes2BufLimit = remaining_bytes;
          remaining_bytes -= Bytes2BufLimit;
          blk_num = 0;
          if (multiblk_expected_checksum == partial_checksum)
            candidate_recnum = expected_recnum;
          break;
        }

        if (blk_num) {
          nop();
          nop();
          nop();                              /* BRK */
          if ((err = call SDread.read(blk_num, dm_buf)))
            dm_panic(8, err, 0);
        } else {
          break;
        }
        return;
    }


    nop();
    nop();
    nop();                              /* BRK */
    dm_state = DMS_IDLE;

    /*
     * signal OutBoot first, then release the SD
     *
     * If the next module in the sequenced boot chain wants to
     * use the SD it will issue a request, which will queue them up.
     * Then when we release, it will get the SD without powering the
     * SD down.
     */
    call Collect.setLastRecnum(candidate_recnum);
    call Collect.setLastSyncOffset(candidate_last_sync_offset);
    signal Booted.booted();
    call SDResource.release();
  }


  /*
   * next_scan_sector drives the search for sync/reboot records.
   * It scans the last 8 sectors first, then 16 sectors if none are found.
   */
  bool next_scan_sector() {
    error_t err = 0;
    nop();
    nop();
    nop();                              /* BRK */

    if (restart_state == DMR_1_SECTOR)
      restart_state = DMR_8_SECTOR;

    /*
     * If no sync record found in last sector, go back and search last 8
     * sectors
     */
    if (restart_state == DMR_8_SECTOR && resync_blk == dmc.dblk_nxt) {
      if (dmc.dblk_nxt - 8 < dmc.dblk_lower) {
        resync_blk = 0;
        return FALSE;
      }

      restart_state = DMR_16_SECTOR;
      resync_blk = dmc.dblk_nxt - 8;
      resync_limit = dmc.dblk_nxt - 1;
      return TRUE;
    }

    /*
     * If no sync record found within last 8 sectors, go back and search
     * last 16 sectors
     */
    if (restart_state == DMR_16_SECTOR && resync_blk == dmc.dblk_nxt - 1) {
      if (dmc.dblk_nxt - 16 < dmc.dblk_lower) {
        resync_blk = 0;
        return FALSE;
      }

      restart_state = DMR_FAIL;
      resync_blk = dmc.dblk_nxt - 16;
      resync_limit = dmc.dblk_nxt - 9;
      return TRUE;
    }

    /*
     * If no sync record found within last 16 sectors, bail and do not
     * update recnum or sync offset
     */
    if (restart_state == DMR_FAIL && resync_blk == dmc.dblk_nxt - 9) {
      resync_blk = 0;
      return TRUE;
    }

    dm_panic(7, err, 0);
    return FALSE;
  }


  /*
   * checksum routine for records within a single block
   */
  bool recsum_valid_p(dt_header_t* record_ptr) {
    uint8_t * data = (uint8_t *)record_ptr;
    uint16_t expected_checksum = (record_ptr->recsum);
    uint16_t checksum = 0;
    uint32_t i;

    record_ptr->recsum = 0;
    for (i = 0; i < (record_ptr->len); i++) {
      checksum += data[i];
    }
    nop();
    nop();
    nop();                              /* BRK */
    if(checksum != expected_checksum)
      return FALSE;
    return TRUE;
  }


  /*
   * checksum routine for data records than span multiple blocks
   */
  void recsum_multi_blk_p() {
    uint8_t * data = (uint8_t *)data_ptr;
    uint16_t checksum = 0;
    uint32_t i;

    for (i = 0; i < Bytes2BufLimit; i++) {
      checksum += data[i];
    }

    nop();
    nop();
    nop();                              /* BRK */
    partial_checksum += checksum;
    dm_state = DMS_MULTI_BLK_RECSUM;
    return;
  }


  /*
   * searches an entire block for sync/reboot records when a record is
   * found, saves file offset and datetime, to send to Collect.
   *
   * return:
   * SFS_VALID_SYNC
   * SFS_CORRUPT_SYNC
   * SFS_OUT_OF_DATA
   * SFS_SYNC_RECORD_NOTFOUND
   *
   * This routine uses global peristent variable to control its behaviour.  This
   * is because we are searching for records that may span across multi blk boundaries.
   *
   * Sync Search States:
   *
   * sync_copy_remaining is 0:    searching for the start of a sync, no sync is in progress.
   *      sync_copy_len is meaningless
   *
   * sync_copy_remaining is > 0   current working on a multi blk sync
   *      sync_copy_len           how much of the sync has already been marshalled.
   */
  search_for_sync_t search_for_sync() {
    uint8_t    *dp = dm_buf;
    dt_sync_t *dt_sync_ptr;
    dt_dump_reboot_t * reboot_type __attribute__((unused));

    nop();
    nop();
    nop();                              /* BRK */

    if(sync_copy_remaining == 0) {
      /*
       * working on a fresh sync.
       *
       */
      for (; cur_working_idx < 512; cur_working_idx+=4) {
        dt_sync_ptr = (dt_sync_t*)&dp[cur_working_idx];

        if (cur_working_idx + sizeof(dt_sync_t) >= SD_BLOCKSIZE) {
          /* need to marshall */
          /* set up for the marshall */
          return SFS_OUT_OF_DATA;
        }

        if (!validate_sync(dt_sync_ptr))
          continue;

        if (dt_sync_ptr->sync_majik != SYNC_MAJIK)
          continue;

        if ((dt_sync_ptr->dtype == DT_SYNC &&
             dt_sync_ptr->len == sizeof(dt_sync_t)) ||
            (dt_sync_ptr->dtype == DT_REBOOT &&
             dt_sync_ptr->len == sizeof(dt_dump_reboot_t))) {
          nop();                              /* BRK */

          if((dt_sync_ptr->len + cur_working_idx) > SD_BLOCKSIZE) {

            sync_copy_remaining = ((dt_sync_ptr->len + cur_working_idx) - SD_BLOCKSIZE);
            sync_copy_len = dt_sync_ptr->len - sync_copy_remaining;

            memcpy(&dt_header_copy, &dp[cur_working_idx], sync_copy_len);
            resync_blk++;
            return SFS_OUT_OF_DATA;
          } else {
            memcpy(&dt_header_copy, &dp[cur_working_idx], dt_sync_ptr->len);

            if (validate_sync()) {
              cur_working_idx += ((dt_sync_t*)dt_header_copy)->len;
              return SFS_VALID_SYNC;
            } else {
              return SFS_CORRUPT_SYNC;
            }
            cur_working_idx += ((dt_sync_t*)dt_header_copy)->len;
          }
        }
      }
      resync_blk++;
      return SFS_SYNC_RECORD_NOTFOUND;
    } else {
      nop();
      nop();
      nop();                              /* BRK */
      /* Marshall second portion of partial record */
      memcpy(&dt_header_copy[sync_copy_len], &dp[cur_working_idx+sync_copy_len], sync_copy_remaining);
      sync_copy_remaining = 0;
      reboot_type = (dt_dump_reboot_t *)dt_header_copy;

      if (validate_sync()) {
        cur_working_idx += sync_copy_remaining;
        return SFS_VALID_SYNC;
      } else {
        return SFS_CORRUPT_SYNC;
      }
    }
    nop();
    nop();
    nop();                              /* BRK */
    return SFS_SYNC_RECORD_NOTFOUND;
  }


  /*
   * scans all blocks up to dblk_next for valid data records.
   * last record found is saved to send to Collect.
   */
  bool search_for_last_record() {
    error_t err = 0;
    uint8_t *dp = dm_buf;
    uint32_t number_sectors_to_advance;
    dt_header_t* record_header = (dt_header_t*)&dp[cur_working_idx];
    dt_header_t* prev_record = 0;

    nop();
    nop();
    nop();                              /* BRK */

    while (record_header->dtype > DT_NONE && record_header->dtype <= DT_MAX) {
      if(record_header->len < (SD_BLOCKSIZE - cur_working_idx)) {
        nop();
        nop();
        nop();                              /* BRK */
        if (recsum_valid_p(record_header)) {
          prev_record = record_header;
          cur_working_idx+=record_header->len;
          record_header = (dt_header_t*)&dp[cur_working_idx];
        }
      } else {
        break;
      }
    }
    if (record_header->dtype <= DT_NONE || record_header->dtype > DT_MAX) {
      nop();
      nop();
      nop();                              /* BRK */
      if (prev_record != 0 && recsum_valid_p(prev_record))
        candidate_recnum = prev_record->recnum;
      return FALSE;
    }
    if (record_header->len > (SD_BLOCKSIZE - cur_working_idx)) {
      nop();
      nop();
      nop();                              /* BRK */
      remaining_bytes = record_header->len - (SD_BLOCKSIZE - cur_working_idx);
      number_sectors_to_advance = remaining_bytes / SD_BLOCKSIZE;
      resync_blk += number_sectors_to_advance + 1;

      if (resync_blk > dmc.dblk_nxt)
        dm_panic(7, err, 0);

      if (resync_blk == dmc.dblk_nxt) {
        nop();
        nop();
        nop();                              /* BRK */
        Bytes2BufLimit = (record_header->len - remaining_bytes);
        blk_num = resync_blk -= number_sectors_to_advance;
        data_ptr = (uint8_t *)record_header;
        expected_recnum = record_header->recnum;
        multiblk_expected_checksum = (record_header->recsum);
        record_header->recsum = 0;
        recsum_multi_blk_p();
      }
      resync_blk++;
      return FALSE;
    }

    if (resync_blk == dmc.dblk_nxt) {
      nop();                              /* BRK */
      return FALSE;
    }

    nop();                              /* BRK */
    resync_blk++;
    return FALSE;
  }


  bool validate_sync() {
    if (recsum_valid_p((dt_header_t*)dt_header_copy)) {
      candidate_recnum = ((dt_sync_t*)dt_header_copy)->recnum;
      candidate_last_sync_offset =  ((resync_blk - dmc.dblk_lower) * SD_BLOCKSIZE) + cur_working_idx;
      /* Add datetime routine here */
      record_found = TRUE;
      return TRUE;
    }
    return FALSE;
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
