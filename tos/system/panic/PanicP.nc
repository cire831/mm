/*
 * Copyright (c) 2012-2013, 2016-2017 Eric B. Decker
 * Copyright (c) 2017 Miles Maltbie, Eric B. Decker
 * All rights reserved.
 *
 * This module provides a full Panic implementation.
 *
 * Panic is responsible for collecting crash information and saving
 * it to persistent storage.  One crash set is called a Panic Block
 * and is written to one section of the Panic Region/Area on the SD.
 *
 * See doc/06_Panic_CrashDumps for more details.
 *
 * PANIC_WIGGLE: enables code to wiggle the EXC (exception) signal
 * line with information about what panic occurred.
 */

#include <platform.h>
#include <panic.h>
#include <panic_regions.h>
#include <sd.h>
#include <fs_loc.h>

#ifdef PANIC_GATE
norace volatile uint32_t g_panic_gate;
#endif

#ifdef   PANIC_WIGGLE
#ifndef  WIGGLE_EXC
#warning WIGGLE_EXC not defined, using default nothingness
#define  WIGGLE_EXC do{} while (0)
#define  WIGGLE_DELAY 1
#endif
#endif


#define PCB_SIG 0xAAAAB00B

#define CRASH_CATCHER_STACK_WORD_COUNT 100


typedef struct {
  uint32_t pcb_sig;

  /* if a double panic, high order bit is set */
  uint32_t in_panic;           /* initialized to 0 */

  /* persistent state for collect_io */
  uint8_t *buf;                /* inits to NULL */
  uint8_t *bptr;
  uint32_t remaining;          /* inits to 0 */
  uint32_t block;              /* where the block starts */
  uint32_t panic_sec;          /* current sector being written */

  /* panic control, only active after a Panic happens */
  uint32_t dir;                /* directory sector */
  uint32_t low;                /* low  limit for blocks */
  uint32_t high;               /* high limit for blocks */
} pcb_t;

norace pcb_t pcb;              /* panic control block */

extern image_info_t image_info;
extern uint32_t     __crash_stack_top__;
extern uint32_t crash_stack[];
extern uint32_t crash_regs[];

typedef struct {
  uint32_t a0;                          /* arguments */
  uint32_t a1;
  uint32_t a2;
  uint32_t a3;
  uint8_t  pcode;                       /* subsys */
  uint8_t  where;
} panic_args_t;                         /* panic args stash */


typedef struct {
  uint32_t lr;
  uint32_t r0;
  uint32_t r1;
  uint32_t r2;
  uint32_t r3;
  uint32_t r12;
} exc_regs_t;


exc_regs_t *exc_regs;
panic_args_t _panic_args;
panic_block_0_t _panic_block_0;
panic_block_0_t *b0p = &_panic_block_0;

module PanicP {
  provides interface Panic;
  uses {
    interface SSWrite  as SSW;
    interface Platform;
    interface FileSystem as FS;
    interface OverWatch;
    interface SDsa;                     /* standalone */
    interface SDraw;                    /* other SD aux */
    interface Checksum;
    interface SysReboot;
  }
}

