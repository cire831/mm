/*
 * Copyright (c) 2012, 2014-2015 Eric B. Decker
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
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

/**
 * The Hpl_MM_hw interface exports low-level access to control registers
 * of the mammark h/w.
 *
 * exp5438_5t is the msp430 5438 eval board wired up for various test sensors
 *
 * @author Eric B. Decker
 */

#include "hardware.h"
#include "mmPortRegs.h"

module Hpl_MM_hwP {
  provides interface Hpl_MM_hw as HW;
}

implementation {
  async command bool HW.r446x_cts()          { return R446X_CTS; }
  async command bool HW.r446x_irq()          { return !R446X_IRQ_N; }
  async command void HW.r446x_shutdown()     { R446X_SDN = 1; }
  async command void HW.r446x_unshutdown()   { R446X_SDN = 0; }
  async command void HW.r446x_set_cs()       { R446X_CSN = 0; }
  async command void HW.r446x_clr_cs()       { R446X_CSN = 1; }
  async command void HW.r446x_set_low_pwr()  { R446X_VOLT_SEL = 0; }
  async command void HW.r446x_set_high_pwr() { R446X_VOLT_SEL = 1; }

  async command bool HW.gps_awake()      { return GSD4E_GPS_AWAKE; }
  async command void HW.gps_set_cs()     { GSD4E_GPS_CSN = 0; }
  async command void HW.gps_clr_cs()     { GSD4E_GPS_CSN = 1; }
  async command void HW.gps_set_on_off() { GSD4E_GPS_SET_ONOFF; }
  async command void HW.gps_clr_on_off() { GSD4E_GPS_CLR_ONOFF; }
  async command void HW.gps_set_reset()  { GSD4E_GPS_RESET; }
  async command void HW.gps_clr_reset()  { GSD4E_GPS_UNRESET; }
}
