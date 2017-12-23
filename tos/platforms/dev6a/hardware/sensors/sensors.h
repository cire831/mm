/*
 * Copyright (c) 2017, Eric B. Decker, Miles Maltbie
 * All rights reserved.
 */

#ifndef SENSORS_H
#define SENSORS_H

typedef uint16_t  sensor_id_t;
typedef uint16_t sensor_data_t;

/* MM Sensors

   A primitive sensor is either a single sensor or a sequence
   of single sensors that need to be read at one time.  For
   example the accelerometer consists of a single chip (powered
   once) and requires 3 data cycles (X, Y, and Z).  These
   3 values need to be read back to back.

   Each primitive sensor is represented in the ADC subsystem
   by a sensor id and a single bit in the ADC arbiter (sns_id - 1).
   The ADC can be handling one primitive sensor at a time and must
   be protected by an arbiter.

   Values obtained from the sensors are passed via the buffer
   that is part of the getData interface similar to the MultiChannel
   interface provided in the MSP430 ADC12 implementation.  This
   interface is used for both single and multiple values.

   Singleton sensors include Battery and Temp.

   Sequenced sensors include Salinity (2 x 16), Accel (3 x 16),
   Pressure (2 x 16, pressure and pressure temp), Velocity (2 x 16),
   and Magnatometer (3 x 16).


   NOTE: SNS_ID 0 (SNS_ID_NONE) is used when added information to the data
   stream.  The information is still in data_block format (see sd_blocks.h)
   but doesn't have a normal sensor id associated with it.
*/

enum {
  SNS_ID_NONE		= 0,	// used for other data stream stuff
  SNS_ID_ACCEL		= 1,	// Accelerometer (x,y,z)
  SNS_ID_MAG		= 2,    // Magnetometer (x,y,z)
  SNS_ID_GYRO		= 3,    // Gyro (x,y,z)
  SNS_ID_TMP_0		= 4,	// Temperature Sensor, Internal (on board)
  SNS_ID_TMP_1		= 5,	// Temperature Sensor, External (off board)
  SNS_ID_BATT		= 6,	// Battery Sensor

  SNS_MAX_ID		= 6,

  /*
   * MM_NUM_SENSORS controls how many sensors are compiled into the system.  This also
   * effects allocation of communication message structures.  The allocation doesn't happen
   * automagically as it should so one needs to search all files for use of MM_NUM_SENSORS and
   * make the changes manually.  For example, DTSenderP.nc needs to have pointers to each
   * of the sensor data packets.  But this is done manually since we want it to be allocated
   * in code space.
   */
  MM_NUM_SENSORS	= 7,	// includes none
  SNS_ID_16             = 0xffff,
};

#endif
