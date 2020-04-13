/*
 * Copyright (c) 2016 Eric B. Decker
 * All rights reserved.
 */

/**
 * This module provides the general Led interface.
 *
 * The advantage to doing it this way is we can now create a platforms
 * that provide more or less than 3 LED's, and the LED's can be pull-up or
 * pull-down enabled.
 *
 * @author Eric B. Decker <cire831@gmail.com>
 */

module PlatformLedsP {
  provides {
    interface Init;
    interface Leds;
  }

  uses {
    interface GeneralIO as Led0;
    interface GeneralIO as Led1;
    interface GeneralIO as Led2;
  }
}

implementation {

  /***************** Init Commands ****************/
  command error_t Init.init() {
#ifdef notdef
    /* Init for PlatforLeds handled by __pins_init in startup.c */

    atomic {
      call Led0.makeOutput();
      call Led1.makeOutput();
      call Led2.makeOutput();
      call Led0.clr();
      call Led1.clr();
      call Led2.clr();
    }
#endif
    return SUCCESS;
  }

  /***************** Leds Commands ****************/
  async command void Leds.led0On() {
    call Led0.set();
  }

  async command void Leds.led0Off() {
    call Led0.clr();
  }

  async command void Leds.led0Toggle() {
    call Led0.toggle();
  }

  async command void Leds.led1On() {
    call Led1.set();
  }

  async command void Leds.led1Off() {
    call Led1.clr();
  }

  async command void Leds.led1Toggle() {
    call Led1.toggle();
  }

 async command void Leds.led2On() {
    call Led2.set();
  }

  async command void Leds.led2Off() {
    call Led2.clr();
  }

  async command void Leds.led2Toggle() {
    call Led2.toggle();
  }

  async command uint8_t Leds.get() {
    uint8_t rval;
    atomic {
      rval = 0;
      if (call Led0.get()) {
	rval |= LEDS_LED0;
      }
      if (call Led1.get()) {
	rval |= LEDS_LED1;
      }
      if (call Led2.get()) {
	rval |= LEDS_LED2;
      }
    }
    return rval;
  }

  async command void Leds.set(uint8_t val) {
    atomic {
      if (val & LEDS_LED0) {
	call Leds.led0On();
      } else {
	call Leds.led0Off();
      }
      if (val & LEDS_LED1) {
	call Leds.led1On();
      } else {
	call Leds.led1Off();
      }
      if (val & LEDS_LED2) {
	call Leds.led2On();
      } else {
	call Leds.led2Off();
      }
    }
  }
}
