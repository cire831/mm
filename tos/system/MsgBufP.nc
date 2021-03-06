/*
 * Copyright (c) 2020,     Eric B. Decker
 * Copyright (c) 2017-2018 Daniel J. Maltbie, Eric B. Decker
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
 *          Daniel J. Maltbie <dmaltbie@daloma.org>
 */

/*
 * Buffer Slicing:
 *
 * This module handles carving a single receive buffer into logical
 * messages that get delivered to a receiver module.  A single area of
 * memory, buf, is carved up into logical messages (msg) as incoming data
 * arrives.  The messages are kept in strictly FIFO order.
 *
 * The underlying memory is a single circular buffer.  This buffer allows
 * for the incoming traffic to be bursty, and allowing for some flexibility
 * in the processing dynamic.  When the message has been processed it is
 * returned to the free space of the buffer.
 *
 * Free space in this buffer is maintained by a single free structure that
 * remembers a data pointer and length.  It is always the space following
 * any tail (if the queue exists) to the next boundary, either the end
 * of the buffer or to the head of the queue.
 *
 * Typically, free space will be at the tail of the buffer (bottom, higher
 * addresses).  This will continue until the free space at the tail no longer
 * can fit new messages.
 *
 * While free space exists at the tail of the buffer, any msg_release will
 * be added to the free space at the front of the buffer.  This is called
 * Aux_Free and always starts at buf.  Its size is held in aux_len.
 * Thusly, aux_len = msgs[mbc.head].data - buf, if free space is at the
 * rear of the buffer.
 *
 * We purposely keep free behind the message queue as long as we can.  For
 * example, if we have a perfect match at the end of the buffer region,
 * free space will point just beyond and free_len will be 0.  Aux will have
 * any releases that have occured (these will be at the front of buf).  We
 * won't wrap free until a new message is allocated.  The only time free
 * will point at the beginning of the buffer is when there are no messages
 * (empty buffer).
 *
 * We implement a first-in-first-out, contiguous, strictly ordered
 * allocation and queueing discipline.  This defines the message queue.
 * This allows us to minimize the complexity of the allocation and free
 * mechanisms when managing the memory blob.  There is no message
 * fragmentation.
 *
 * Messages are layed down in memory, stictly contiguous.  We do not allow
 * a message to wrap or become split in anyway.  This greatly simplifies
 * how the message is accessed by higher layer routines.  This also means
 * that all memory allocated between head and tail is strictly contiguous
 * subject to end of buffer wrappage.
 *
 * Message byte collection can occur at either interrupt level (async) or
 * from task level (sync).  Both mechanisms are supported.  Completed
 * messages are handed off to upper layers at task level.
 *
 * While messages are being processed, additional incoming bytes can be
 * seen at interrupt level (async arrival).  These bytes will be added to
 * the buffer as an additional message until the buffer runs out of
 * space. The buffer size is set to accommodate some reasonable number of
 * incoming messages.  Once either the buffer becomes full or we run out of
 * msg slots, further messages will be discarded.
 *
 * Management of buffers, messages, and free space.
 *
 * Each msg slot maybe in one of several states:
 *
 *   EMPTY:     available for assignment, doesn't point to a memory region
 *   FILLING:   assigned, currently being filled by incoming bytes.
 *   FULL:      assigned and complete.  In the upgoing queue.
 *   BUSY:      someone is actively messing with the msg, its the head.
 *
 * The buffer can be in one of several states:
 *
 * (The notation M_N indicates the contiguous block of msgs (starting with
 *  msg M through msg N, ie.  head is M, tail is N).
 *
 *   EMPTY, completely empty: There will be one msg set to FREE pointing at
 *     the entire free space.  If there are no msgs allocated, then the
 *     entire buffer has to be free.  free always points at buf and len is
 *     BUF_SIZE.
 *
 *   M_N_1F, 1 (or more) contiguous msgs.  And 1 free region.  The free
 *     region can be either at the front, followed by the msgs, or we can
 *     have msgs (starting at the front of the buffer) followed by the free
 *     space.  free points at this region and its len reflects either the
 *     end of the buffer or from free to head.
 *
 *   M_N_2F, 1 (or more) contiguous msgs and two free regions One before
 *     the msg blocks and a trailing free region.  free will always point
 *     just beyond tail (tail->data + tail->len) and will have a length to
 *     either EOB or to head as appropriate.
 *
 * When we have two free regions, the main free region (pointed to by free) is
 * considered the main free region.  It is what is used when allocating new
 * space for a message.  It immediately trails the Tail area (the last allocated
 * message on the queue).
 *
 * We use an explict free pointer to avoid mixing algorithms between free
 * space constraints and msg_slot constraints.  Seperate control structures
 * keeps the special cases needed to a minimum.
 *
 * When working towards the end of memory, some special cases must be
 * handled.  If we have room for a message but it won't fit in the region
 * at the end of memory we do a force_consumption of the bytes at the
 * end, they get added to tail->extra and we wrap the free pointer.
 * The new message gets allocated at the front of the buffer and we move
 * on.  When the previous tail message is msg_released the extra bytes
 * will also be removed.
 *
 * Note that we must check to see if the message will fit before changing
 * any state.
 *
 *
**** Discussion of control variables and corner cases:
 *
 * The buffer allocation is controlled by the following cells:
 *
 * xxx_msgs: an array of strictly ordered xxx_msg_t structs that point at
 *   regions in buf.
 *
 * head(h): head index, points to an element of xxx_msgs that defines the
 *   head of the fifo queue of msg_slots that contain allocated messages.
 *   If head is INVALID no messages are queued (queue is empty).
 *
 * tail(t): tail index, points to the last element of xxx_msgs that defines
 *   the tail of the fifo queue.  All msg_slots between h and t are valid
 *   and point at valid messages.
 *
 * messages are allocated stictly ordered (subject to wrap) and successive
 * entries in xxx_msgs (the msg array) will point to messages that have
 * arrived later than earlier entries.  This sequence of msg_slots forms an
 * ordered first-in-first-out queue for the messages as they arrive.
 * Further successive entries in the fifo will also be strictly contiguous.
 *
 *
 * free space control:
 *
 *   free: is a pointer into buf.  It always points at memory that follows
 *     the tail msg if tail is valid.  It either runs from the end of tail
 *     to the end of buf (free region is in the rear of the buffer) or from
 *     the end of tail to start of head (free region is in the front of the
 *     buffer)
 *
 *   free_len: the length of the current free region.
 *
 *
****
**** Corner/Special Cases:
****
 *
**** Initial State: When the buffer is empty, there are no entries in the
 *   msg_queue, head will be INVALID.  Free will be set to start of buf
 *   with a free_len of BUF_SIZE
 *
 * Transition from 1 queue element to 0.  ie.  the last msg is released and
 * the queue length is 1.  The queue may be located anywhere in memory,
 * when the last element is released we could end up with a fragmented free
 * space, even though all memory has now been released.
 *
 * When the last message is released, the free space will be reset back to
 * fully contiguous, ie. free = buf, free_len = BUF_SIZE.
 *
**** Running out of memory:
 *
 * Memory starvation is indicated by free_len < len (the requested length)
 * and aux_len < len.  We will always return NULL (fail) to a msg_start
 * call.
 *
 * When checking to see if a message will fit we need to check both the
 * current free region and the aux region (in the front).
 *
 *
**** Running Off the End:
 *
 * We run off the end of the buffer when a new msg won't fit in the current
 * remaining free space.  We want to keep all messages contiguous to
 * simplify access to the data and the current message won't fit in the
 * remaining space.
 *
 * There may be more free space in the aux region at the front.  We first
 * check to see if a message will fit in the current region (free_len).  If
 * not check the aux_region (aux_len).
 *
**** Freeing last used msg_slot (free space reorg)
 *
 * When the last used message is freed, the entire buffer will be free
 * space.  We want to coalesce the free space into one contiguous region
 * again.  Set free = buf and free_len = XXX_BUF_SIZE.  aux_len = 0.
 */


