/*
 * Copyright 2014 (c) Eric Decker
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
 *
 * @author Eric Decker
 */

#ifndef _H_PLATFORM_GSD4E_SPI_H_
#define _H_PLATFORM_GSD4E_SPI_H_

#include "msp430usci.h"

/* MM5, 5438a, USCI, SPI, gps interface
 * phase 0, polarity 0, msb, 8 bit, master,
 * mode 3 pin, sync.
 *
 * SMCLK (8MHz)/2 -> 4MHz
 */
const msp430_usci_config_t gsd4e_spi_config = {
  ctl0 : (UCMSB | UCMST | UCSYNC),
  ctl1 : UCSSEL__SMCLK,
  br0  : 2,			/* 8MHz -> 4 MHz */
  br1  : 0,
  mctl : 0,                     /* Always 0 in SPI mode */
  i2coa: 0
};

#endif	/* _H_PLATFORM_GSD4E_SPI_H_ */
