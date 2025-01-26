import argparse
import pathlib
import struct

import isa


# Parse command line arguments.
def parse_args():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        '-v',
        '--verbose',
        action='store_true',
        help='Enable verbose output.',
    )

    parser.add_argument(
        'input',
        metavar='INPUT',
        type=pathlib.Path,
        help='Path to input binary to disassemble.',
    )

    args = parser.parse_args()

    if not args.input.is_file():
        raise Exception(f'Bad input file: {args.input}')

    return args


# Parse input file into instructions.
def parse(args):
    items = []

    with open(args.input, 'rb') as f:
        data = f.read()

    if len(data) % 2:
        raise Exception(f'Input not multiple of 16b: {len(data)}')

    # Process all the data in 16b chunks, making notes of duplicates.
    while data:
        this_half = data[:2]
        next_half = data[2:4]

        try:
            item = isa.Instruction.from_bytes(this_half, next_half)
            data = data[item.size() * 2:]
        except:
            item, = struct.unpack('>h', this_half)
            data = data[2:]

        if items:
            prev_item, prev_count = items[-1]
        else:
            prev_item = None

        if item == prev_item:
            items[-1] = (item, prev_count + 1)
        else:
            items.append((item, 1))

    return items


# Return the disassembly as a string.
def dump(args, items):
    lines = []
    pc = 0

    branches = set([
        'beqz',
        'bnez',
        'bltz',
        'bgez',
        'bt',
        'bf',
        'blt',
        'blf',
    ])

    jumps = set([
        'jt',
        'jf',
        'jlt',
        'jlf',
    ])

    for item, count in items:
        if isinstance(item, isa.Instruction):
            # Get the raw encoding of the instruction in hex form.
            enc = item.encode()
            raw = f'{struct.unpack(">H", enc[:2])[0]:04x}'
            if len(enc) > 2:
                raw = f'{raw} {struct.unpack(">H", enc[2:])[0]:04x}'

            # Get the disassmebly, appending a comment for the target if the PC
            # is written to a known value - but only if we don't repeat the
            # entry multiple times, as otherwise the comment will be incorrect
            # on all but the first.
            line = str(item)
            size = item.size()

            if count == 1:
                know_target = item.ops.get('imm') != None
                target = None

                if item.name in branches:
                    if know_target:
                        target = hex(pc + 1 + item.ops['imm'])
                    else:
                        target = '?'
                elif item.name in jumps:
                    target = hex(item.ops['imm']) if know_target else '?'

                if target is not None:
                    line = f'{line} # target={target}'
        else:
            # This is just a chunk of data so print in hex.
            raw = f'{item:04x}'
            line = f'.data 0x{item}'
            size = 1

        # If verbose mode is enabled then output all of the lines, otherwise
        # output a truncated version when there are many repeats.
        if args.verbose or count < 3:
            for _ in range(count):
                lines.append(f'{pc:04x}:  {raw:12}  {line}')
                pc += size
        else:
            lines.append(f'{pc:04x}:  {raw:12}  {line}')
            pc += size

            lines.append(' *')
            pc += size * (count - 2)

            lines.append(f'{pc:04x}:  {raw:12}  {line}')
            pc += size

    return lines


if __name__ == '__main__':
    args = parse_args()
    items = parse(args)
    lines = dump(args, items)

    print('\n'.join(lines))