implementation {
#ifdef PANIC_WIGGLE
  void debug_break(parg_t arg)  __attribute__ ((noinline)) {
    uint32_t t0;
    uint32_t i;

    WIGGLE_EXC; WIGGLE_EXC; WIGGLE_EXC; WIGGLE_EXC;     /* 4 */
    t0 = call Platform.usecsRaw();
    while ((call Platform.usecsRaw() - t0) < WIGGLE_DELAY) ;

    for (i = 0; i < _panic_args.pcode; i++)
      WIGGLE_EXC;
    t0 = call Platform.usecsRaw();
    while ((call Platform.usecsRaw() - t0) < WIGGLE_DELAY) ;

    for (i = 0; i < _panic_args.where; i++)
      WIGGLE_EXC;
    t0 = call Platform.usecsRaw();
    while ((call Platform.usecsRaw() - t0) < WIGGLE_DELAY) ;
    WIGGLE_EXC; WIGGLE_EXC; WIGGLE_EXC; WIGGLE_EXC;     /* 4 */

    nop();                              /* the other place */
    ROM_DEBUG_BREAK(0xf0);
  }
#else
  void debug_break(parg_t arg)  __attribute__ ((noinline)) {
    nop();                              /* BRK */
    ROM_DEBUG_BREAK(0xf0);
  }
#endif

  void __panic_exception_entry(uint32_t exception, uint32_t exc_psr, uint32_t exc_msp) @C() @spontaneous() {
    call Panic.panic(PANIC_EXC, exception, exc_psr, exc_msp, 0, 0);
  }


  /*
   * init_panic_dump
   * initialize panic buffer management
   *
   * Typically, someone (SSW) prior to dump will have turned on the
   * SD.  But if not FS.reload_locator_sa() will do it.  Either
   * way we don't need to do a SDsa.reset(), its been done.
   *
   * Don't mess with pcb.in_panic.  Set and/or checked on the
   * entry to Panic.
   */
  void init_panic_dump() {
    panic_dir_t *dirp;

    pcb.pcb_sig   = PCB_SIG;
    pcb.buf       = call SSW.get_temp_buf();
    pcb.bptr      = pcb.buf;
    pcb.remaining = SD_BLOCKSIZE;

    if (call FS.reload_locator_sa(pcb.buf))
      call OverWatch.strange(0x80);     /* no return */

    /* Initialize pcb with sector addresses */
    pcb.dir       = call FS.area_start(FS_LOC_PANIC);
    pcb.low       = pcb.dir + 1;
    pcb.high      = call FS.area_end(FS_LOC_PANIC);
    pcb.block     = pcb.low;
    pcb.panic_sec = pcb.block;

    call SDsa.read(pcb.dir, pcb.buf);
    dirp = (panic_dir_t *) pcb.buf;

    if (!call SDraw.chk_zero(pcb.buf)) {
      if (call Checksum.sum32_aligned((void *) dirp, sizeof(*dirp))
          || dirp->panic_dir_sig != PANIC_DIR_SIG)
        call OverWatch.strange(0x81);

      /*
       * if the dir sector has something in it and it passes the validity
       * checks then use the sector value in it as the starting point for
       * the next panic block.
       */
      pcb.block = dirp->panic_block_sector;
      pcb.panic_sec = pcb.block;
    }

    /*
     * If the Dir sector is zero, then we simply use the initial values
     * set above, pcb.low.
     */
  }


  void panic_write(uint32_t blk_id, uint8_t *buf) {
    if (pcb.pcb_sig != PCB_SIG
        || blk_id < pcb.dir
        || blk_id  > pcb.high)
      call OverWatch.strange(0x82);
    call SDsa.write(blk_id, buf);
  }


  void update_panic_dir() {
    panic_dir_t *dirp;

    /*
     * need to bump pcb.block to the next panic block if any.
     * pcb.block += PBLK_SIZE
     */
    dirp                     = (panic_dir_t *) pcb.buf;
    dirp->panic_dir_sig      = PANIC_DIR_SIG;
    dirp->panic_block_sector = pcb.block + PBLK_SIZE;
    dirp->panic_dir_checksum = 0;
    dirp->panic_dir_checksum = 0 - call Checksum.sum32_aligned((void *) dirp, sizeof(*dirp));

    panic_write(pcb.dir, pcb.buf);
    call SDsa.off();
  }


  uint32_t collect_ram(const panic_region_t *ram_desc, uint32_t start_sec) {
    uint32_t len = ram_desc->len;
    uint8_t *base = ram_desc->base_addr;

    b0p->ram_header.start = (uint32_t)ram_desc->base_addr;
    b0p->ram_header.end = ((uint32_t)ram_desc->base_addr + ram_desc->len);

    while (len > 0) {
      panic_write(start_sec, base);
      start_sec++;
      base += 512;
      len  -= 512;
    }
    return start_sec;
  }


  /*
   * copy the region pointed at by src into the working buffer at dest
   * update where we left off.
   *
   * input: src         where we are coping from
   *        len         how many bytes are being copied
   *        esize       element size, granularity
   *                    1 - byte granules
   *                    2 - half word (16 bit) granules
   *                    4 - word (32 bit) granules
   *                    granuals > 1 have to be properly aligned.
   *
   * data moved should be properly aligned for the granual as well
   * as have a modulo granual length.
   */
  void copy_region(uint8_t *src, uint32_t len, uint32_t esize)  {
    uint8_t *dest;
    uint32_t d_len, copy_len, w_len;
    uint16_t *dp_16, *sp_16;
    uint32_t *dp_32, *sp_32;

    dest = pcb.bptr;
    d_len = pcb.remaining;

    /* protect len against non-granular values */
    len = (len + (esize - 1)) & ~(esize - 1);
    while (len > 0) {
      copy_len = ((len < d_len) ? len : d_len);
      w_len    = copy_len;
      switch (esize) {
        default:
        case 1:
          while (w_len) {
            *dest++ = *src++;
            w_len--;
          }
          break;

        case 2:
          dp_16 = (void *) dest;
          sp_16 = (void *) src;
          while (w_len) {
            *dp_16++ = *sp_16++;
            w_len -= 2;
          }
          break;

        case 4:
          dp_32 = (void *) dest;
          sp_32 = (void *) src;
          while (w_len) {
            *dp_32++ = *sp_32++;
            w_len -= 4;
          }
          break;
      }
      src   += copy_len;
      len   -= copy_len;
      dest  += copy_len;
      d_len -= copy_len;
      if (!d_len) {
        /*
         * current sd buffer is full, need to write it out and
         * reset the buffer pointers.
         */
        panic_write(pcb.panic_sec, pcb.buf);
        pcb.panic_sec++;
        dest = pcb.buf;
        d_len = SD_BLOCKSIZE;
      }
      pcb.bptr = dest;
      pcb.remaining = d_len;
    }
  }


  /* uses persistent global in pcb (panic_sec) for where to write */
  void collect_io(const panic_region_t *io_desc) {
    cc_header_t header;

    while (io_desc->base_addr != PR_EOR) {
      header.start = (uint32_t)io_desc->base_addr;
      header.end = ((uint32_t)io_desc->base_addr + io_desc->len);

      copy_region((void *)&header, sizeof(cc_header_t), 4);
      copy_region(io_desc->base_addr, io_desc->len, io_desc->element_size);
      io_desc++;
    }
    if (pcb.remaining != SD_BLOCKSIZE) {
      call SDraw.zero_fill((uint8_t *)pcb.buf, SD_BLOCKSIZE - pcb.remaining);
      panic_write(pcb.panic_sec, pcb.buf);
      pcb.panic_sec++;
    }
  }


  async command void Panic.warn(uint8_t pcode, uint8_t where,
        parg_t arg0, parg_t arg1, parg_t arg2, parg_t arg3)
        __attribute__ ((noinline)) {

    panic_args_t *pap = &_panic_args;

    pcode |= PANIC_WARN_FLAG;

    pap->pcode = pcode; pap->where = where;
    pap->a0    = arg0;  pap->a1    = arg1;
    pap->a2    = arg2;  pap->a3    = arg3;

    debug_break(0);
  }


  void panic_main(uint32_t *old_sp) @C() @spontaneous() {
    panic_args_t       *pap;            /* panic args stash, working */
    panic_info_t       *pip;            /* panic info in panic_block */
    panic_additional_t *addp;           /* additional in panic_block */
    crash_info_t       *pac;            /* crash_info in panic_block */

    uint32_t w_len = 24;
    uint32_t *sp_32 = (uint32_t *)0xE000ED24; /* Fault regs base address */
    uint32_t *dp_32;
    uint32_t i;
    uint32_t j;

    pap = &_panic_args;
    pap->pcode = old_sp[0];
    pap->where = old_sp[1];
    pap->a0    = old_sp[2];
    pap->a1    = old_sp[3];
    pap->a2    = old_sp[4];
    pap->a3    = old_sp[5];

    pac = &b0p->crash_info;
    pac->sig = CRASH_INFO_SIG;
    pac->flags = 0;

    if (pap->pcode == PANIC_EXC) {
      uint32_t *msp_ptr =  (uint32_t *)(pap->a1);
      exc_regs = (exc_regs_t *)(msp_ptr + 9);

      pac->bxLR = exc_regs->lr;
      pac->bxRegs[0] = exc_regs->r0;
      pac->bxRegs[1] = exc_regs->r1;
      pac->bxRegs[2] = exc_regs->r2;
      pac->bxRegs[3] = exc_regs->r3;
      pac->bxRegs[12] = exc_regs->r12;
    } else {

      i = 0;
      while (i < 4) {
        pac->bxRegs[i] = (uint32_t)(old_sp + i);
        i++;
      }
      pac->bxLR = crash_stack[9 + 118];
      pac->bxRegs[12] = crash_stack[126];
    }

    i = 4;
    j = 0;
    while (j < 8) {
      pac->bxRegs[i] = crash_stack[j + 118];
      i++;
      j++;
    }

    pac->bxSP = (uint32_t)(old_sp - 4);
    pac->axPSR = crash_stack[117];

    /* dp_32 allows unfaulted access to fault regs */
    dp_32 = pac->fault_regs;
    while (w_len) {
      *dp_32++ = *sp_32++;
      w_len -= 4; }

    pcb.in_panic = TRUE;
    ROM_DEBUG_BREAK(0xf0);

    /*
     * First flush any pending buffers out to the SD.
     *
     * Note: If the PANIC is from the SSW or SD subsystem don't flush the buffers.
     */
    if (pap->pcode != PANIC_SD && pap->pcode != PANIC_SS)
      call SysReboot.flush();

    /*
     * signal any modules that a Panic is underway and if possible they should copy any
     * device state into RAM to be copied out.
     */
    signal Panic.hook();

    /*
     * initialize the panic control block so we can dump any panic information
     * out to the PANIC AREA on the SD.
     */
    ROM_DEBUG_BREAK(0xf0);
    init_panic_dump();

    /* first dump RAM out.  then we can do what we want in RAM */
    collect_ram(&ram_region, pcb.block + PBLK_RAM);

    b0p = (panic_block_0_t *) pcb.buf;
    pip = &b0p->panic_info;
    pip->sig = PANIC_INFO_SIG;
    pip->ts  = 0;
    pip->cycle = 0;
    pip->boot_count = 0;
    pip->subsys = pap->pcode;
    pip->where  = pap->where;
    pip->pad    = 0;
    pip->arg[0] = pap->a0;
    pip->arg[1] = pap->a1;
    pip->arg[2] = pap->a2;
    pip->arg[3] = pap->a3;

    memcpy((void *) (&b0p->image_info), (void *) (&image_info), sizeof(image_info_t));

    addp                = &b0p->additional_info;
    addp->sig           = PANIC_ADDITIONS;
    addp->ram_sector    = pcb.block + PBLK_RAM;
    addp->io_sector     = pcb.block + PBLK_IO;
    addp->fcrumb_sector = pcb.block + PBLK_FCRUMBS;

    pcb.panic_sec = pcb.block + PBLK_IO;
    collect_io(&io_regions[0]);
    update_panic_dir();
    ROM_DEBUG_BREAK(0xf0);

    debug_break(1);
    if (pcb.in_panic) {
      pcb.in_panic |= 0x80;             /* flag a double */
      ROM_DEBUG_BREAK(0xf1);
      call OverWatch.strange(0x83);     /* no return */
    }


#ifdef PANIC_GATE
    while (g_panic_gate != 0xdeadbeaf) {
      nop();
    }
    g_panic_gate = 0;
#endif
    call OverWatch.fail(ORR_PANIC);
    /* shouldn't return */
    call OverWatch.strange(0x84);       /* no return */
  }

/*
 * launch the mainline of panic.
 *
 * r0 (new_stack): is the address we want for the crash stack
 * r1 (cur_lr):    the lr we want to force ourselves to use
 *                 from our caller.
 *
 * using cur_lr effectively makes the call to launch_panic
 * become a jump to launch_panic.  It doesn't actualy show
 * up on the backtrace.
 *
 * keeping the call sequence together by maintaining the previous
 * value of lr make it so we can do a valid backtrace even from
 * the new crash stack.  YUM!
 */
  static void launch_panic(void *new_stack, uint32_t cur_lr)
    __attribute__((naked)) {
    nop();                              /* BRK */
    ROM_DEBUG_BREAK(0xf0);
    __asm__ volatile
      /* working notes: sp = bxsp; r0 = axsp; r1 = cur_lr */
      ( "mov r2, sp \n"
        "mov sp, r0 \n"
        "mov r0, r2 \n"
        "mov lr, r1 \n"
        "push {r4-r12, lr} \n"
        "mrs r4, PSR \n"
        "push {r4} \n"
        "b panic_main \n"
        : : : "memory");
  }


  /*
   * Panic.panic: something really bad happened.
   * switch to crash_stack
   *
   * we have to pass in the new stack to get around a linker/asm
   * issue.  But first we save the other 4 parameters on the
   * current stack.  This keeps all 6 of panic's parameters
   * togther but also frees up r0-r3 as scratch.
   *
   * we pass in the address of the stack pointer we want to use
   * as well as the current lr.  This means we can preserve the
   * stack linkage and gdb doesn't get lost.
   */
  async command void Panic.panic(uint8_t pcode, uint8_t where,
                                 parg_t arg0, parg_t arg1, parg_t arg2, parg_t arg3)
    __attribute__ ((naked, noinline)) {
    register uint32_t cur_lr asm ("lr");

    __asm__ volatile ( "push {r0-r3} \n" : : : "memory");
    launch_panic(&__crash_stack_top__, cur_lr);
  }

  event void FS.eraseDone(uint8_t which) { }

  async event void SysReboot.shutdown_flush() { }

  default async event void Panic.hook() { }
}
