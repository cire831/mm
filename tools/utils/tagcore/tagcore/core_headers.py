# Copyright (c) 2020,      Eric B. Decker
# Copyright (c) 2017-2019, Daniel J. Maltbie, Eric B. Decker
# All rights reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
# See COPYING in the top level directory of this source tree.
#
# Contact: Daniel J. Maltbie <dmaltbie@daloma.org>
#          Eric B. Decker <cire831@gmail.com>

'''Core Data Type decoders and objects'''

from   __future__         import print_function

__version__ = '0.4.9.dev0'

import binascii
from   collections  import OrderedDict

from   base_objs    import *
from   ubx_headers  import obj_ubx_hdr

from   sensor_defs  import *
import sensor_defs  as     sensor

from   ubx_defs     import *
import ubx_defs     as     ubx

import tagcore.globals as  g


########################################################################
#
# Core Decoders
#
########################################################################

#
# Sensor Data decoder
#
# decodes top level of the sensor_data record and then uses the dt_sns_id
# (dtype, dt_sns_*) and sns_table to dispatch the appropriate decoder for
# the actual sensor data.  Sensor data is stored on the object pointed to
# in the sns_table entry.
#
# obj must be a obj_dt_sensor_data.
#
# this decoder does the following:
#
# o consume/process a dt_sensor_data hdr
# o dt_sns_id is embedded in the dtype field.
# o extract the appropriate vector from sns_table[dt_sns_id]
# o consume/process the sensor data using decode/obj from the vector entry

def decode_sensor(level, offset, buf, obj):
    consumed = obj.set(buf)
    dt_sns_id = obj['hdr']['type'].val
    try:
        sensor.sns_count[dt_sns_id] += 1
    except KeyError:
        sensor.sns_count[dt_sns_id] = 1
    v = sensor.sns_table.get(dt_sns_id, ('', None, None, None, None, ''))
    decoder     = v[SNS_DECODER]            # sns decoder
    decoder_obj = v[SNS_OBJECT]             # sns object
    if not decoder:
        if level >= 5 or g.debug:
            print('*** no decoder/obj defined for sns {}'.format(dt_sns_id))
        return consumed
    return consumed + decoder(level, offset, buf[consumed:], decoder_obj)


# GPS RAW decoder
#
# main gps raw decoder, decodes DT_GPS_RAW, ubx or nmea.
# dt_gps_raw_obj, decode on class/id
#
# obj must be a obj_dt_gps_raw.
#
# this decoder does the following:  (it is not a simple decode_default)
#
# o consume/process a gps_raw_hdr (dt_hdr + gps_hdr)
# o extract class/id from the ubxbin header.
#
# Note: for ubxbin packets we do not consume the ubx_hdr.  It get decoded
# so we know the Class/Id.  But the header gets offically processed as part
# of the ubx packet deocde.
#
# NMEA packet:
# o only consume up to the beginning of the SOP
#
# UbxBin packet:
# o Look up class/id in cid_table
# o consume/process the entire ubxbin packet using the appropriate decoder.

def decode_gps_raw(level, offset, buf, obj):
    consumed = obj.set(buf)
    start    = buf[consumed]   << 8 | buf[consumed+1]

    if start != UBX_SOP_SEQ:
        return consumed

    cid      = buf[consumed+2] << 8 | buf[consumed+3]
    try:
        ubx.cid_count[cid] += 1
    except KeyError:
        ubx.cid_count[cid] = 1

    v = ubx.cid_table.get(cid, (None, None, None, ''))
    decoder     = v[CID_DECODER]        # cid function
    decoder_obj = v[CID_OBJECT]         # cid object
    if not decoder:
        if level >= 5 or g.debug:
            print('*** no decoder/obj defined for class/id {:04X}'.format(cid))
        return consumed
    consumed += decoder(level, offset, buf[consumed:], decoder_obj)
    return consumed


########################################################################
#
# Core Header objects
#
########################################################################

