/*
 * Copyright (c) 2020-2021 Eric B. Decker
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
 */

#ifndef __UBLOX_MSG_H__
#define __UBLOX_MSG_H__

/*
 * Various external Ublox UBX structures and definitions that are protocol
 * dependent.
 *
 * Alignment: Ublox packets are laid out such that all multibyte fields are aligned.
 * However, we can't take advantage of this for a couple of reasons.  A) We
 * include both sync bytes but the alignment starts assuming Class/Id is aligned
 * (which we violate).  And B) the underlying messages (buffer slicing) are not
 * guaranteed to be quad aligned.
 *
 * Bottom line, any multibyte fields must extracted byte by byte and properly
 * assembled.
 *
 * Values are documented in u-blox8-M8_ReceiverDescrProtSpec (UBX-13003221),
 * version 24.  Additional values have been extracted from ucenter 20.06.01.
 */

#ifndef PACKED
#define PACKED __attribute__((__packed__))
#endif

#define NMEA_START      '$'
#define NMEA_END        '*'

#define UBX_SYNC1       0xB5
#define UBX_SYNC2       0x62

/* Packet Format:
 *
 *     1       1       1      1        2       LEN        2
 * +-------+-------+-------+------+--------+---------+---------+
 * | SYNC1 | SYNC2 | CLASS |  ID  |   LEN  | PAYLOAD | CHK_A/B |
 * +-------+-------+-------+------+--------+---------+---------+
 */

#define UBX_CLASS(msg)          (msg[2])
#define UBX_ID(msg)             (msg[3])
#define UBX_CLASS_ID(msg)       (UBX_CLASS(msg) << 8 | UBX_ID(msg))

/*
 * overhead: sync (2), class (1), id (1), len (2),        chk_a/chk_b (2)
 * chksum:             class (1), id (1), len (2), data[]
 */
#define UBX_OVERHEAD            8
#define UBX_CHKSUM_ADJUST       4


/*
 * max size (UBX length) message we will receive
 *
 * If we are eavesdropping then we want to see everything
 */
#define UBX_MIN_MSG     0
#define UBX_MAX_MSG     512


typedef struct {
  uint8_t   sync1;
  uint8_t   sync2;
  uint8_t   class;
  uint8_t   id;
  uint16_t  len;
  uint8_t   data[0];
} PACKED ubx_header_t;


/*
 * UBX class identifiers
 * See page 145 of u-blox 8 / u-blox M8 Receiver description - Manual
 *     R18 (9c8fe58), 24 March 2020
 */
typedef enum {
  UBX_CLASS_NAV     = 0x01,     // Navigation Results Messages
  UBX_CLASS_RXM     = 0x02,     // Receiver Manager Messages
  UBX_CLASS_INF     = 0x04,     // Information Messages
  UBX_CLASS_ACK     = 0x05,     // Ack/Nak Messages
  UBX_CLASS_CFG     = 0x06,     // Configuration Input Messages
  UBX_CLASS_UPD     = 0x09,     // Firmware Update Messages
  UBX_CLASS_MON     = 0x0A,     // Monitoring Messages
  UBX_CLASS_AID     = 0x0B,     // AssistNow Aiding Messages
  UBX_CLASS_TIM     = 0x0D,     // Timing Messages
  UBX_CLASS_ESF     = 0x10,     // External Sensor Fusion Messages
  UBX_CLASS_MGA     = 0x13,     // Multiple GNSS Assistance Messages
  UBX_CLASS_LOG     = 0x21,     // Logging Messages
  UBX_CLASS_SEC     = 0x27,     // Security Feature Messages
  UBX_CLASS_HNR     = 0x28,     // High Rate Navigation
  UBX_CLASS_NMEA    = 0xF0,     // NMEA Strings
} ubx_classes_t;


/* UBX_CLASS_ACK (05) */
enum {
  UBX_ACK_NACK      = 0x00,
  UBX_ACK_ACK       = 0x01,
  UBX_ACK_NONE      = 0x02,     //  Not a real value
};

