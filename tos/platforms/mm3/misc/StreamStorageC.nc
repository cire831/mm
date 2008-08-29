/**
 * Copyright @ 2008 Eric B. Decker
 * @author Eric B. Decker
 * @date 5/8/2008
 *
 * Configuration wiring for StreamStorage.  See StreamStorageP for
 * more details on what StreamStorage does.
 *
 * Threaded TinyOS 2 implementation.
 */

#include "stream_storage.h"

configuration StreamStorageC {
  provides {
    interface Boot as SSBoot;
    interface StreamStorage as SS;
    interface StreamStorageFull as SSF;
    interface BlockingSpiPacket;
  }
  uses interface Boot;
}

implementation {
  components StreamStorageP as SS_P, MainC;
  SS = SS_P;
  SSF = SS_P;
  MainC.SoftwareInit -> SS_P;

  components new BlockingBootC();
  BlockingBootC -> SS_P.BlockingBoot;

  Boot = SS_P.Boot;
  SSBoot = BlockingBootC;

  /*
   * Not sure of the stack size needed here
   * If things seems to break make it bigger...
   *
   * We need to implement stack guards
   * This will also give us an idea of how deep the stacks have been
   */

  components new ThreadC(512) as SSWriter, new ThreadC(512) as SSReader;
  SS_P.SSWriter -> SSWriter;
  SS_P.SSReader -> SSReader;
  
  components SemaphoreC;
  SS_P.Semaphore -> SemaphoreC;

  components new mm3BlockingSpi1C() as SpiWrite;
  components new mm3BlockingSpi1C() as SpiRead;
  SS_P.BlockingWriteResource -> SpiWrite;
  SS_P.BlockingReadResource -> SpiRead;
  SS_P.ResourceConfigure <- SpiWrite;
  SS_P.SpiResourceConfigure -> SpiWrite;
  BlockingSpiPacket = SpiWrite;

//  components new BlockingResourceC();
//  BlockingResourceC.Resource -> SpiC;

  components SDC, PanicC, HplMM3AdcC, LocalTimeMilliC;
  SS_P.SD -> SDC;
  SS_P.Panic -> PanicC;
  SS_P.HW -> HplMM3AdcC;
  SS_P.LocalTime -> LocalTimeMilliC;

  components TraceC;
  SS_P.Trace -> TraceC;
}
