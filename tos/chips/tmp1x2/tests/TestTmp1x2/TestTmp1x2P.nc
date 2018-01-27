/*
 * Copyright (c) 2012, 2017 Eric B. Decker
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

#include <stdio.h>
#include <Timer.h>
#include <typed_data.h>
#include <sensors.h>

#define SAMPLE_COUNT 60
uint32_t state;
uint16_t tempSamples[SAMPLE_COUNT];
uint32_t sample_idx;
dt_sensor_data_t tdp; /* Temp Data Pointer */

module TestTmp1x2P {
  uses {
    interface Boot;
    interface Panic;
    interface SimpleSensor<uint16_t> as P;
    interface SimpleSensor<uint16_t> as X;
    interface Timer<TMilli> as  TestTimer;
    interface PowerManager;
    interface Collect;
    interface Resource;
    interface Platform;
  }
}
implementation {
  event void Boot.booted() {
    nop();
    nop();   /* BRK */
    sample_idx = 0;
    call TestTimer.startPeriodic(1024);         /* about 1/min */
  }

  event void TestTimer.fired() {
    nop();
    nop();   /* BRK */
    call PowerManager.battery_connected();
    call Resource.immediateRequest();
    call PowerManager.battery_connected();
    call Resource.release();
    if ((state & 1) == 0) {
      call P.isPresent();
      call P.read();
    } else {
      call X.isPresent();
      call X.read();
    }
    nop();
    nop();   /* BRK */
    state++;
  }

  event void P.readDone(error_t error, uint16_t data) {
    nop();
    nop();   /* BRK */
    tempSamples[sample_idx] = data;
    sample_idx++;
    if (sample_idx >= SAMPLE_COUNT) {
      nop();
      nop();
      nop();   /* BRK */
      sample_idx = 0;
      tdp.dtype = DT_SENSOR_DATA;
      tdp.sns_id = SNS_ID_TMP_0;
      tdp.len = (sizeof(dt_sensor_data_t) + (SAMPLE_COUNT));

      call Collect.collect((void *) &tdp, sizeof(dt_sensor_data_t), (void *) &tempSamples, (SAMPLE_COUNT));
    }
  }

  event void X.readDone(error_t error, uint16_t data) {
    nop();
    nop();   /* BRK */
    tempSamples[sample_idx] = data;
    sample_idx++;
    if (sample_idx >= SAMPLE_COUNT) {
      nop();
      nop();
      nop();   /* BRK */
      sample_idx = 0;
    }
  }

  event void Resource.granted() { }

  async event void Panic.hook() { }
}