def obj_rtctime():
    return aggie(OrderedDict([
        ('sub_sec', atom(('<H', '{}'))),
        ('sec',     atom(('<B', '{}'))),
        ('min',     atom(('<B', '{}'))),
        ('hr',      atom(('<B', '{}'))),
        ('dow',     atom(('<B', '{}'))),
        ('day',     atom(('<B', '{}'))),
        ('mon',     atom(('<B', '{}'))),
        ('year',    atom(('<H', '{}'))),
    ]))


def obj_dt_hdr():
    return aggie(OrderedDict([
        ('len',     atom(('<H', '{}'))),
        ('type',    atom(('B',  '{}'))),
        ('hdr_crc8',atom(('B',  '{}'))),
        ('recnum',  atom(('<I', '{}'))),
        ('rt',      obj_rtctime()),
        ('recsum',  atom(('<H', '0x{:04x}'))),
    ]))


def obj_dt_reboot():
    return aggie(OrderedDict([
        ('hdr',       obj_dt_hdr()),
        ('core_rev',  atom(('<H', '0x{:04x}'))),
        ('core_minor',atom(('<H', '0x{:04x}'))),
        ('base',      atom(('<I', '0x{:08x}'))),
        ('node_id',   atom(('6s', '{}', binascii.hexlify))),
        ('pad',       atom(('<H', '0x{:04x}'))),
        ('owcb',      obj_owcb())
    ]))


# RTC SRC values
rtc_src_names = {
    0:  'BOOT',
    1:  'FORCED',
    2:  'DBLK',
    3:  'NET',
    4:  'GPS0',
    5:  'GPS',
}

def rtc_src_name(rtc_src):
    return rtc_src_names.get(rtc_src, 'rtcsrc/' + str(rtc_src))


#
# reboot is followed by the ow_control_block
# We want to decode that as well.  native order, little endian.
# see OverWatch/overwatch.h.
#
def obj_owcb():
    return aggie(OrderedDict([
        ('ow_sig',          atom(('<I', '0x{:08x}'))),
        ('rpt',             atom(('<I', '0x{:08x}'))),
        ('boot_time',       obj_rtctime()),
        ('prev_boot',       obj_rtctime()),
        ('reset_status',    atom(('<I', '0x{:08x}'))),
        ('reset_others',    atom(('<I', '0x{:08x}'))),
        ('from_base',       atom(('<I', '0x{:08x}'))),
        ('panic_count',     atom(('<I', '{}'))),
        ('panics_gold',     atom(('<I', '{}'))),

        ('fault_gold',      atom(('<I', '0x{:08x}'))),
        ('fault_nib',       atom(('<I', '0x{:08x}'))),
        ('subsys_disable',  atom(('<I', '0x{:08x}'))),
        ('protection_status', atom(('<I', '0x{:08x}'))),

        ('ow_sig_b',        atom(('<I', '0x{:08x}'))),

        ('ow_req',          atom(('<B', '{}'))),
        ('reboot_reason',   atom(('<B', '{}'))),

        ('ow_boot_mode',    atom(('<B', '{}'))),
        ('owt_action',      atom(('<B', '{}'))),

        ('reboot_count',    atom(('<I', '{}'))),
        ('strange',         atom(('<I', '{}'))),
        ('strange_loc',     atom(('<I', '0x{:04x}'))),
        ('chk_fails',       atom(('<I', '{}'))),
        ('logging_flags',   atom(('<I', '{}'))),

        ('pi_panic_idx',    atom(('<H', '{}'))),
        ('pi_pcode',        atom(('<B', '{}'))),
        ('pi_where',        atom(('<B', '{}'))),
        ('pi_arg0',         atom(('<I', '{}'))),
        ('pi_arg1',         atom(('<I', '{}'))),
        ('pi_arg2',         atom(('<I', '{}'))),
        ('pi_arg3',         atom(('<I', '{}'))),

        ('rtc_src',         atom(('B',  '{}'))),
        ('ow_debug',        atom(('B',  '0x{:02x}'))),
        ('pad1',            atom(('<H', '{}'))),

        ('ow_sig_c',        atom(('<I', '0x{:08x}')))
    ]))


def obj_dt_version():
    return aggie(OrderedDict([
        ('hdr',       obj_dt_hdr()),
        ('base',      atom(('<I', '0x{:08x}'))),
        ('image_info', obj_image_info())
    ]))


