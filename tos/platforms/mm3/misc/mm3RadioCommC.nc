/**
 * Copyright @ 2008 Eric B. Decker
 * @author Eric B. Decker
 */
 
#include "sensors.h"

configuration mm3RadioCommC {
  provides interface Send[uint8_t id];
  provides interface SendBusy[uint8_t id];
  provides interface AMPacket;
  provides interface Packet;
  provides interface SplitControl;
}

implementation {
  components new AMSenderC(AM_MM_DATA);
  components new AMQueueImplP(MM_NUM_SENSORS), ActiveMessageC;

  Send = AMQueueImplP;
  SendBusy = AMQueueImplP;
  AMPacket = AMSenderC;
  Packet = AMSenderC;
  SplitControl = ActiveMessageC;
  
  AMQueueImplP.AMSend[AM_MM_DATA] -> AMSenderC;
  AMQueueImplP.Packet -> AMSenderC;
  AMQueueImplP.AMPacket -> AMSenderC;
}
