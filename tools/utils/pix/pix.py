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

'''PIX: Panic Inspector/eXtractor

display and extract panic blocks from a composite PANIC file.
Extracted panics can be fed to CrashDump for analysis.

usage: pix [-h] [-V]
           [-o <output>]
           [--output <output>]
           panic_vile

Args:

optional arguments:
  -h              show this help message and exit
  -V              show program's version number and exit

  -o <output>     enables extraction and sets output file.
                  (args.output, file)

positional argument:
  panic_file      input file, composite PANIC file.
'''

from   __future__               import print_function

VERSION = '0.0.1.dev2'

import sys
import struct
import argparse
from   collections              import OrderedDict
from   pprint                   import PrettyPrinter

from   tagcore                  import *
from   tagcore.panic_headers    import *

ppPP = PrettyPrinter(indent = 4)
pp   = ppPP.pprint

def panic_args():
    parser = argparse.ArgumentParser(
        description='Panic Inspector/eXtractor (PIX)')

    parser.add_argument('-V', '--version',
        action  = 'version',
        version = '%(prog)s ' + VERSION)

    parser.add_argument('panic_file',
                        type = argparse.FileType('rb'),
                        help = 'panic file')

    parser.add_argument('-o', '--output',
                        type = argparse.FileType('wb'),
                        help = 'dest filename for extraction')

    return parser.parse_args()


# Global scope
args    = panic_args()
inFile  = args.panic_file
outFile = args.output

pblk = 'ffffff'
PLIST = []
BLK = 0
pi_sig_hex  = '0x44665041'
dir_sig_hex = '0xddddb00b'

# Read in Directory block for verification
raw = inFile.read()
consumed = panic_dir_obj.set(raw)
panic_dir_sector = (panic_dir_obj['panic_dir_sector'].val)
print("panic_dir_sector: %d" % (panic_dir_sector))


panic_high_sector = (panic_dir_obj['panic_high_sector'].val)
panic_block_size  = (panic_dir_obj['panic_block_size'].val)
dir_sig           = (panic_dir_obj['panic_dir_sig'].val)

if (hex(dir_sig) != dir_sig_hex):
    print('dir_sig_mismatch')
    sys.exit(0)

# Checks each panic block for verification
def panic_verify(bptr,list):
    consumed = panic_block_0_obj.set(bptr)
    panic_info = panic_block_0_obj['panic_info']
    pi_sig = (panic_info['pi_sig'].val)
    if (hex(pi_sig) == pi_sig_hex):
        PLIST.append(("Panic Block %d: " % (BLK)) + str(panic_info))
        return list
    else:
        return False

# Searches panic file for panic dumps
def panic_search(plist):
    global BLK

    offset = 512
    while True:
        buf = raw[offset:(offset+512)]
        if not buf: break
        p = panic_verify(buf,plist)
        if (p):
            BLK += 1
        offset += 76800
    return plist

print('Panic Inspector/eXtractor')

# always display
if panic_search(PLIST):
    print('%s Panic Dumps Found:' % (len(PLIST)))
    for element in PLIST:
        print(element)

if args.output:
    pblk = raw_input("\n*** dump to extract: ")
    pblk = int(pblk)
    pblk_offset = 512 * 150 * pblk + 512
    ex_blk      = raw[pblk_offset:]
    consumed    = panic_block_0_obj.set(ex_blk)

    panic_info = panic_block_0_obj['panic_info']
    image_info = panic_block_0_obj['image_info']
    add_info   = panic_block_0_obj['add_info']
    crash_info = panic_block_0_obj['crash_info']
    ram_header = panic_block_0_obj['ram_header']

    ci_sig      = (crash_info['ci_sig'].val)
    cc_sig      = (crash_info['cc_sig'].val)
    cc_sig      = struct.pack('>I',cc_sig)
    cc_flags    = (crash_info['flags'].val)
    ci_sig      = (crash_info['ci_sig'].val)
    cc_sig      = (crash_info['cc_sig'].val)
    cc_sig      = struct.pack('>I',cc_sig)
    cc_flags    = (crash_info['flags'].val)
    bxReg_0     = (crash_info['bxReg_0'].val)
    bxReg_1     = (crash_info['bxReg_1'].val)
    bxReg_2     = (crash_info['bxReg_2'].val)
    bxReg_3     = (crash_info['bxReg_3'].val)
    bxReg_4     = (crash_info['bxReg_4'].val)
    bxReg_5     = (crash_info['bxReg_5'].val)
    bxReg_6     = (crash_info['bxReg_6'].val)
    bxReg_7     = (crash_info['bxReg_7'].val)
    bxReg_8     = (crash_info['bxReg_8'].val)
    bxReg_9     = (crash_info['bxReg_9'].val)
    bxReg_10    = (crash_info['bxReg_10'].val)
    bxReg_11    = (crash_info['bxReg_11'].val)
    bxReg_12    = (crash_info['bxReg_12'].val)
    bxSP        = (crash_info['bxSP'].val)
    bxLR        = (crash_info['bxLR'].val)
    bxPC        = (crash_info['bxPC'].val)
    bxPSR       = (crash_info['bxPSR'].val)
    axPSR       = (crash_info['axPSR'].val)
    ai_sig      = (add_info['ai_sig'].val)
    ii_sig      = (image_info['ii_sig'].val)
    pi_sig      = (panic_info['pi_sig'].val)
    pi_sig_hex  = '44665041'

    ram_sector  = (add_info['ram_sector'].val)
    ram_size    = (add_info['ram_size'].val)
    io_sector   = (add_info['io_sector'].val)
    io_dump_start = ((io_sector - panic_dir_sector) * 512)

    dump_end    = (panic_dir_sector + (panic_block_size * 512))
    a5          = (add_info['fcrumb_sector'].val)
    ram_start   = (ram_header['start'].val)
    ram_end     = (ram_header['end'].val)
    ram_header_start = struct.pack('<I',ram_start)
    ram_header_end   = struct.pack('<I',ram_end)
    regs_1      = [cc_flags,bxReg_0,bxReg_1,bxReg_2]
    regs_2      = [bxReg_3,bxReg_4,bxReg_5,bxReg_6]
    regs_3      = [bxReg_7,bxReg_8,bxReg_9,bxReg_10]
    regs_4      = [bxReg_11]
    regs_5      = [bxReg_12]
    regs_6      = [bxSP,bxLR,bxPC]
    regs_7      = [bxPSR,axPSR]

    outFile.write(cc_sig)
    for b in regs_1:
        outFile.write(struct.pack('<I',b))
    for b in regs_2:
        outFile.write(struct.pack('<I',b))
    for b in regs_3:
        outFile.write(struct.pack('<I',b))
    for b in regs_4:
        outFile.write(struct.pack('<I',b))
    for b in regs_5:
        outFile.write(struct.pack('<I',b))
    for b in regs_6:
        outFile.write(struct.pack('<I',b))
    for b in regs_7:
        outFile.write(struct.pack('<I',b))
    outFile.write(ram_header_start)
    outFile.write(ram_header_end)
    ram_dump = raw[ram_sector:ram_sector+ram_size]
    outFile.write(ram_dump)
    print('*** panic {} exported to CrashDebug: {}'.format(
        pblk, args.output.name))
    outFile.close