def obj_hw_version():
    return aggie(OrderedDict([
        ('rev',       atom(('<B', '{}'))),
        ('model',     atom(('<B', '{}'))),
    ]))


def obj_image_version():
    return aggie(OrderedDict([
        ('build',     atom(('<H', '{}'))),
        ('minor',     atom(('<B', '{}'))),
        ('major',     atom(('<B', '{}'))),
    ]))


def obj_image_info():
    return aggie(OrderedDict([
        ('basic',     obj_image_basic()),
        ('plus',      obj_image_plus()),
    ]))


def obj_image_basic():
    return aggie(OrderedDict([
        ('ii_sig',    atom(('<I', '0x{:08x}'))),
        ('im_start',  atom(('<I', '0x{:08x}'))),
        ('im_len',    atom(('<I', '0x{:08x}'))),
        ('ver_id',    obj_image_version()),
        ('im_chk',    atom(('<I', '0x{:08x}'))),
        ('hw_ver',    obj_hw_version()),
        ('im_plus_len', atom(('<H', '{}'))),
        ('reserved',  atom(('8s', '{}', binascii.hexlify))),
    ]))


# obj_image_plus is a container that holds obj_image_plus_tlvs.
#
# The maximum size of obj_image_plus is static and determined at compile
# time of the main tag image.  see IMAGE_INFO_PLUS_SIZE in image_info.h.
# The size of the plus area is also stored in basic[plus_len].
#
# obj_image_plus_tlvs are built dynamically as tlvs are processed, once
# we know the size of the tlv's data we can build the tlv and add it
# to the block.
#
# We effectively create the following
#
#    def obj_image_plus_tlv():
#        return aggie(OrderedDict([
#            ('tlv_type',  atom(('B', '{}'))),
#            ('tlv_len',   atom(('B', '{}'))),
#            ('tlv_value', atom(('Ns', '{}'))),
#        ]))
#
# where 'N' is the size of the string.
#
# This is handled by the tlv_aggie class defined in base_objs.py
#
# The TLV_END tlv is used to terminate the sequence of TLVs.
# It has a length of 2 bytes, tlv_type: 0 and tlv_len: 0.
#

def obj_image_plus():
    return tlv_block_aggie(aggie(OrderedDict([
    ])))


# Constructed manually in tlv_block_aggie and tlv_aggie (base_objs.py)
#
#def obj_image_plus_tlv():
#    return tlv_aggie(aggie(OrderedDict([
#        ('tlv_type',  atom(('<B', '{}'))),
#        ('tlv_len',   atom(('<B', '{}'))),
#        ('tlv_value', atom(('<Ns', '{}'))),
#    ])))


def obj_dt_sync():
    return aggie(OrderedDict([
        ('hdr',       obj_dt_hdr()),
        ('prev_sync', atom(('<I', '0x{:x}'))),
        ('majik',     atom(('<I', '0x{:08x}'))),
    ]))


img_mgr_events = {
    0: 'none',
    1: 'alloc',
    2: 'abort',
    3: 'finish',
    4: 'delete',
    5: 'active',
    6: 'backup',
    7: 'eject',
}

def img_mgr_event_name(im_ev):
    iv_name = img_mgr_events.get(im_ev, 0)
    if iv_name == 0:
        iv_name = 'imgmgr_ev_' + str(im_ev)
    return iv_name


def obj_dt_event():
    return aggie(OrderedDict([
        ('hdr',   obj_dt_hdr()),
        ('event', atom(('<H', '{}'))),
        ('pcode', atom(('<B', '{}'))),
        ('w',     atom(('<B', '{}'))),
        ('arg0',  atom(('<I', '0x{:04x}'))),
        ('arg1',  atom(('<I', '0x{:04x}'))),
        ('arg2',  atom(('<I', '0x{:04x}'))),
        ('arg3',  atom(('<I', '0x{:04x}'))),
    ]))


#
# not implemented yet.
#
def obj_dt_debug():
    return aggie(OrderedDict([
        ('hdr',   obj_dt_hdr()),
    ]))


