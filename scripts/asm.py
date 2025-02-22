import argparse
import collections
import pathlib
import re
import struct

import isa


# Labels are a name and flag indicating whether or not they are local.
Label = collections.namedtuple('Label', 'name is_local')

# A signed 16b integer.
Int = collections.namedtuple('Data', 'value')


# Parse command line arguments.
def parse_args():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        '-v',
        '--verbose',
        action='store_true',
        help='Enable verbose output for debug.',
    )

    parser.add_argument(
        'input',
        metavar='INPUT',
        type=pathlib.Path,
        help='Path to input file to assemble.',
    )

    parser.add_argument(
        '-o',
        '--output',
        type=pathlib.Path,
        required=True,
        help='Path to output binary to generate.',
    )

    args = parser.parse_args()

    if not args.input.is_file():
        raise Exception(f'Bad input file: {args.input}')

    if not args.output.parent.is_dir():
        raise Exception(f'Bad output directory: {args.output.parent}')

    return args


# Parse label token. Labels can be either local or global, with local labels
# being formed of decimal characters only.
def parse_label(args, parts, error_prefix, indent):
    if not re.match(r'[_0-9a-zA-Z]+:', parts[0]):
        raise Exception(f'{error_prefix}Bad label name: {part[0]}')

    name = parts[0][:-1]
    parts.pop(0)

    label = Label(name=name, is_local=name.isdigit())

    if args.verbose:
        print(f'{" " * indent}- {label}')

    return label


# Parse assembler directives.
def parse_directive(args, parts, inc_dir, error_prefix, indent):
    name = parts[0]
    parts.pop(0)

    # .include replaces the current line with the content of the referenced
    # file.
    if name == '.include':
        if len(parts) != 1:
            raise Exception(f'{error_prefix}Junk at end of line.')

        path = parts[0]
        parts.pop(0)

        if path[0] != '"' or path[-1] != '"':
            raise Exception(f'{error_prefix}Bad include path string format.')

        path = inc_dir / path[1:-1]

        if not path.is_file():
            raise Exception(
                f'{error_prefix}Included file does not exist: {path}'
            )

        return parse_file(args, path, indent + 1)

    # .int indicates a 16b immediate with the specified value.
    if name == '.int':
        if len(parts) != 1:
            raise Exception(f'{error_prefix}Junk at end of line.')

        imm = isa.parse_imm(parts[0], error_prefix)
        imm = Int(value=imm)

        parts.pop(0)

        if args.verbose:
            print(f'{" " * indent}- {imm}')

        return [imm]

    # .zeros indicates N zero integers.
    if name == '.zeros':
        if len(parts) != 1:
            raise Exception(f'{error_prefix}Junk at end of line.')

        n = int(parts[0], 0)
        parts.pop(0)

        if n < 1:
            raise Exception(f'{error_prefix}Bad number of zeros: {n}')

        zero = Int(value=0)

        if args.verbose:
            print(f'{" " * indent}- {zero} * {n}')

        return [zero] * n

    raise Exception(f'{error_prefix}Unknown directive: {name}')


# Parse the provided line.
def parse_line(args, line, inc_dir, error_prefix, indent):
    items = []

    # Remove and comments. These are defined in the same way as python, where a
    # hash indicates the start of a comment and the rest of the line is ignored.
    # We also need to make sure the hash isn't in a string or character.
    in_str = None
    for i, char in enumerate(line):
        if in_str == char:
            in_str = None
            continue

        if in_str:
            continue

        if char in '\'"':
            in_str = char
            continue

        if char == '#':
            line = line[:i].strip()
            break

    # Skip empty lines, otherwise split into parts.
    if not line:
        return items

    if args.verbose:
        print(f'{" " * indent}- Parse line: {line}')

    parts = re.split(r'[\s,]+|\.\.', line)

    # While we have parts left in the line continue parsing.
    while parts:
        # If this part ends with a colon then it's expected to be a label.
        if parts[0][-1] == ':':
            items.append(parse_label(
                args,
                parts,
                error_prefix,
                indent + 1,
            ))
            continue

        # If it starts with a full stop then we have an assembly directive.
        if parts[0][0] == '.':
            items.extend(parse_directive(
                args,
                parts,
                inc_dir,
                error_prefix,
                indent + 1,
            ))
            continue

        # If it's neither of these then we expect an instruction.
        instr = isa.Instruction.from_parts(parts, error_prefix)
        items.append(instr)

        if args.verbose:
            print(f'{" " * (indent + 1)}- Instuction({instr})')

        # Instructions must be the last thing on a line.
        if parts:
            raise Exception(f'{error_prefix}Junk at end of line.')

    return items


