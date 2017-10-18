/**
 * This module provides functions for adapting system execution
 * control variables.
 *
 *<p>
 * @author Daniel J. Maltbie <dmaltbie@daloma.org>
 *
 * @Copyright (c) 2017 Daniel J. Maltbie
 * All rights reserved.
 *</p>
 */
/* Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * - Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 *
 * - Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the
 *   distribution.
 *
 * - Neither the name of the copyright holders nor the names of
 *   its contributors may be used to endorse or promote products derived
 *   from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL
 * THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE.
 */
#include <message.h>
#include <Tagnet.h>
#include <TagnetTLV.h>
#include <image_info.h>

module TagnetSysExecP {
  provides interface TagnetSysExecAdapter as  SysActive;
  provides interface TagnetSysExecAdapter as  SysBackup;
  provides interface TagnetSysExecAdapter as  SysGolden;
  provides interface TagnetSysExecAdapter as  SysNIB;
  provides interface TagnetSysExecAdapter as  SysRunning;
  provides interface TagnetSysExecAdapter as  SysReboot;
  uses     interface ImageManager         as  IM;
  uses     interface ImageManagerData     as  IMD;
  uses     interface OverWatch            as  OW;
}
implementation {
  bool    activate_waiting = FALSE;

  /*
   * Active Image control
   */
  command uint8_t SysActive.get_state() {
    image_dir_slot_t    *dirp;

    dirp = call IMD.dir_get_active();
    if (dirp) {
      return call IMD.slotStateLetter(dirp->slot_state);
    }
    return ' ';
  }

  command error_t    SysActive.get_version(image_ver_t *versionp) {
    image_dir_slot_t    *dirp;

    dirp = call IMD.dir_get_active();
    if (dirp) {
      call IMD.setVer(&dirp->ver_id, versionp);
      return SUCCESS;
    }
    return FAIL;
 }

  command error_t    SysActive.set_version(image_ver_t *versionp) {
    /* will cause an overwatch install when set_active_complete() is signalled */
    activate_waiting = TRUE;
    return call IM.dir_set_active(versionp);
  }

  /*
   * Backup Image control
   */
  command uint8_t SysBackup.get_state() {
    image_dir_slot_t*dirp;
    uint16_t         i;

    for (i = 0; i < IMAGE_DIR_SLOTS; i++) {
      dirp = call IMD.dir_get_dir(i);
      if (!dirp)
        break;
      if (dirp->slot_state == SLOT_BACKUP)
        return call IMD.slotStateLetter(dirp->slot_state);
    }
    return ' ';
  }

  command error_t SysBackup.get_version(image_ver_t *versionp) {
    image_dir_slot_t*dirp;
    uint16_t         i;

    for (i = 0; i < IMAGE_DIR_SLOTS; i++) {
      dirp = call IMD.dir_get_dir(i);
      if (!dirp)
        break;
      if (dirp->slot_state == SLOT_BACKUP) {
        call IMD.setVer(&dirp->ver_id, versionp);
        return SUCCESS;
      }
    }
    return FAIL;
  }

  command error_t SysBackup.set_version(image_ver_t *versionp) {
    return call IM.dir_set_backup(versionp);
  }

  /*
   * Golden Image control
   */
  command uint8_t SysGolden.get_state() { return 'G'; }

  command error_t SysGolden.get_version(image_ver_t *versionp) {
    image_info_t    *infop = (void *) 0x140;
    call IMD.setVer(&infop->ver_id, versionp);
    return SUCCESS;
  }

  command error_t SysGolden.set_version(image_ver_t *versionp) {
    return EALREADY;            /* not allowed */
  }

  /*
   * NIB Image control
   */
  command uint8_t SysNIB.get_state() { return 'N'; }

  command error_t SysNIB.get_version(image_ver_t *versionp) {
    image_info_t    *infop = (void *) 0x20140;
    call IMD.setVer(&infop->ver_id, versionp);
    return SUCCESS;
  }

  command error_t SysNIB.set_version(image_ver_t *versionp) {
    return EALREADY;            /* not allowed */
  }

  /*
   * Running Image control
   */
  command uint8_t SysRunning.get_state() {
    uint8_t    st;
    if (call OW.getImageBase())
      st = call SysNIB.get_state();
    else
      st = call SysGolden.get_state();
    return st;
  }

  command error_t SysRunning.get_version(image_ver_t *versionp) {
    if (call OW.getImageBase())
      return call SysNIB.get_version(versionp);
    else
      return call SysGolden.get_version(versionp);
  }

  command error_t SysRunning.set_version(image_ver_t *versionp) {
    return EALREADY;            /* not allowed */
  }

  /*
   * Reboot Image control
   */
  command uint8_t SysReboot.get_state() {
    return call SysRunning.get_state();
  }

  command error_t SysReboot.get_version(image_ver_t *versionp) {
    return call SysRunning.get_version(versionp);
  }

  command error_t SysReboot.set_version(image_ver_t *versionp) {
    call OW.fail(ORR_FORCED_MODE); /* force reboot */
    return SUCCESS;             /* won't get here! */
  }


  event   void    IM.delete_complete() { }

  event   void    IM.dir_eject_active_complete() { }

  event   void    IM.dir_set_active_complete() {
    if (activate_waiting) {
      activate_waiting = FALSE;
      call OW.install();          /* won't return */
    }
  }

  event   void    IM.dir_set_backup_complete() { }

  event   void    IM.finish_complete() {  }

  event   void    IM.write_continue() {  }
}