typedef struct {
  uint8_t   sync1;
  uint8_t   sync2;
  uint8_t   class;
  uint8_t   id;
  uint16_t  len;
  uint8_t   ackClass;
  uint8_t   ackId;
  uint8_t   chkA;
  uint8_t   chkB;
} PACKED ubx_ack_t;


/* UBX_CLASS_CFG (06) */
enum {
  UBX_CFG_PRT       = 0x00,     // Port control
  UBX_CFG_MSG       = 0x01,     // Message Poll/Configuration, msg rate.
  UBX_CFG_INF       = 0x02,     // Information, poll or information
  UBX_CFG_RST       = 0x04,     // Reset Receiver
  UBX_CFG_DAT       = 0x06,     // Set/Get User-defined Datum
  UBX_CFG_TP        = 0x07,     // Time Pulse config
  UBX_CFG_RATE      = 0x08,     // Nav/Meas Rate Settings. (port baud rates).
  UBX_CFG_CFG       = 0x09,     // Configuration control.
  UBX_CFG_FXN       = 0x0E,     // Fix Now Mode
  UBX_CFG_RXM       = 0x11,     // RXM configuration
  UBX_CFG_EKF       = 0x12,     // EKF
  UBX_CFG_ANT       = 0x13,     // Antenna Control Settings
  UBX_CFG_SBAS      = 0x16,     // SBAS configuration
  UBX_CFG_NMEA      = 0x17,     // Extended NMEA config V1
  UBX_CFG_USB       = 0x1B,     // USB Configuration
  UBX_CFG_TMODE     = 0x1D,     // Time Mode
  UBX_CFG_ODO       = 0x1E,     // Odometer
  UBX_CFG_NAVX5     = 0x23,     // Navigation Engine Expert Settings
  UBX_CFG_NAV5      = 0x24,     // Navigation Engine Settings.
  UBX_CFG_ESFGWT    = 0x29,     // ESF (external sensor fusion), gyro + wheeltick
  UBX_CFG_TP5       = 0x31,     // Time Pulse Parameters
  UBX_CFG_PM        = 0x32,     // Power Management
  UBX_CFG_RINV      = 0x34,     // Remote Inventory
  UBX_CFG_ITFM      = 0x39,     // Jamming/Interference Monitor config.
  UBX_CFG_PM2       = 0x3B,     // Extended power management configuration
  UBX_CFG_TMODE2    = 0x3D,     // Time Mode 2
  UBX_CFG_GNSS      = 0x3E,     // GNSS system configuration
  UBX_CFG_OTP       = 0x41,     // One Time Program, write efuse, permanent config
  UBX_CFG_LOGFILTER = 0x47,     // Data Logger Configuration
  UBX_CFG_TXSLOT    = 0x53,     // Tx Time Slots
  UBX_CFG_PWR       = 0x57,     // Pwr control
  UBX_CFG_HNR       = 0x5C,     // High Nav Rate
  UBX_CFG_ESRC      = 0x60,     // External SRC
  UBX_CFG_DOSC      = 0x61,     // Disciplined Oscillator
  UBX_CFG_SMGR      = 0x62,     // Sync Manager Config
  UBX_CFG_GEOFENCE  = 0x69,     // Geofencing configuration
  UBX_CFG_DGNSS     = 0x70,     // DGNSS configuration
  UBX_CFG_TMODE3    = 0x71,     // Time Mode Settings 3.  (Survey In Mode)
  UBX_CFG_PMS       = 0x86,     // Power mode setup
  UBX_CFG_VALDEL    = 0x8C,     // v27 key/val delete
  UBX_CFG_VALSET    = 0x8A,     // v27 key/val set config
  UBX_CFG_VALGET    = 0x8B,     // v27 key/val get config
  UBX_CFG_SLAS      = 0x8D,     // SLAS
  UBX_CFG_BATCH     = 0x93,     // Get/set data batching configuration.
};


/* used by UBX_CLASS_CFG/UBX_CFG_PRT */
enum {
  UBX_COM_PORT_I2C  = 0,
  UBX_COM_PORT_UART1= 1,
  UBX_COM_PORT_UART2= 2,
  UBX_COM_PORT_USB  = 3,
  UBX_COM_PORT_SPI  = 4,