# Parse an input file, updating items and labels.
def parse_file(args, path, indent=0):
    if args.verbose:
        print(f'{" " * indent}- Parse file: {path}')

    items = []

    with open(path, 'r') as f:
        for i, line in enumerate(f):
            line_items = parse_line(
                args,
                line.strip(),
                path.parent,
                f'{path}:{i + 1}: ',
                indent + 1,
            )

            items.extend(line_items)

    return items


# Resolve any label references to addresses.
def resolve_labels(args, items):
    if args.verbose:
        print('- Finding label addresses:')

    # Find all the labels and their addresses.
    pc = 0
    labels = {}

    for item in items:
        # Increment PC for data and instructions.
        if not isinstance(item, Label):
            if isinstance(item, isa.Instruction):
                pc += item.size()
            else:
                pc += 1
            continue

        if item.is_local:
            if item.name not in labels:
                labels[item.name] = []
            labels[item.name].append(pc)
        else:
            if item.name in labels:
                raise Exception(
                    f'Multiple instances of non-local label: {item.name}'
                )
            labels[item.name] = [pc]

    if not labels:
        if args.verbose:
            print(' - No labels found.')
        return

    if args.verbose:
        for name, addrs in sorted(labels.items()):
            print(f' - {name}: {", ".join(str(x) for x in addrs)}')

    # Now iterate through the instructions to resolve all the references.
    if args.verbose:
        print('- Resolving references to labels:')

    pc = 0
    for item in items:
        if not isinstance(item, isa.Instruction):
            if not isinstance(item, Label):
                pc += 1
            continue

        ref = item.ops.get('imm')
        if not isinstance(ref, str):
            pc += item.size()
            continue

        mode = ref[0]
        name = ref[1:]
        if mode not in '$@':
            raise Exception(f'Missing mode in label reference: {item}')

        # Local references must be a number followed by 'f' for forwards or 'b'
        # for backwards.
        local = name[:-1].isdigit() and name[-1] in 'bf'
        if local:
            search = name[-1]
            name = name[:-1]

            addrs = labels.get(name)
            if not addrs:
                raise Exception(f'Reference to unknown label: {item}')

            if search == 'f':
                for addr in addrs:
                    if addr > pc:
                        break
            else:
                for addr in reversed(addrs):
                    if addr <= pc:
                        break
        else:
            # Non-local references must be unambiguous.
            addrs = labels.get(name)

            if not addrs:
                raise Exception(f'Reference to unknown label: {item}')
            if len(addrs) != 1:
                raise Exception(f'Ambiguous reference to label: {item}')

            addr = addrs[0]

        # Calulate the offset. If absolute this is just the address, but if it's
        # PC relative we need to account for the pipeline having advanced.
        if mode == '$':
            item.ops['imm'] = addr
        else:
            item.ops['imm'] = addr - (pc + 1)

        pc += item.size()

        if args.verbose:
            print(f' - Resolved label {ref}: {item}')



# Generate the output binary.
def write_binary(args, items):
    if args.verbose:
        print(f'- Writing binary: {args.output}')

    mem_size = 0
    with open(args.output, 'wb') as f:
        for item in items:
            # Labels have no encoding.
            if isinstance(item, Label):
                continue

            if isinstance(item, Int):
                f.write(struct.pack('>h', item.value))
                mem_size += 1
            else:
                f.write(item.encode())
                mem_size += item.size()

        # Pad out with NOP instructions so we don't get uninitialised accesses
        # due to the pipeline lookahead.
        for _ in range(4):
            f.write(isa.Instruction().encode())
            mem_size += 1


    # Check we haven't exceed the maximum supported memory size.
    if mem_size > (1 << 16):
        raise Exception(f'Binary will exceed memory size: {mem_size}')


if __name__ == '__main__':
    args = parse_args()

    items = parse_file(args, args.input)
    resolve_labels(args, items)
    write_binary(args, items)
