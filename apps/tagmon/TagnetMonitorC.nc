/*
 * Copyright (c) 2020-2021 Eric B. Decker
 * Copyright (c) 2017-2019 Eric B. Decker, Daniel J. Maltbie
 * Copyright (c) 2015 Eric B. Decker
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
 * @author Daniel J. Maltbie <dmaltbie@daloma.org>
 */

#include "Si446xRadio.h"
#include "Tagnet.h"
#include <rtctime.h>

configuration TagnetMonitorC { }
implementation {
  components TagnetMonitorP, SystemBootC, RegimeC;
  TagnetMonitorP.Boot           -> SystemBootC.Boot;
  TagnetMonitorP.Regime         -> RegimeC;

  components TagnetC;
  TagnetMonitorP.Tagnet         -> TagnetC;
  TagnetMonitorP.TName          -> TagnetC;
  TagnetMonitorP.TTLV           -> TagnetC;


  /* HW monitors and HW ports */

  /* gps port */
  components GPSmonitorC;
  GPSmonitorC.TagnetRadio       -> TagnetMonitorP;

  TagnetC.InfoSensGpsXyz        -> GPSmonitorC;
  TagnetC.InfoSensGpsCmd        -> GPSmonitorC;

  components GPS0C              as GpsPort;
  GPSmonitorC.GPSControl        -> GpsPort;
  GPSmonitorC.MsgTransmit       -> GpsPort;
  GPSmonitorC.MsgReceive        -> GpsPort;
  GPSmonitorC.GPSLog            <- GpsPort;

  /* mems */
  components MemsMonitorC;
  components LSM60C             as LsmPort;
  MemsMonitorC.LsmPort -> LsmPort;


  components TagnetSysExecC;
  TagnetC.SysActive             -> TagnetSysExecC.SysActive;
  TagnetC.SysBackup             -> TagnetSysExecC.SysBackup;
  TagnetC.SysGolden             -> TagnetSysExecC.SysGolden;
  TagnetC.SysNIB                -> TagnetSysExecC.SysNIB;
  TagnetC.SysRunning            -> TagnetSysExecC.SysRunning;
  TagnetC.SysRtcTime            -> TagnetSysExecC.SysRtcTime;

  components TagnetPollExecC;
  TagnetC.PollCount             -> TagnetPollExecC.PollCount;
  TagnetC.PollEvent             -> TagnetPollExecC.PollEvent;

  components DblkByteStorageC;
  TagnetC.DblkBytes             -> DblkByteStorageC.DblkBytes;
  TagnetC.DblkNote              -> DblkByteStorageC.DblkNote;

  components TagnetTestBytesC;
  TagnetC.TestZeroBytes         -> TagnetTestBytesC.TestZeroBytes;
  TagnetC.TestOnesBytes         -> TagnetTestBytesC.TestOnesBytes;
  TagnetC.TestEchoBytes         -> TagnetTestBytesC.TestEchoBytes;
  TagnetC.TestDropBytes         -> TagnetTestBytesC.TestDropBytes;

  components PanicByteStorageC;
  TagnetC.PanicBytes            -> PanicByteStorageC.PanicBytes;

  components CollectC;
  TagnetC.DblkBootRecNum        -> CollectC.DblkBootRecNum;
  TagnetC.DblkBootOffset        -> CollectC.DblkBootOffset;
  TagnetC.DblkLastRecNum        -> CollectC.DblkLastRecNum;
  TagnetC.DblkLastRecOffset     -> CollectC.DblkLastRecOffset;
  TagnetC.DblkLastSyncOffset    -> CollectC.DblkLastSyncOffset;
  TagnetC.DblkCommittedOffset   -> CollectC.DblkCommittedOffset;
  TagnetC.DblkResyncOffset      -> CollectC.DblkResyncOffset;

  TagnetMonitorP.CollectEvent   -> CollectC;

  components Si446xMonitorC;
  TagnetC.RadioRSSI             -> Si446xMonitorC.RadioRSSI;
  TagnetC.RadioTxPower          -> Si446xMonitorC.RadioTxPower;

  components new TimerMilliC()  as StateTimer;
  TagnetMonitorP.smTimer        -> StateTimer;

  components RandomC;
  TagnetMonitorP.Random         -> RandomC;

  components new TaskletC();
  Si446xDriverLayerC.Tasklet    -> TaskletC;
  components new RadioAlarmC();
  Si446xDriverLayerC.RadioAlarm -> RadioAlarmC.RadioAlarm[unique(UQ_SI446X_RADIO_ALARM)];
  Si446xDriverLayerC.Tasklet    -> TaskletC;
  RadioAlarmC.Alarm             -> Si446xDriverLayerC;
  RadioAlarmC.Tasklet           -> TaskletC;

  // -------- MetadataFlags
  components new MetadataFlagsLayerC();
  MetadataFlagsLayerC.SubPacket -> Si446xDriverLayerC;

  components Si446xDriverLayerC;
  TagnetMonitorP.RadioState     -> Si446xDriverLayerC;
  TagnetMonitorP.RadioSend      -> Si446xDriverLayerC;
  TagnetMonitorP.RadioReceive   -> Si446xDriverLayerC;
  Si446xDriverLayerC.TransmitPowerFlag -> MetadataFlagsLayerC.PacketFlag[unique(UQ_SI446X_METADATA_FLAGS)];
  Si446xDriverLayerC.TransmitDelayFlag -> MetadataFlagsLayerC.PacketFlag[unique(UQ_SI446X_METADATA_FLAGS)];
  Si446xDriverLayerC.RSSIFlag   -> MetadataFlagsLayerC.PacketFlag[unique(UQ_SI446X_METADATA_FLAGS)];
  TagnetC.RadioStats            -> Si446xDriverLayerC;

  components PanicC, PlatformC, McuSleepC;
  TagnetMonitorP.Panic          -> PanicC;
  TagnetMonitorP.Platform       -> PlatformC;
  TagnetMonitorP.Rtc            -> PlatformC;
  TagnetMonitorP.RtcAlarm       -> PlatformC;
  TagnetMonitorP.McuPowerOverride<- McuSleepC;

  components OverWatchC;
  TagnetMonitorP.OverWatch      -> OverWatchC;
}
