# Copyright (c) 2018 Eric B. Decker
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
# Contact: Eric B. Decker <cire831@gmail.com>

'''panic objects from panic.h'''

import binascii
from   tagcore.base_objs import *

panic_dir_obj = aggie(OrderedDict([
    ('panic_dir_id',        atom(('4s', '{}'))),
    ('panic_dir_sig',       atom(('<I', '{:x}'))),
    ('panic_dir_sector',    atom(('<I', '{}'))),
    ('panic_high_sector',   atom(('<I', '{}'))),
    ('panic_block_index',   atom(('<I', '{}'))),
    ('panic_block_index_max',atom(('<I', '{}'))),
    ('panic_block_size',    atom(('<I', '{}'))),
    ('panic_dir_checksum',  atom(('<I', '{}')))
]))


panic_info_obj = aggie(OrderedDict([
    ('pi_sig',           atom(('<I', '{:04x}'))),
    ('boot_count',       atom(('<I', '{:2}'))),
    # kludge for now, need to fix panic_info
    ('rt',               atom(('12s', '{}', binascii.hexlify))),
    ('fail_count',       atom(('<I', '{:02}'))),
    ('subsys',           atom(('<B', '{:02}'))),
    ('where',            atom(('<B', '{:02}'))),
    ('pad',              atom(('<H', '{}'))),
    ('arg_0',            atom(('<I', '{:08x}'))),
    ('arg_1',            atom(('<I', '{:08x}'))),
    ('arg_2',            atom(('<I', '{:08x}'))),
    ('arg_3',            atom(('<I', '{:08x}')))
]))


image_ver_obj = aggie(OrderedDict([
    ('build',          atom(('<H', '{}'))),
    ('minor',          atom(('<B', '{}'))),
    ('major',          atom(('<B', '{}')))
]))


hw_ver_obj = aggie(OrderedDict([
    ('hw_rev',         atom(('<B', '{}'))),
    ('hw_model',       atom(('<B', '{}')))
]))


image_info_obj = aggie(OrderedDict([
    ('ii_sig',         atom(('<I', '{:x}'))),
    ('image_start',    atom(('<I', '{}'))),
    ('image_length',   atom(('<I', '{}'))),
    ('vector_chk',     atom(('<I', '{}'))),
    ('image_chk',      atom(('<I', '{}'))),
    ('ver_id',         image_ver_obj),
    ('descriptor0',    atom(('<44B', '{}'))),
    ('descriptor1',    atom(('<44B', '{}'))),
    ('stamp_date',     atom(('<30B', '{}'))),
    ('hw_ver',         hw_ver_obj)
]))


add_info_obj = aggie(OrderedDict([
    ('ai_sig',           atom(('<I', '{}'))),
    ('ram_sector',       atom(('<I', '{}'))),
    ('ram_size',         atom(('<I', '{}'))),
    ('io_sector',        atom(('<I', '{}'))),
    ('fcrumb_sector',    atom(('<I', '{}'))),
]))


crash_info_obj = aggie(OrderedDict([
    ('ci_sig',    atom(('<I', '{}'))),
    ('axLR',      atom(('<I', '{}'))),
    ('MSP',       atom(('<I', '{}'))),
    ('PSP',       atom(('<I', '{}'))),
    ('primask',   atom(('<I', '{}'))),
    ('basepri',   atom(('<I', '{}'))),
    ('faultmask', atom(('<I', '{}'))),
    ('control',   atom(('<I', '{}'))),
    ('cc_sig',    atom(('<I', '{}'))),
    ('flags',     atom(('<I', '{}'))),
    ('bxReg_0',    atom(('<I', '{}'))),
    ('bxReg_1',    atom(('<I', '{}'))),
    ('bxReg_2',    atom(('<I', '{}'))),
    ('bxReg_3',    atom(('<I', '{}'))),
    ('bxReg_4',    atom(('<I', '{}'))),
    ('bxReg_5',    atom(('<I', '{}'))),
    ('bxReg_6',    atom(('<I', '{}'))),
    ('bxReg_7',    atom(('<I', '{}'))),
    ('bxReg_8',    atom(('<I', '{}'))),
    ('bxReg_9',    atom(('<I', '{}'))),
    ('bxReg_10',    atom(('<I', '{}'))),
    ('bxReg_11',    atom(('<I', '{}'))),
    ('bxReg_12',    atom(('<I', '{}'))),
    ('bxSP',      atom(('<I', '{}'))),
    ('bxLR',      atom(('<I', '{}'))),
    ('bxPC',      atom(('<I', '{}'))),
    ('bxPSR',     atom(('<I', '{}'))),
    ('axPSR',     atom(('<I', '{}'))),
    ('fpRegs',    atom(('<32I', '{}'))),
    ('fpscr',     atom(('<I', '{}')))
]))


ram_header_obj = aggie(OrderedDict([
    ('start',     atom(('<I', '{}'))),
    ('end',       atom(('<I', '{}')))
]))


panic_block_0_obj = aggie(OrderedDict([
    ('panic_info', panic_info_obj),
    ('image_info', image_info_obj),
    ('add_info',   add_info_obj),
    ('padding',    atom(('13I', '{}'))),
    ('crash_info', crash_info_obj),
    ('ram_header', ram_header_obj)
]))