  UBX_COM_TYPE_UBX  = (1 << 0),
  UBX_COM_TYPE_NMEA = (1 << 1),
  UBX_COM_TYPE_RTCM3= (1 << 5),
};


typedef struct {
  uint8_t   sync1;
  uint8_t   sync2;
  uint8_t   class;                      /* CLASS_CFG */
  uint8_t   id;                         /* CFG_CFG   */
  uint16_t  len;                        /* 13 */
  uint32_t  clearMask;
  uint32_t  saveMask;
  uint32_t  loadMask;
  uint8_t   devMask;
  uint8_t   chkA;
  uint8_t   chkB;
} PACKED ubx_cfg_cfg_t;


typedef struct {
  uint8_t   sync1;
  uint8_t   sync2;
  uint8_t   class;
  uint8_t   id;
  uint16_t  len;
  uint8_t   msgClass;
  uint8_t   msgId;
  uint8_t   rate;
  uint8_t   chkA;
  uint8_t   chkB;
} PACKED ubx_cfg_msg_t;


typedef struct {
  uint8_t   sync1;
  uint8_t   sync2;
  uint8_t   class;
  uint8_t   id;
  uint16_t  len;
  uint8_t   portId;
  uint8_t   reserved1;
  uint16_t  txReady;
  uint32_t  mode;
  uint32_t  baudRate;
  uint16_t  inProtoMask;
  uint16_t  outProtoMask;
  uint16_t  flags;
  uint8_t   reserved2[2];
  uint8_t   chkA;
  uint8_t   chkB;
} PACKED ubx_cfg_prt_t;


typedef struct {
  uint8_t   sync1;
  uint8_t   sync2;
  uint8_t   class;
  uint8_t   id;
  uint16_t  len;
  uint16_t  measRate;
  uint16_t  navRate;
  uint16_t  timeRef;
  uint8_t   chkA;
  uint8_t   chkB;
} PACKED ubx_cfg_rate_t;


enum {
  /* CFG_RST.navBbrMask */
  UBX_CFG_RST_BBR_HOT           = 0x0000,
  UBX_CFG_RST_BBR_WARM          = 0x0001,
  UBX_CFG_RST_BBR_COLD          = 0xffff,

  UBX_CFG_RST_BBR_AOP           = 0x8000,
  UBX_CFG_RST_BBR_RTC           = 0x0100,
  UBX_CFG_RST_BBR_UTC           = 0x0080,
  UBX_CFG_RST_BBR_OSC           = 0x0040,
  UBX_CFG_RST_BBR_CLKD          = 0x0020,
  UBX_CFG_RST_BBR_POS           = 0x0010,
  UBX_CFG_RST_BBR_KLOB          = 0x0008,
  UBX_CFG_RST_BBR_HEALTH        = 0x0004,
  UBX_CFG_RST_BBR_ALM           = 0x0002,
  UBX_CFG_RST_BBR_EPH           = 0x0001,
};

enum {
  /* CFG_RST.resetMode */
  UBX_CFG_RST_RESET_HW_WDOG     = 0,
  UBX_CFG_RST_RESET_SW          = 1,
  UBX_CFG_RST_RESET_SW_GNSS     = 2,
  UBX_CFG_RST_RESET_HW_SHUT     = 4,    /* hw reset after shutdown */
  UBX_CFG_RST_RESET_GNSS_STOP   = 8,    /* controlled GNSS stop    */
  UBX_CFG_RST_RESET_GNSS_START  = 9,    /* controlled GNSS start   */
};

typedef struct {
  uint8_t   sync1;
  uint8_t   sync2;
  uint8_t   class;
  uint8_t   id;
  uint16_t  len;                        /* 4 */
  uint16_t  navBbrMask;
  uint8_t   resetMode;
  uint8_t   reserved1;
  uint8_t   chkA;
  uint8_t   chkB;
} PACKED ubx_cfg_rst_t;


