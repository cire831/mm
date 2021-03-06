
#include <rtctime.h>

uint32_t recv_count;
uint16_t last_size;


module testMsgBufP {
  uses {
    interface Boot;
    interface MsgReceive;
    interface MsgBuf;
    interface Platform;
  }
}

implementation {

  task void test_task() {
    uint8_t *buf;

    while (1) {
      if (last_size == 0)
        last_size = 10;
      buf = call MsgBuf.msg_start(last_size);
      nop();
      if (!buf) {
        post test_task();
        return;
      }
      call MsgBuf.msg_abort();
      nop();
      buf = call MsgBuf.msg_start(last_size);
      buf[0] = last_size         & 0xff;
      buf[1] = (last_size >>  8) & 0xff;
      buf[2] = (last_size >> 16) & 0xff;
      buf[3] = (last_size >> 24) & 0xff;
      call MsgBuf.msg_complete();
      last_size += 11;
      if (last_size > 256)
        last_size = 0;
    }
  }

  event void Boot.booted() {
    post test_task();
  }


  event void MsgReceive.msg_available(uint8_t *msg, uint16_t len,
                                      rtctime_t *rtp, uint32_t mark) {
    nop();
    recv_count++;
  }
}