#include <panic.h>
#include <platform_panic.h>
#include <msgbuf.h>
#include <rtctime.h>


#ifndef PANIC_MSGBUF
enum {
  __pcode_msgbuf = unique(UQ_PANIC_SUBSYS)
};

#define PANIC_MSGBUF __pcode_msgbuf
#endif

enum {
  MSGW_RESET_FREE = 32,
  MSGW_START,
  MSGW_START_1,
  MSGW_START_2,
  MSGW_START_3,
  MSGW_START_4,
  MSGW_START_5,
  MSGW_START_6,
  MSGW_ADD_BYTE,
  MSGW_ABORT,
  MSGW_ABORT_1,
  MSGW_ABORT_2,
  MSGW_COMPLETE,
  MSGW_COMPLETE_1,
  MSGW_NEXT,
  MSGW_RELEASE,
  MSGW_RELEASE_1,
  MSGW_RELEASE_2,
};


module MsgBufP {
  provides {
    interface Init @exactlyonce();
    interface MsgBuf;
    interface MsgReceive;
  }
  uses {
    interface Rtc;
    interface Panic;
  }
}
implementation {
         uint8_t    msg_buf[MSG_BUF_SIZE];      /* underlying storage */
         msg_slot_t msg_msgs[MSG_MAX_MSGS];     /* msg slots */
  norace mbc_t      mbc;                        /* msgbuffer control */


  void mb_warn(uint8_t where, parg_t p0, parg_t p1) {
    call Panic.warn(PANIC_MSGBUF, where, p0, p1, 0, 0);
  }

  void mb_panic(uint8_t where, parg_t p0, parg_t p1) {
    call Panic.panic(PANIC_MSGBUF, where, p0, p1, 0, 0);
  }


  command error_t Init.init() {
    /* initilize the control cells for the msg queue and free space */
    mbc.free     = msg_buf;
    mbc.free_len = MSG_BUF_SIZE;
    mbc.head     = MSG_NO_INDEX;        /* no msgs in queue */
    mbc.tail     = MSG_NO_INDEX;        /* no msgs in queue */

    /* all msg slots initialized to EMPTY (0) */

    return SUCCESS;
  }


  /*
   * gps_receive_task: actually run the incoming gps message queue
   *
   * gps_receive_task will run the gps queue.  It will be posted
   * any time the incoming fifo goes from 0 to 1 element.  It does the
   * following:
   *
   * o grab the next data pointer from the HEAD via msg_next
   * o pass the msg to any receive handler via MsgReceive.msg_available
   * o on return, kill the current message, msg_release
   * o repeat, until msg_next returns NULL.
   *
   * depending on task loading and balance considerations one may or may
   * not want to repost the task and handle one message at a time or some
   * combination.
   */

  task void gps_receive_task() {
    uint8_t *msg;
    uint16_t len;
    rtctime_t *arrival_rtp;
    uint32_t mark;

    while (1) {
      msg = call MsgBuf.msg_next(&len, &arrival_rtp, &mark);
      if (!msg)
        break;
      signal MsgReceive.msg_available(msg, len, arrival_rtp, mark);
      call MsgBuf.msg_release();
    }
  }


  /*
   * reset_free: reset free space to pristine state.
   */
  void reset_free() {
    if (MSG_INDEX_VALID(mbc.head) || MSG_INDEX_VALID(mbc.tail)) {
        mb_panic(MSGW_RESET_FREE, mbc.head, mbc.tail);
        return;
    }
    mbc.free     = msg_buf;
    mbc.free_len = MSG_BUF_SIZE;
    mbc.aux_len  = 0;
  }


  async command uint8_t *MsgBuf.msg_start(uint16_t len) {
    msg_slot_t *msg;            /* message slot we are working on */
    uint16_t    idx;            /* index of message slot */

    if (mbc.free < msg_buf || mbc.free > msg_buf + MSG_BUF_SIZE ||
        mbc.free_len > MSG_BUF_SIZE) {
      mb_panic(MSGW_START, (parg_t) mbc.free, mbc.free_len);
      return NULL;
    }

    /*
     * gps packets have a minimum size.  If the request is too small
     * bail out.  This includes any overhead vs. length field.
     */
    if (len < MSG_MIN_MSG)
      return NULL;

    /*
     * bail out early if no free space or not enough slots
     */
    if (mbc.full >= MSG_MAX_MSGS ||
        (mbc.free_len < len && mbc.aux_len < len))
      return NULL;

    /*
     * Look at the msg queue to see what the state of free space is.
     * EMPTY (buffer is all FREE), !EMPTY (1 or 2 free space regions).
     */
    if (MSG_INDEX_EMPTY(mbc.head) && MSG_INDEX_EMPTY(mbc.tail)) {
      if (mbc.free != msg_buf || mbc.free_len != MSG_BUF_SIZE) {
        mb_panic(MSGW_START_1, (parg_t) mbc.free, (parg_t) msg_buf);
        return NULL;
      }

      /* no msgs, all free space */
      msg        = &msg_msgs[0];
      msg->data  = msg_buf;
      msg->len   = len;
      msg->state = MSG_SLOT_FILLING;
      call Rtc.getTime(&msg->arrival_rt);
      mbc.free   = msg_buf + len;
      mbc.free_len -= len;              /* zero is okay */

      mbc.allocated = len;
      if (mbc.allocated > mbc.max_allocated)
        mbc.max_allocated = mbc.allocated;

      mbc.head   = 0;                   /* always 0 */
      mbc.tail   = 0;                   /* ditto for tail */
      mbc.full   = 1;                   /* just one */
      if (!mbc.max_full)                /* if zero, pop it */
        mbc.max_full = 1;

      /* no need to wrap if mbc.free_len is zero, just consumed it all */

      return msg->data;
    }

    if (MSG_INDEX_INVALID(mbc.head) || MSG_INDEX_INVALID(mbc.tail)) {
      mb_panic(MSGW_START_2, mbc.tail, 0);
      return NULL;
    }

    /*
     * make sure that tail->state is FULL (BUSY counts as FULL).  Need to
     * complete previous message before doing another start.
     */
    msg = &msg_msgs[mbc.tail];
    if (msg->state != MSG_SLOT_FULL && msg->state != MSG_SLOT_BUSY) {
      mb_panic(MSGW_START_3, mbc.tail, msg->state);
      return NULL;
    }
    if (msg->extra) {                   /* extra should always be zero here */
      mb_panic(MSGW_START_4, mbc.tail, msg->extra);
      return NULL;
    }

    /*
     * First check to see if the request won't fit in the current free
     * space.
     *
     * If it doesn't fit, we still know it will fit into the aux area.
     * So ...
     *
     * note if something got screwy and the checks don't pass we fall
     * all the way through (none of the ifs take) and hit the panic
     * at the bottom.  Shouldn't ever happen.....  Ah the joys of paranoid
     * programming.  (the code at the end, the panic, should actually
     * get optimized out.)
     */
    if (len > mbc.free_len && len <= mbc.aux_len) {
      /*
       * ah ha!  Just as I suspected, doesn't fit into the current free
       * region but does fit into the free space at the front of the
       * buffer.
       *
       * first put the remaining free space onto the extra of tail.
       * zero free and wrap it.  That puts us onto the front free region.
       * Then we can just fall through into the next if and let
       * the regular advance take over.
       *
       * Note: since aux_len is non-zero, current free space must be on
       * the tail of the buffer.  ie.  free > msg_msgs[head].data.
       */
      msg->extra = mbc.free_len;
      mbc.free_len = 0;
      mbc.allocated += msg->extra;      /* put extra into allocated too */
      if (mbc.allocated > mbc.max_allocated)
        mbc.max_allocated = mbc.allocated;
      mbc.free = msg_buf;                 /* wrap to beginning */
      mbc.free_len = mbc.aux_len;
      mbc.aux_len  = 0;
    }

    /*
     * The msg queue is not empty.  Tail (t) points at the last puppy.
     * We know we have 1 or 2 free regions.  free points at the one
     * we want to try first.  If we have 2 regions, free is the tail
     * and aux_len says the front one is active too.
     *
     * note: if we wrapped above, aux_len will be zero (back to 1 active
     * region, in the front).  We won't wrap again.
     */
    if (len <= mbc.free_len) {
      /* msg will fit in current free space. */
      idx = MSG_NEXT_INDEX(mbc.tail);
      msg = &msg_msgs[idx];
      if (msg->state) {                 /* had better be empty */
        mb_panic(MSGW_START_5, (parg_t) msg, msg->state);
        return NULL;
      }

      msg->data  = mbc.free;
      msg->len   = len;
      msg->state = MSG_SLOT_FILLING;
      mbc.tail   = idx;                 /* advance tail */

      call Rtc.getTime(&msg->arrival_rt);
      mbc.free = mbc.free + len;
      mbc.free_len -= len;              /* zero is okay */
      mbc.allocated += len;
      if (mbc.allocated > mbc.max_allocated)
        mbc.max_allocated = mbc.allocated;

      mbc.full++;                       /* one more*/
      if (mbc.full > mbc.max_full)
        mbc.max_full = mbc.full;
      return msg->data;
    }

    /* shouldn't be here, ever */
    mb_panic(MSGW_START_6, mbc.free_len, mbc.aux_len);
    return NULL;
  }


  /*
   * msg_abort: send current message back to the free pool
   *
   * current message is defined to be Tail.  It must be in
   * FILLING state.
   *
   * msg->extra should never be set in a pending msg.  It is only
   * used with the last msg if a new message doesn't fit.  It only
   * gets referenced in msg_start and msg_release.
   */
  async command void MsgBuf.msg_abort() {
    msg_slot_t *msg;            /* message slot we are working on */
    uint8_t   *slice;           /* memory slice we are aborting */

    if (MSG_INDEX_INVALID(mbc.tail)) {  /* oht oh */
      mb_panic(MSGW_ABORT, mbc.tail, 0);
      return;
    }
    msg = &msg_msgs[mbc.tail];
    if (msg->state != MSG_SLOT_FILLING) { /* oht oh */
      mb_panic(MSGW_ABORT_1, (parg_t) msg, msg->state);
      return;
    }
    if (msg->extra) {                   /* oht oh */
      mb_panic(MSGW_ABORT_2, (parg_t) msg, msg->extra);
      return;
    }
    msg->state = MSG_SLOT_EMPTY;        /* no longer in use */
    slice = msg->data;
    msg->data = NULL;
    if (mbc.head == mbc.tail) {         /* only entry? */
      mbc.head = MSG_NO_INDEX;
      mbc.tail = MSG_NO_INDEX;
      mbc.full = 0;
      mbc.allocated = 0;
      reset_free();
      return;
    }

    /*
     * Only one special case:
     *
     * o tail->data == msg_buf, a msg didn't fit in the free space, we
     *     consumed and added it to the previous tail, (t-1)->extra. The
     *     new message then got added at the front of the aux region
     *     (msg_buf).
     *
     *     We want to remove the current tail (which is at the front of
     *     msg_buf), restore the aux region (aux_len), and move free back
     *     to point at the extra that was added to the prev tail.
     */

    if (slice == msg_buf) {
      /*
       * Special Case: Tail->data == msg_buf
       *
       * The Tail we are nuking was added because it wouldn't fit in the
       * previous free region, this caused Free to Wrap and there will be
       * 0 or more extra bytes on the previous tail.
       *
       * We want to restore aux_len (tail->len + free_len), back tail up to
       * its previous value.  free = tail->data+len (point at the extra area)
       * and free_len = tail->extra.  Nuke tail->extra.
       */
      mbc.aux_len = msg->len + mbc.free_len;
      mbc.allocated -= msg->len;
      mbc.tail = MSG_PREV_INDEX(mbc.tail);
      msg = &msg_msgs[mbc.tail];
      mbc.free = msg->data + msg->len;
      mbc.free_len = msg->extra;
      mbc.allocated -= msg->extra;
      msg->extra = 0;
      mbc.full--;
      return;
    }

    /*
     * Relatively Normal
     *
     * Tail and Free have a relatively normal relationship.  Just
     * move Free to where Tail starts and add in its length.  There
     * should never be any extra here.
     *
     * msg set to tail above, and its state to EMPTY.
     */
    mbc.free = slice;
    mbc.free_len += msg->len;
    mbc.allocated -= msg->len;
    mbc.tail = MSG_PREV_INDEX(mbc.tail);
    mbc.full--;
    return;
  }


  /*
   * msg_compelete: flag current message as complete
   *
   * current message is TAIL.
   */
  async command void MsgBuf.msg_complete() {
    msg_slot_t *msg;             /* message slot we are working on */

    if (MSG_INDEX_INVALID(mbc.tail)) {  /* oht oh */
      mb_panic(MSGW_COMPLETE, mbc.tail, 0);
      return;
    }
    msg = &msg_msgs[mbc.tail];
    if (msg->state != MSG_SLOT_FILLING) { /* oht oh */
      mb_panic(MSGW_COMPLETE_1, (parg_t) msg, msg->state);
      return;
    }

    msg->state = MSG_SLOT_FULL;
    if (mbc.tail == mbc.head)
      post gps_receive_task();          /* start processing the queue */
  }


  command uint8_t *MsgBuf.msg_next(uint16_t *lenp,
        rtctime_t **arrival_rtpp, uint32_t *markp) {
    msg_slot_t *msg;                   /* message slot we are working on */

    atomic {
      if (MSG_INDEX_INVALID(mbc.head))          /* empty queue */
        return NULL;
      msg = &msg_msgs[mbc.head];
      if (msg->state == MSG_SLOT_FILLING)       /* not ready yet */
        return NULL;
      if (msg->state != MSG_SLOT_FULL) {        /* oht oh */
        mb_panic(MSGW_NEXT, (parg_t) msg, msg->state);
        return NULL;
      }
      msg->state = MSG_SLOT_BUSY;
      *lenp = msg->len;
      *arrival_rtpp = &msg->arrival_rt;
      *markp       = msg->mark_j;
      return msg->data;
    }
  }


  command uint8_t *MsgBuf.msg_last(uint16_t *lenp,
        rtctime_t **arrival_rtpp, uint32_t *markp) {
    msg_slot_t *msg;                   /* message slot we are working on */

    atomic {
      if (MSG_INDEX_INVALID(mbc.head))          /* empty queue */
        return NULL;
      msg = &msg_msgs[mbc.tail];                /* last message we are working on */

      /* only allow looking at msgs that are complete */
      if (msg->state != MSG_SLOT_FULL)          /* oht oh */
        mb_panic(MSGW_NEXT, (parg_t) msg, msg->state);

      *lenp = msg->len;
      *arrival_rtpp = &msg->arrival_rt;
      *markp       = msg->mark_j;
      return msg->data;
    }
  }


  /*
   * msg_release: release the next message in the queue
   *
   * the next message to be released is always the HEAD
   */
  command void MsgBuf.msg_release() {
    msg_slot_t *msg;            /* message slot we are working on */
    uint8_t    *slice;          /* slice being released */
    uint16_t    rtn_size;       /* what is being freed */

    atomic {
      if (MSG_INDEX_INVALID(mbc.head) ||
          MSG_INDEX_INVALID(mbc.tail)) {  /* oht oh */
        mb_panic(MSGW_RELEASE, mbc.head, 0);
        return;
      }
      msg = &msg_msgs[mbc.head];
      /* oht oh - only FULL or BUSY can be released */
      if (msg->state != MSG_SLOT_BUSY && msg->state != MSG_SLOT_FULL) {
        mb_panic(MSGW_RELEASE_1, (parg_t) msg, msg->state);
        return;
      }
      msg->state = MSG_SLOT_EMPTY;
      slice = msg->data;
      msg->data  = NULL;                /* for observability */
      rtn_size = msg->len + msg->extra;
      if (mbc.head == mbc.tail) {
        /* releasing entire buffer */
        mbc.head     = MSG_NO_INDEX;
        mbc.tail     = MSG_NO_INDEX;
        mbc.full     = 0;
        mbc.allocated= 0;
        reset_free();
        return;
      }

      if (slice < mbc.free) {
        /*
         * slice (the head being released) is below the free pointer, this
         * means free is on the tail of the region.  (back of the buffer).
         * extra is always 0 when slice < free.
         *
         * The release needs to get added to the aux region.
         */
        mbc.aux_len += rtn_size;
        mbc.allocated -= rtn_size;
        mbc.head = MSG_NEXT_INDEX(mbc.head);
        mbc.full--;
        return;
      }

      /*
       * must be free < slice (head)
       *
       * free space is in front of the slice (head).  no aux.  add the
       * space from head/slice to the free space.
       */
      if (mbc.aux_len) {
        /*
         * free space is in the front of the buffer (below the head/slice)
         * aux_len shouldn't have anything on it.  Bitch.
         */
        mb_panic(MSGW_RELEASE_2, mbc.aux_len, (parg_t) mbc.free);
        return;
      }
      msg->extra = 0;
      mbc.free_len += rtn_size;
      mbc.allocated -= rtn_size;
      mbc.head = MSG_NEXT_INDEX(mbc.head);
      mbc.full--;
      return;
    }
  }


  default event void MsgReceive.msg_available(uint8_t *msg, uint16_t len,
        rtctime_t *arrival_rtp, uint32_t mark_j) { }

  async event void Panic.hook() { }
}