/* UBX_CLASS_INF (04) */
enum {
  UBX_INF_ERROR     = 0x00,     // ASCII output with error contents
  UBX_INF_WARNING   = 0x01,     // ASCII output with warning contents
  UBX_INF_NOTICE    = 0x02,     // ASCII output with informational contents
  UBX_INF_TEST      = 0x03,     // ASCII output with test contents
  UBX_INF_DEBUG     = 0x04,     // ASCII output with debug contents
};


/* UBX_CLASS_LOG (21) */
enum {
  UBX_LOG_ERASE            = 0x03,  // Erase Logged Data
  UBX_LOG_STRING           = 0x04,  // Log arbitrary string
  UBX_LOG_CREATE           = 0x07,  // Create Log File
  UBX_LOG_INFO             = 0x08,  // Poll for log information
  UBX_LOG_RETRIEVE         = 0x09,  // Request log data
  UBX_LOG_RETRIEVEPOS      = 0x0B,  // Position fix log entry
  UBX_LOG_RETRIEVESTRING   = 0x0D,  // Byte string log entry
  UBX_LOG_FINDTIME         = 0x0E,  // Find index of a log entry
  UBX_LOG_RETRIEVEPOSEXTRA = 0x0F,  // Odometer log entry
};


/* UBX_CLASS_MON (0A) */
enum {
  UBX_MON_IO        = 0x02,     // I/O Subsystem Status
  UBX_MON_VER       = 0x04,     // Software Version.
  UBX_MON_MSGPP     = 0x06,     // Message Parse and Process Status
  UBX_MON_RXBUF     = 0x07,     // Rx Buffer Status
  UBX_MON_TXBUF     = 0x08,     // Tx Buffer Status.  tx buffer size/state.
  UBX_MON_HW        = 0x09,     // Hardware Status
  UBX_MON_HW2       = 0x0B,     // Extended Hardware Status
  UBX_MON_LLC       = 0x0D,     // go get the Low Level Configuration
  UBX_MON_RXR       = 0x21,     // Receiver Status Information
  UBX_MON_PATCH     = 0x27,     // Patches
  UBX_MON_GNSS      = 0x28,     // major GNSS selections
  UBX_MON_COMMS     = 0x36,     // Comm port information
  UBX_MON_HW3       = 0x37,     // HW I/O pin information
  UBX_MON_RF        = 0x38,     // RF information
};


enum {
  UBX_MON_RXR_FLAGS_AWAKE = 0x01,
};

typedef struct {
  uint8_t   sync1;
  uint8_t   sync2;
  uint8_t   class;                      /* mon       - 0a       */
  uint8_t   id;                         /* rxr       - 21       */
  uint16_t  len;                        /* len 2 bytes, value 1 */
  uint8_t   flags;                      /* awake                */
  uint8_t   chkA;
  uint8_t   chkB;
} PACKED ubx_mon_rxr_t;




/* UBX_CLASS_NAV (01) */
enum {
  UBX_NAV_POSECEF   = 0x01,     // Position Solution in ECEF
  UBX_NAV_POSLLH    = 0x02,     // Geodetic Position Solution
  UBX_NAV_STATUS    = 0x03,     // Receiver Navigation Status
  UBX_NAV_DOP       = 0x04,     // Dilution of precision
  UBX_NAV_PVT       = 0x07,     // Position, Velocity, Time, (and more).
  UBX_NAV_ODO       = 0x09,     // Odometer Solution
  UBX_NAV_RESETODO  = 0x10,     // Reset odometer
  UBX_NAV_VELECEF   = 0x11,     // Velocity Solution in ECEF
  UBX_NAV_VELNED    = 0x12,     // Velocity Solution in NED
  UBX_NAV_HPPOSECEF = 0x13,     // ECEF (High Precision)
  UBX_NAV_HPPOSLLH  = 0x14,     // Geo (High Precision)
  UBX_NAV_TIMEGPS   = 0x20,     // GPS Time Solution
  UBX_NAV_TIMEUTC   = 0x21,     // UTC Time Solution
  UBX_NAV_CLOCK     = 0x22,     // Clock Solution
  UBX_NAV_TIMEGLO   = 0x23,     // GLO Time Solution
  UBX_NAV_TIMEBDS   = 0x24,     // BDS Time Solution
  UBX_NAV_TIMEGAL   = 0x25,     // Galileo Time Solution
  UBX_NAV_TIMELS    = 0x26,     // Leap second event information
  UBX_NAV_ORB       = 0x34,     // GNSS Orbit Database Info
  UBX_NAV_SAT       = 0x35,     // Satellite Information
  UBX_NAV_GEOFENCE  = 0x39,     // Geofencing status.
  UBX_NAV_SVIN      = 0x3B,     // Survey-in data.  Survey In status.
  UBX_NAV_RELPOSNED = 0x3C,     // Relative Positioning (NED)
  UBX_NAV_SIG       = 0x43,     // Signal Information
  UBX_NAV_AOPSTATUS = 0x60,     // Auton. Orbit Parameters Status
  UBX_NAV_EOE       = 0x61,     // End of Epoch
};


