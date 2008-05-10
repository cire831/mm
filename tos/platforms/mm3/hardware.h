/**
 *
 * Copyright 2008 (c) Eric B. Decker
 * All rights reserved.
 *
 * @author Eric B. Decker
 */

#ifndef _H_hardware_h
#define _H_hardware_h

#include "msp430hardware.h"
#include "mm3PortRegs.h"

/*
 * Port definitions:
 *
 * what do these damn codes mean?  (<dir><usage><default val>: Is0 <input><spi><0, zero>)
 * another nomenclature used is <value><function><direction>, 0pO (0 (zero), port, Output),
 *    xpI (don't care, port, Input), mI (module input).
 *
 * Need:
 *	red, green, yellow leds
 *	cc2420: csn, vref, reset, fifop, sfd, gio0, fifo, gio1, cca
 *	    cc: fifop, fifo, sfd, vren, rstn (these aren't assigned, where to put them)
 *	  (cc2420 power down?)
 *
 *      gps is wired to a mux and then to uart1.  And power up/down
 *	cc2420 (spi1), sd (spi1), gps, and serial direct connect (uart1) on same usart.
 *
 * port 1.0	O	d_mux_a0		port 4.0	O	gain_mux_a0
 *       .1	O	d_mux_a1		      .1	O	gain_mux_a1
 *       .2	O	mag_degauss_1		      .2	O	vdiff_off
 *       .3    mI(0pO)	gps_rx  		      .3	O	vref_off
 *       .4	O	mag_deguass_2		      .4	O	solar_chg_on
 *       .5	O	press_res_off		      .5	O	extchg_battchk
 *       .6	O	salinity_off		      .6	O	gps_off
 *       .7	O	press_off		      .7	O	led_g (rf232_pwr off)
 *
 * port 2.0	O	U8_inhibit		port 5.0	O	sd_pwr_off (1 = off)
 *       .1	O	accel_wake		      .1	0sO	sd_di (simo1, spi1)  (0pO, sd off)
 *       .2	O	salinity_polarity	      .2	0sI	sd_do (somi1, spi1)  (0pO, sd off)
 *       .3	O	u12_inhibit		      .3	0sO	sd_clk (uclk1, spi1) (0pO, sd off)
 *       .4	O	s_mux_a0		      .4	O	sd_csn (cs low true) (0pO, sd off)
 *       .5	O	s_mux_a1		      .5	O	rf_beeper_off
 *       .6	O	adc_cnv			      .6	O	ser_sel_a0
 *       .7	I	adc_da0			      .7	O	ser_sel_a1  (cc2420_reset)
 *
 * port 3.0	O	cc2420_csn		port 6.0	O	cc2420_fifop
 *       .1	O	s_mux_a2		      .1	O	cc2420_sfd
 *       .2	0sI	adc_somi (spi0)		      .2	I	cc2420_fifo
 *       .3	0sO	adc_clk (uclk0, spi0)	      .3	O	telltale (cc2420_cca)
 *       .4	OpO	tmp_on			      .4	O	speed_off
 *       .5	1pO	adc_sdi (not part of spi)     .5	O	mag_xy_off
 *			  (mode control in, adc)
 *       .6	1uO	ser_txd (uart1)		      .6	O	led_y
 *       .7	0uI	ser_rxd (uart1)		      .7	O	mag_z_off
 */

/*
 * MUX Control
 *
 * Dmux controls which differential sensor is connected to
 * the differential amps.  The inhibits are involved.
 * (Dmux is P1.0-1)
 *
 * Gmux controls the gain the differential amps use.
 * (Gmux is P4.0-1)
 *
 * Smux controls which single ended sensor is selected.
 * also can select the output of the differential system.
 * (Smux is P2.4-5 and P3.1)
 *
 *
 * USART Pins
 *
 * usart 0 is dedicated to the ADC in SPI mode.  3.2-3, 5-6.
 * 2.7 is an input coming from the ADC that indicates the conversion
 * is complete.
 *
 * usart 1 is shared between the sd (spi), radio (spi), gps, and direct connect
 * (gps and direct connect use the uart).  The radio is mutually exclusive with
 * direct connect.
 *
 * uart1 is used to communicate with the direct connect cradle or with the gps.
 * The gps also connects to p1.3 which allows an interrupt to be generated when
 * the gps starts to send data.  This pin can also be used in conjunction with
 * Timer A to implement a s/w uart.  Which port is connected is determined by
 * the settings on a h/w multiplexor.
 */