#
# dt, native, little endian
# used by DT_GPS_VERSION and DT_GPS_RAW (gps_raw)
#
def obj_dt_gps_hdr():
    return aggie(OrderedDict([
        ('hdr',     obj_dt_hdr()),
        ('mark',    atom(('<I', '0x{:04x}'))),
        ('chip',    atom(('B',  '0x{:02x}'))),
        ('dir',     atom(('B',  '{}'))),
        ('pad',     atom(('<H', '{}'))),
    ]))


# deprecated
def obj_dt_gps_ver():
    return aggie(OrderedDict([
        ('gps_hdr',    obj_dt_gps_hdr()),
#        ('sirf_swver', obj_sirf_swver()),
    ]))


def obj_dt_gps_time():
    return aggie(OrderedDict([
        ('gps_hdr',   obj_dt_gps_hdr()),
        ('capdelta',  atom(('<i', '{}'))),
        ('itow',      atom(('<I', '{}'))),
        ('tacc',      atom(('<I', '{}'))),
        ('utc_ms',    atom(('<H', '{}'))),
        ('utc_year',  atom(('<H', '{}'))),
        ('utc_month', atom(('<B', '{}'))),
        ('utc_day',   atom(('<B', '{}'))),
        ('utc_hour',  atom(('<B', '{}'))),
        ('utc_min',   atom(('<B', '{}'))),
        ('utc_sec',   atom(('<B', '{}'))),
        ('nsats',     atom(('<B', '{}'))),
    ]))


def obj_dt_gps_geo():
    return aggie(OrderedDict([
        ('gps_hdr',   obj_dt_gps_hdr()),
        ('capdelta',  atom(('<i', '{}'))),
        ('itow',      atom(('<I', '{}'))),
        ('lat',       atom(('<i', '{}'))),
        ('lon',       atom(('<i', '{}'))),
        ('alt_ell',   atom(('<i', '{}'))),
        ('alt_msl',   atom(('<i', '{}'))),
        ('hacc',      atom(('<I', '{}'))),
        ('vacc',      atom(('<I', '{}'))),
        ('pdop',      atom(('<H', '{}'))),
        ('fixtype',   atom(('<B', '{}'))),
        ('flags',     atom(('<B', '0x{:02x}'))),
        ('nsats',     atom(('<B', '{}'))),
    ]))


def obj_dt_gps_xyz():
    return aggie(OrderedDict([
        ('gps_hdr',   obj_dt_gps_hdr()),
        ('capdelta',  atom(('<i', '{}'))),
        ('x',         atom(('<i', '{}'))),
        ('y',         atom(('<i', '{}'))),
        ('z',         atom(('<i', '{}'))),
        ('sat_mask',  atom(('<I', '0x{:08x}'))),
        ('tow100',    atom(('<I', '{}'))),
        ('week_x',    atom(('<H', '{}'))),
        ('m1',        atom(('<B', '0x{:02x}'))),
        ('hdop5',     atom(('<B', '{}'))),
        ('nsats',     atom(('<B', '{}'))),
    ]))


def obj_dt_gps_clk():
    return aggie(OrderedDict([
        ('gps_hdr',   obj_dt_gps_hdr()),
        ('capdelta',  atom(('<i', '{}'))),
        ('tow100',    atom(('<I', '{}'))),
        ('drift',     atom(('<I', '{}'))),
        ('bias',      atom(('<I', '{}'))),
        ('week_x',    atom(('<H', '{}'))),
        ('nsats',     atom(('B', '{}'))),
    ]))


def obj_dt_gps_trk_element():
    return aggie(OrderedDict([
        ('az10',      atom(('<H', '{}'))),
        ('el10',      atom(('<H', '{}'))),
        ('state',     atom(('<H', '{}'))),
        ('svid',      atom(('<H', '{}'))),
        ('cno0',      atom(('B',  '{}'))),
        ('cno1',      atom(('B',  '{}'))),
        ('cno2',      atom(('B',  '{}'))),
        ('cno3',      atom(('B',  '{}'))),
        ('cno4',      atom(('B',  '{}'))),
        ('cno5',      atom(('B',  '{}'))),
        ('cno6',      atom(('B',  '{}'))),
        ('cno7',      atom(('B',  '{}'))),
        ('cno8',      atom(('B',  '{}'))),
        ('cno9',      atom(('B',  '{}'))),
    ]))