typedef struct {
  uint8_t   sync1;
  uint8_t   sync2;
  uint8_t   class;                      /* nav       - 01       */
  uint8_t   id;                         /* aopstatus - 60       */
  uint16_t  len;                        /* 16 bytes             */
  uint32_t  iTow;                       /* ms                   */
  uint8_t   aopCfg;                     /* ANAutonomous cfg     */
  uint8_t   status;                     /* 0 idle, not 0 idle   */
  uint8_t   reserved1[10];
  uint8_t   chkA;
  uint8_t   chkB;
} PACKED ubx_nav_aopstatus_t;


typedef struct {
  uint8_t   sync1;
  uint8_t   sync2;
  uint8_t   class;                      /* nav     - 01         */
  uint8_t   id;                         /* clock   - 22         */
  uint16_t  len;                        /* 20 bytes             */
  uint32_t  iTow;                       /* ms                   */
  int32_t   clkB;                       /* ns   - clock bias    */
  int32_t   clkD;                       /* ns/s - clock drift   */
  uint32_t  tAcc;                       /* ns   - time accuracy */
  uint32_t  fAcc;                       /* ps/s - freq accuracy */
  uint8_t   chkA;
  uint8_t   chkB;
} PACKED ubx_nav_clock_t;


typedef struct {
  uint8_t   sync1;
  uint8_t   sync2;
  uint8_t   class;                      /* nav     - 01         */
  uint8_t   id;                         /* dop     - 04         */
  uint16_t  len;                        /* 18 bytes             */
  uint32_t  iTow;                       /* ms                   */
  uint16_t  gDop;                       /* 0.01 - geometric dop */
  uint16_t  pDop;                       /* 0.01 - pos dop       */
  uint16_t  tDop;                       /* 0.01 - time dop      */
  uint16_t  vDop;                       /* 0.01 - vert dop      */
  uint16_t  hDop;                       /* 0.01 - horz dop      */
  uint16_t  nDop;                       /* 0.01 - northing dop  */
  uint16_t  eDop;                       /* 0.01 - easting dop   */
  uint8_t   chkA;
  uint8_t   chkB;
} PACKED ubx_nav_dop_t;

#define NAVDOP_LEN 18


typedef struct {
  uint8_t   sync1;
  uint8_t   sync2;
  uint8_t   class;                      /* nav     - 01         */
  uint8_t   id;                         /* eoe     - 61         */
  uint16_t  len;                        /* 18 bytes             */
  uint32_t  iTow;                       /* ms                   */
  uint8_t   chkA;
  uint8_t   chkB;
} PACKED ubx_nav_eoe_t;


typedef struct {
  uint8_t   gnssId;                     /* which constellation  */
  uint8_t   svId;                       /* sat Id */
  uint8_t   svFlag;                     /* info */
  uint8_t   eph;                        /* eph data */
  uint8_t   alm;                        /* alm data */
  uint8_t   otherOrb;                   /* other orbit data */
} PACKED ubx_nav_orb_elm_t;