TOSH_ASSIGN_PIN(GSP_RXx, 1, 3);

#define ADC_CNV mmP2out.adc_cnv

TOSH_ASSIGN_PIN(ADCxCNV, 2, 6);

#define ADC_SDO mmP3out.adc_sdo
#define ADC_CLK mmP3out.adc_clk
#define ADC_SDI mmP3out.adc_sdi

TOSH_ASSIGN_PIN(ADCxSDO, 3, 2);
TOSH_ASSIGN_PIN(ADCxCLK, 3, 3);
TOSH_ASSIGN_PIN(ADCxSDI, 3, 5);

TOSH_ASSIGN_PIN(SDxSDI, 5, 1);
TOSH_ASSIGN_PIN(SDxSDO, 5, 2);
TOSH_ASSIGN_PIN(SDxCLK, 5, 3);
TOSH_ASSIGN_PIN(SDxCSN, 5, 4);

  enum {
    SER_SEL_CRADLE =	0,
    SER_SEL_GPS    =	1,	/* temp so we can see it via the uart */
//    SER_SEL_RF232  =	2,	/* shouldnt be used */
    SER_SEL_NONE   =	3,
  };

#define TELL mmP6out.tell
TOSH_ASSIGN_PIN(TELLx, 6, 3);

// LEDs
TOSH_ASSIGN_PIN(GREEN_LED, 6, 4);
TOSH_ASSIGN_PIN(YELLOW_LED, 6, 6);


#ifdef notdef
// CC2420 RADIO #defines
TOSH_ASSIGN_PIN(RADIO_CSN, 4, 2);
TOSH_ASSIGN_PIN(RADIO_VREF, 4, 5);
TOSH_ASSIGN_PIN(RADIO_RESET, 4, 6);
TOSH_ASSIGN_PIN(RADIO_FIFOP, 1, 0);
TOSH_ASSIGN_PIN(RADIO_SFD, 4, 1);
TOSH_ASSIGN_PIN(RADIO_GIO0, 1, 3);
TOSH_ASSIGN_PIN(RADIO_FIFO, 1, 3);
TOSH_ASSIGN_PIN(RADIO_GIO1, 1, 4);
TOSH_ASSIGN_PIN(RADIO_CCA, 1, 4);

TOSH_ASSIGN_PIN(CC_FIFOP, 1, 0);
TOSH_ASSIGN_PIN(CC_FIFO, 1, 3);
TOSH_ASSIGN_PIN(CC_SFD, 4, 1);
TOSH_ASSIGN_PIN(CC_VREN, 4, 5);
TOSH_ASSIGN_PIN(CC_RSTN, 4, 6);
#endif


// need to undef atomic inside header files or nesC ignores the directive
#undef atomic