def obj_dt_gps_trk():
    return aggie(OrderedDict([
        ('gps_hdr',   obj_dt_gps_hdr()),
        ('capdelta',  atom(('<i', '{}'))),
        ('tow100',    atom(('<I', '{}'))),
        ('week',      atom(('<H', '{}'))),
        ('chans',     atom(('<H', '{}'))),
    ]))


####
#
# Sensor Data
#
# Record header followed by sensor data.
# dt_sns_id determines the format of the sensor data.
#
def obj_dt_sns_data():
    return aggie(OrderedDict([
        ('hdr',         obj_dt_hdr()),
        ('sched_delta', atom(('<I', '{}'))),
    ]))


def obj_dt_test():
    return aggie(OrderedDict([
        ('hdr',   obj_dt_hdr()),
    ]))

####
#
# NOTES
#
# A note record consists of a dt_note_t header (same as dt_header_t, a
# simple header) followed by n bytes of note.  typically a printable
# ascii string (yeah, localization is an issue, but not now).
#
def obj_dt_note():
    return aggie(OrderedDict([
        ('hdr',   obj_dt_hdr()),
    ]))

def obj_dt_config():
    return aggie(OrderedDict([
        ('hdr',   obj_dt_hdr()),
    ]))


####
#
# GPS PROTO STATS
#

def obj_dt_gps_proto_stats():
    return aggie(OrderedDict([
        ('hdr',                 obj_dt_hdr()),
        ('stats',               obj_gps_proto_stats()),
    ]))

def obj_gps_proto_stats():
    return aggie(OrderedDict([
        ('starts',              atom(('<I', '{}'))),
        ('complete',            atom(('<I', '{}'))),
        ('ignored',             atom(('<I', '{}'))),
        ('resets',              atom(('<H', '{}'))),
        ('too_small',           atom(('<H', '{}'))),
        ('too_big',             atom(('<H', '{}'))),
        ('chksum_fail',         atom(('<H', '{}'))),
        ('rx_timeouts',         atom(('<H', '{}'))),
        ('rx_errors',           atom(('<H', '{}'))),
        ('rx_framing',          atom(('<H', '{}'))),
        ('rx_overrun',          atom(('<H', '{}'))),
        ('rx_parity',           atom(('<H', '{}'))),
        ('proto_start_fail',    atom(('<H', '{}'))),
        ('proto_end_fail',      atom(('<H', '{}'))),
    ]))


# DT_GPS_RAW, dt, native, little endian
#  ubx data little endian.
def obj_dt_gps_raw():
    return aggie(OrderedDict([
        ('gps_hdr', obj_dt_gps_hdr()),
    ]))

def obj_dt_tagnet():
    return aggie(OrderedDict([
        ('hdr',   obj_dt_hdr()),
    ]))


# extract and decode gps nav track messages.
#
# base object is an obj_dt_gps_trk which includes 'chans' which
# tells us how many channels are following.  Each chan is made up of
# a obj_dt_gps_trk_element (gps_navtrk_chan).
#
# each instance of gps_navtrk_chan is held as part of a dictionary
# key'd off the numeric chan number, 0-11 (12 channels is typical),
# and attached to the main obj_dt_gps_trk object (obj).
#

gps_navtrk_chan = obj_dt_gps_trk_element()

def decode_gps_trk(level, offset, buf, obj):
    # delete any previous navtrk channel data
    for k in obj.iterkeys():
        if isinstance(k,int):
            del obj[k]

    consumed = obj.set(buf)
    chans    = obj['chans'].val

    # grab each channels cnos and other data
    for n in range(chans):
        d = {}                      # get a new dict
        consumed += gps_navtrk_chan.set(buf[consumed:])
        for k, v in gps_navtrk_chan.items():
            d[k] = v.val
        avg  = d['cno0'] + d['cno1'] + d['cno2']
        avg += d['cno3'] + d['cno4'] + d['cno5']
        avg += d['cno6'] + d['cno7'] + d['cno8']
        avg += d['cno9']
        avg /= float(10)
        d['cno_avg'] = avg
        obj[n] = d
    return consumed