typedef struct {
  uint8_t   sync1;
  uint8_t   sync2;
  uint8_t   class;                      /* nav     - 01         */
  uint8_t   id;                         /* orb     - 34         */
  uint16_t  len;                        /* 8 + 6 * numSv        */
  uint32_t  iTow;                       /* ms                   */
  uint8_t   version;
  uint8_t   numSvs;
  uint8_t   reserved1[2];
  ubx_nav_orb_elm_t
            orb_data[0];                /* 0 or more orb blocks */
} PACKED ubx_nav_orb_t;


typedef struct {
  uint8_t   sync1;
  uint8_t   sync2;
  uint8_t   class;                      /* nav     - 01         */
  uint8_t   id;                         /* posecef - 01         */
  uint16_t  len;                        /* 20 bytes             */
  uint32_t  iTow;                       /* ms                   */
  int32_t   ecefX;                      /* cm                   */
  int32_t   ecefY;                      /* cm                   */
  int32_t   ecefZ;                      /* cm                   */
  uint32_t  pAcc;                       /* cm, pos accuracy     */
  uint8_t   chkA;
  uint8_t   chkB;
} PACKED ubx_nav_posecef_t;


typedef struct {
  uint8_t   sync1;
  uint8_t   sync2;
  uint8_t   class;                      /* nav    - 01          */
  uint8_t   id;                         /* posllh - 02          */
  uint16_t  len;                        /* 28 bytes             */
  uint32_t  iTow;                       /* ms                   */
  int32_t   lon;                        /* deg, 1e-7            */
  int32_t   lat;                        /* deg, 1e-7            */
  int32_t   height;                     /* mm, ellipsoid        */
  int32_t   hMSL;                       /* mm, mean sea level   */
  uint32_t  hAcc;                       /* mm, horz accuracy    */
  uint32_t  vAcc;                       /* mm, vert accuracy    */
  uint8_t   chkA;
  uint8_t   chkB;
} PACKED ubx_nav_posllh_t;


typedef struct {
  uint8_t   sync1;
  uint8_t   sync2;
  uint8_t   class;                      /* nav - 01 */
  uint8_t   id;                         /* pvt - 07 */
  uint16_t  len;                        /* 92 bytes */
  uint32_t  iTow;                       /* ms */
  uint16_t  year;
  uint8_t   month;
  uint8_t   day;
  uint8_t   hour;
  uint8_t   min;
  uint8_t   sec;
  uint8_t   valid;
  uint32_t  tAcc;                       /* ns, time accur */
  int32_t   nano;                       /* ns, frac of sec, -1e9..1e9 */
  uint8_t   fixType;
  uint8_t   flags;
  uint8_t   flags2;
  uint8_t   numSV;                      /* num sats */
  int32_t   lon;                        /* deg, 1e-7 */
  int32_t   lat;                        /* deg, 1e-7 */
  int32_t   height;                     /* mm, ellipsoid */
  int32_t   hMSL;                       /* mm, mean sea level */
  uint32_t  hAcc;                       /* mm, horz accuracy  */
  uint32_t  vAcc;                       /* mm, vert accuracy  */
  int32_t   velN;                       /* mm/s, NED north velocity */
  int32_t   velE;                       /* mm/s, NED east  velocity */
  int32_t   velD;                       /* mm/s, NED down  velocity */
  int32_t   gSpeed;                     /* mm/s, ground, 2D */
  int32_t   headMot;                    /* deg, head of motion, 2D */
  uint32_t  sAcc;                       /* mm/s, speed accuracy */
  uint32_t  headAcc;                    /* deg, heading accuracy */
  uint16_t  pDop;                       /* position dop */
  uint8_t   flags3;
  uint8_t   reserved1[5];
  int32_t   headVeh;
  int16_t   magDec;                     /* magnetic declination */
  uint16_t  magAcc;
  uint8_t   chkA;
  uint8_t   chkB;
} PACKED ubx_nav_pvt_t;

#define UBX_NAV_PVT_FLAGS_GNSSFIXOK 1


