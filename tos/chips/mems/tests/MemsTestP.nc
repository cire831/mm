#include "typed_data.h"
#include "sensors.h"


module MemsTestP {
  uses interface Boot;
  uses interface Panic;

  uses interface Timer<TMilli> as AccelTimer;
  uses interface Lis3dh as Accel;

  uses interface Collect;
  uses interface Platform;

#ifdef REGIME_TEST
  uses interface Regime as RegimeCtrl;
#endif

#ifdef notdef
  uses interface Timer<TMilli> as GyroTimer;
  uses interface L3g4200 as Gyro;

  uses interface Timer<TMilli> as MagTimer;
  uses interface Lis3mdl as Mag;
#endif
}
implementation {
  typedef struct {
    uint8_t xLow;
    uint8_t xHigh;
    uint8_t yLow;
    uint8_t yHigh;
    uint8_t zLow;
    uint8_t zHigh;
  } mems_sample_t;

  #define SAMPLE_COUNT 60
  #define SAMPLE_SIZE 6
  uint8_t m_accelSampleCount;
  uint8_t m_gyroSampleCount;
  uint8_t m_magSampleCount;

  mems_sample_t m_accelSamples[SAMPLE_COUNT];
  mems_sample_t m_gyroSamples[SAMPLE_COUNT];
  mems_sample_t m_magSamples[SAMPLE_COUNT];

  dt_sensor_data_t adp; /* Accel Data Pointer */
  // uint8_t accel_state;
  uint32_t period;
  uint32_t total_samples;
  uint32_t total_collects;
  uint32_t      t0, t1;
  uint8_t  max_thresh;

#ifdef REGIME_TEST
  event void RegimeCtrl.regimeChange() {
    uint32_t new_period;

    call AccelTimer.stop();
    new_period = call RegimeCtrl.sensorPeriod(SNS_ID_ACCEL);
    if (new_period == 0) {
      //    temp_state = TEMP_STATE_OFF;
      return;
    }
//    temp_state = TEMP_STATE_IDLE;
    period = new_period;
    t0 = call Platform.usecsRaw();
    call AccelTimer.startPeriodic(period);
  }
#endif

  event void Boot.booted() {
    nop();
    nop();   /* BRK */
    m_magSampleCount = call Accel.whoAmI();

#ifdef INCREASE_HZ_TEST
    call Accel.config100Hz();
    call AccelTimer.startPeriodic(5);
#else
    call Accel.config1Hz();
    call AccelTimer.startPeriodic(500);
#endif

#ifdef notdef
    id = call Gyro.whoAmI();
    call Gyro.config100Hz();
    call GyroTimer.startPeriodic(1000);

    id = call Mag.whoAmI();
    call Mag.config10Hz();
    call MagTimer.startPeriodic(1000);
#endif
  }


  event void AccelTimer.fired() {
    nop();
    nop();   /* BRK */

    if (call Accel.xyzDataAvail()) {
      nop();
      nop();   /* BRK */
      call Accel.readSample((uint8_t *)(&m_accelSamples[m_accelSampleCount]),
			    (SAMPLE_SIZE));
      m_accelSampleCount ++;
      total_samples ++;

      if (m_accelSampleCount >= SAMPLE_COUNT) {
        nop();
        nop();   /* BRK */

        adp.dtype = DT_SENSOR_DATA;
        adp.sns_id = SNS_ID_ACCEL;
        adp.len = (sizeof(dt_sensor_data_t) + (SAMPLE_SIZE * SAMPLE_COUNT));
        /* Timer is stopped for debugging purposes */
        //   call AccelTimer.stop();

        call Collect.collect((void *) &adp, sizeof(dt_sensor_data_t), (void *) &m_accelSamples, (SAMPLE_SIZE * SAMPLE_COUNT));
        m_accelSampleCount = 0;
        total_collects++;
        if (total_samples > 1000) {
          t1 = call Platform.usecsRaw();
          t1 = t1 - t0;

          nop();
          nop();   /* BRK */
          call AccelTimer.stop();
        }
      }

    }
  }

#ifdef notdef
  event void GyroTimer.fired() {
    nop();
    if (call Gyro.xyzDataAvail()) {
      call Gyro.readSample((uint8_t *)(&m_gyroSamples[m_gyroSampleCount]),
			   SAMPLE_SIZE);
      m_gyroSampleCount++;
    }
    if (m_gyroSampleCount >= SAMPLE_COUNT) {
      call GyroTimer.stop();
    }
  }


  event void MagTimer.fired() {
    nop();
    if (call Mag.xyzDataAvail()) {
      call Mag.readSample((uint8_t *)(&m_magSamples[m_magSampleCount]),
			  SAMPLE_SIZE);
      m_magSampleCount++;
    }
    if (m_magSampleCount >= SAMPLE_COUNT) {
      call MagTimer.stop();
    }
  }
#endif

  async event void Panic.hook() { }
}