/*
 * Notes on power for sensors and peripherals.
 *
 * Set initial state of ports to something reasonable.  Although we
 * assume that we have just been reset, we explicitly make sure
 * that the mcu pins are in a reasonable state.
 *
 * After Power-Up Clear, the following state exists on the digitial
 * ports.
 *
 * PxIN		ro	-
 * PxOUT	rw	unchanged
 * PxDIR	rw	reset to 0 (pin input)
 * PxIFG	rw	reset to 0 (no pending interrupts)
 * PxIES	rw	unchanged
 * PxIE		rw	reset to 0 (no port interrupts)
 * PxSEL	rw	reset to 0 (port function)
 *
 * SPI0 enabled, UART1 disabled, SPI1 disabled.
 *
 * P3.(2,3)   -> SPI0  (USART0), enabled
 * P3.(6,7)   -> UART1 (USART1), disabled
 * P5.(1,2,3) -> SPI1  (USART1), disabled
 *
 * When a function is disabled, its corresponding pins are
 * switched back to port function, the module disabled, the pin
 * is set to input, the pin's POUT is set to 0.  This avoids
 * powering the chip when power is off through the input clamps.
 * (Need to check whether this is valid for chip outputs as well,
 * currently the code sets these pins the same as chip inputs).
 *
 * init_ports also makes sure that all modules are powered off.
 * Any pins connected to power fets are set to power down the
 * circuit.  Any pins connected to i/o pins on a powered down
 * chip will be set to 0pI (set to 0, port func, dir input).
 *
 * The ADC is connected to SPI0 and is always on (it goes into
 * low power mode itself).  Pins connected to SPI0 are assigned
 * at power up.
 *
 * Direction: 0 for input, 1 for output.
 * Selects:   0 for port, 1 for module function.
 */


/*
 * d_mux = 0 (inhibits will be high, u8/u12_inhibit)
 * all pwr bits high (off), gps_rx_out 0 (gps off), degauss = 0
 */
#define P1_BASE_DIR	0xff
#define P1_BASE_VAL	0xe0

/*
 * s_mux = 0, accel sleeping, u8/12 inhibit
 * adc_cnv=0pO, gps_rx input.
 */
#define P2_BASE_DIR	0x7f
#define P2_BASE_VAL	0x09

/*
 * rx in, tx out/1, adc_sdi high (sets mode), temp off, s_mux 0
 * ser_txd is set to 1 (mark).
 *
 * ADC_SDO and ADC_CLK are assigned to SPI0
 */
#define P3_BASE_DIR	0x7b

/* gps is being moved to its own pin.  meaning a s/w uart
   driven initially by interrupt (start bit interrupts us)
   and then timed with t2 timers for the sample rate.
*/
#define P3_BASE_VAL	0x60
#define P3_BASE_SEL	0x0c

/* gps off, no batt chk, no solar, vref/vdiff off, g_mux 0 */
#define P4_BASE_DIR	0xff
#define P4_BASE_VAL	0xcc

/*
 * ser_sel 0 (direct connect), beeper off, sd bits 0pO, sd pwr off 1pO
 * (when powered off we dont want to power the chip via any of its other
 * pins).  So set any pins connected to the SD to output 0.
 */
#define P5_BASE_DIR	0xff
#define P5_BASE_VAL	0x21

/* mag pwr off */
#define P6_BASE_DIR	0xff
#define P6_BASE_VAL	0xf0


inline void uwait(uint16_t u) {
  uint16_t t0 = TAR;
  while((TAR - t0) <= u);
}


void TOSH_MM3_INITIAL_PIN_STATE(void) {
  atomic {
    SVSCTL = 0;			/* for now, disable SVS */
    U0CTL = SWRST;		/* hold USART0 in reset */
    U1CTL = SWRST;		/* and  USART1 as well  */
    ME1 = 0;
    ME2 = 0;

    P1SEL = 0;			/* all ports port function */
    P1DIR = P1_BASE_DIR;
    P1OUT = P1_BASE_VAL;
    P1IES = 0;
    P1IFG = 0;

    P2SEL = 0;
    P2DIR = P2_BASE_DIR;
    P2OUT = P2_BASE_VAL;
    P2IES = 0;
    P2IFG = 0;

    P3SEL = P3_BASE_SEL;
    P3DIR = P3_BASE_DIR;
    P3OUT = P3_BASE_VAL;

    P4SEL = 0;
    P4DIR = P4_BASE_DIR;
    P4OUT = P4_BASE_VAL;

    P5SEL = 0;
    P5DIR = P5_BASE_DIR;
    P5OUT = P5_BASE_VAL;

    P6SEL = 0;
    P6DIR = P6_BASE_DIR;
    P6OUT = P6_BASE_VAL;
  }
}

#endif // _H_hardware_h