typedef struct {
  uint8_t   gnssId;                     /* which constellation  */
  uint8_t   svId;                       /* sat Id */
  uint8_t   cno;                        /* dbHz */
  int8_t    elev;                       /* +/- 90, unk out of range */
  int16_t   azim;                       /* deg, azimuth, 0-360      */
  int16_t   prRes;                      /* 0.1 m - pseudorange residual */
  uint32_t  flags;
} PACKED ubx_nav_sat_elm_t;

typedef struct {
  uint8_t   sync1;
  uint8_t   sync2;
  uint8_t   class;                      /* nav     - 01         */
  uint8_t   id;                         /* sat     - 35         */
  uint16_t  len;                        /* 20 bytes             */
  uint32_t  iTow;                       /* ms                   */
  uint8_t   version;                    /* 0x01 */
  uint8_t   numSvs;
  uint8_t   reserved1[2];
} PACKED ubx_nav_sat_t;


typedef struct {
  uint8_t   sync1;
  uint8_t   sync2;
  uint8_t   class;                      /* nav     - 01         */
  uint8_t   id;                         /* status  - 03         */
  uint16_t  len;                        /* 16 bytes             */
  uint32_t  iTow;                       /* ms                   */
  uint8_t   gpsFix;                     /* fix type             */
  uint8_t   flags;                      /* nav status flags     */
  uint8_t   fixStat;                    /* fix status           */
  uint8_t   flags2;
  uint32_t  ttff;                       /* ms - time to first fix */
  uint32_t  msss;                       /* ms - ms since startup  */
  uint8_t   chkA;
  uint8_t   chkB;
} PACKED ubx_nav_status_t;


/*
 * precise GPS time in seconds:
 *   (iTow * 1e-3) + (fTow * 1e-9)
 *
 * GPS leap secs (leapS)...   GPS - UTC
 */
typedef struct {
  uint8_t   sync1;
  uint8_t   sync2;
  uint8_t   class;                      /* nav     - 01         */
  uint8_t   id;                         /* timegps - 20         */
  uint16_t  len;                        /* 16 bytes             */
  uint32_t  iTow;                       /* ms                   */
  uint32_t  fTow;                       /* ns - fractional      */
  int16_t   week;                       /* gps week             */
  int8_t    leapS;                      /* gps leap seconds     */
  uint8_t   valid;                      /* validity flags       */
  uint32_t  tAcc;                       /* ns - time accuracy   */
  uint8_t   chkA;
  uint8_t   chkB;
} PACKED ubx_nav_timegps_t;


typedef struct {
  uint8_t   sync1;
  uint8_t   sync2;
  uint8_t   class;                      /* nav     - 01         */
  uint8_t   id;                         /* timels  - 26         */
  uint16_t  len;                        /* 24 bytes             */
  uint32_t  iTow;                       /* ms                   */
  uint8_t   version;                    /* 0x00 */
  uint8_t   reserved1[3];
  uint8_t   srcOfCurrLs;                /* info src for LS val     */
  int8_t    currLs;                     /* lp secs since 19800106  */
  uint8_t   srcOfLsChange;              /* info src for future     */
  int8_t    lsChange;                   /* -1, 0, +1               */
  int32_t   timeToLsEvent;              /* s - next leap sec event */
  uint16_t  dateOfLsGpsWn;              /* gps wk next leap sec    */
  uint16_t  dateOfLsGpsDn;              /* gps day wk next lp sec  */
  uint8_t   reserved2[3];
  uint8_t   valid;
  uint8_t   chkA;
  uint8_t   chkB;
} PACKED ubx_nav_timels_t;


typedef struct {
  uint8_t   sync1;
  uint8_t   sync2;
  uint8_t   class;                      /* nav     - 01         */
  uint8_t   id;                         /* timeutc - 21         */
  uint16_t  len;                        /* 20 bytes             */
  uint32_t  iTow;                       /* ms                   */
  uint32_t  tAcc;                       /* ns - time accuracy   */
  int32_t   nano;                       /* ns - fraction of sec */
  uint16_t  year;
  uint8_t   month;
  uint8_t   day;
  uint8_t   hour;
  uint8_t   min;
  uint8_t   sec;
  uint8_t   valid;                      /* flags */
  uint8_t   chkA;
  uint8_t   chkB;
} PACKED ubx_nav_timeutc_t;


