/*
 * Copyright (c) 2021 Eric B. Decker
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
 * given a set of chips on an SPI bus, collect the chip selects and
 * the actual USCI h/w.  Expose as SpiReg[mem_id].
 *
 * Also export each sensor's interrupt
 */

configuration HplMems0C {
  provides interface SpiReg[uint8_t mem_id];
}
implementation {
  components HplMsp432GpioC   as GIO;
  components Msp432UsciSpiB1C as SpiC;
  components Mems0HardwareP;
  components PanicC, PlatformC;

  SpiC.CLK                 -> GIO.UCB1CLK;
  SpiC.SOMI                -> GIO.UCB1SOMI;
  SpiC.SIMO                -> GIO.UCB1SIMO;
  SpiC.Panic               -> PanicC;
  SpiC.Platform            -> PlatformC;
  SpiC.Msp432UsciConfigure -> Mems0HardwareP;

  PlatformC.PeripheralInit -> Mems0HardwareP;
  Mems0HardwareP.SpiInit   -> SpiC;

  components HplMsp432PortIntP as PortInts;
  components McuSleepC;
  PortInts.McuSleep -> McuSleepC;
  Mems0HardwareP.LSM6Int1Port -> PortInts.Int[MEMS0_LSM6DSOX_INT1_PORT_PIN];

  components new MemsBusP() as StMemsBus;
  StMemsBus.FastSpiByte    -> SpiC;
  StMemsBus.SpiBus         -> Mems0HardwareP;
  Mems0HardwareP.Panic     -> PanicC;

  SpiReg = StMemsBus;
}
