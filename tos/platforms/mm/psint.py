#
# this program is a simple tool for visulizing the progression that PS
# interrupts take when closing in on a time event.
#
# run with: 'python psint.py'
#

from   __future__         import print_function
import sys

def get_input(prompt):
    x = raw_input(prompt).lstrip()
    if x == '':
        sys.exit()
    return x

def cycles2time(cycles):
    return 1000 * cycles/32768.

def doit(cur_ta, target):
    x = target & ~7
    mask = target ^ cur_ta
    num_zeros = len(format(mask, '016b').split('1', 1)[0])
    if num_zeros == 16:
        ps_int = 0
        new_ta = cur_ta
    else:
        ps_int = 2**(15-num_zeros)
        new_ta = cur_ta & ~(ps_int - 1) | ps_int
    cycles = new_ta - cur_ta

    if target & 0x8000 != cur_ta & 0x8000:
        print('edge: {}  {}'.format(
            'R > target' if cur_ta > target else 'R < target',
            'PS/Q15 zero' if cur_ta < target else ''))

    print('{:04x} -> {:04x} ({:5})  {:04x}  ({:5})  {:04x}  ->  {:04x}  {:x}  {:6} {:8.3f}'.format(
        cur_ta, target, target - cur_ta,
        x, x - cur_ta, mask, ps_int, new_ta, cycles, cycles2time(cycles)))

    if x <= cur_ta or (x - cur_ta) < 8:
        return cur_ta
    return new_ta

while True:
    target = get_input('target: ')
    target = int(target, 16) & 0xffff
    cur_ta = get_input('cur_ta: ')
    cur_ta = int(cur_ta, 16) & 0xffff

    print('               diff     x     d_x    mask       int   new  cycles   ms')
    while True:
        new_ta = doit(cur_ta, target)
        if new_ta == cur_ta:
            cycles = target - new_ta
            print('remaining: {} cycles  {:4.3f} ms'.format(cycles, cycles2time(cycles)))
            print()
            break
        cur_ta = new_ta