enum {
  UBX_RXM_PMREQ = 0x41,
};

enum {
  UBX_RXM_PMREQ_FLAGS_BACKUP    = 0x0002,
  UBX_RXM_PMREQ_FLAGS_FORCE     = 0x0004,

  UBX_RXM_PMREQ_WAKEUP_UART     = 0x0008,
  UBX_RXM_PMREQ_WAKEUP_EXTINT0  = 0x0020,
  UBX_RXM_PMREQ_WAKEUP_EXTINT1  = 0x0040,
  UBX_RXM_PMREQ_WAKEUP_SPICS    = 0x0080,
};

typedef struct {
  uint8_t   sync1;
  uint8_t   sync2;
  uint8_t   class;                      /* rxm     - 02         */
  uint8_t   id;                         /* pmreq   - 41         */
  uint16_t  len;                        /* 8 or 16 bytes        */
  uint8_t   version;                    /* 0 */
  uint8_t   reserved1[3];
  uint32_t  duration;                   /* how long for task, ms */
  uint32_t  flags;                      /* what tasks            */
  uint32_t  wakeupSources;
  uint8_t   chkA;
  uint8_t   chkB;
} PACKED ubx_rxm_pmreq_t;


/* UBX_CLASS_SEC (27) */
enum {
  UBX_SEC_UNIQID    = 0x03,     // Unique chip ID
};


/* UBX_CLASS_TIM (0D) */
enum {
  UBX_TIM_TP        = 0x01,     // Time Pulse Timedata
  UBX_TIM_TM2       = 0x03,     // Time mark data
  UBX_TIM_VRFY      = 0x06,     // Sourced Time Verification
};

typedef struct {
  uint8_t   sync1;
  uint8_t   sync2;
  uint8_t   class;                      /* nav     - 01         */
  uint8_t   id;                         /* timeutc - 21         */
  uint16_t  len;                        /* 20 bytes             */
  uint32_t  towMs;                      /* ms                   */
  uint32_t  towSubMs;                   /* ms - 2^-32           */
  int32_t   qErr;                       /* ps - quant err, tp   */
  uint16_t  week;                       /* week number          */
  uint8_t   flags;
  uint8_t   refInfo;                    /* time ref info        */
  uint8_t   chkA;
  uint8_t   chkB;
} PACKED ubx_tim_tp_t;


/* UBX_CLASS_UPD (09) */
enum {
  UBX_UPD_SOS          = 0x14,          /* save on shutdown     */
  UBX_UPD_SOS_CREATE   = 0,
  UBX_UPD_SOS_CLEAR    = 1,
  UBX_UPD_SOS_ACK      = 2,
  UBX_UPD_SOS_RESTORED = 3,

  UBX_UPD_SOS_ACK_NACK = 0,
  UBX_UPD_SOS_ACK_ACK  = 1,

  UBX_UPD_SOS_RSP_UNK  = 0,             /* weird                */
  UBX_UPD_SOS_RSP_FAIL = 1,             /* nope                 */
  UBX_UPD_SOS_RSP_OK   = 2,             /* restored             */
  UBX_UPD_SOS_RSP_NONE = 3,             /* no backup present    */
};

typedef struct {
  uint8_t   sync1;
  uint8_t   sync2;
  uint8_t   class;                      /* upd     - 09         */
  uint8_t   id;                         /* sos     - 14         */
  uint16_t  len;                        /* 4/8 bytes            */
  uint8_t   cmd;
  uint8_t   reserved1[3];
  uint8_t   rsp;
  uint8_t   reserved2[3];
  uint8_t   chkA;
  uint8_t   chkB;
} PACKED ubx_upd_sos_t;


#endif  /* __UBLOX_MSG_H__ */
