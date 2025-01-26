import re
import struct


# General purpose REGisters, mapping from name in assembly to encoding. There
# are a total of eight 16b registers:
# - r0..r5      No special purpose.
# - r6          Link Register.
# - r7          Stack Pointer.
GREGS = {
    'r0': 0,
    'r1': 1,
    'r2': 2,
    'r3': 3,
    'r4': 4,
    'r5': 5,
    'r6': 6,
    'r7': 7,

    'lr': 6,
    'sp': 7,
}

GREGS_INV = {v: k for k, v in GREGS.items()}


# Predicate REGisters. There are a total of four 1b predicate registers, used
# for storing the results of comparisons. These are used to control conditional
# execution of instructions.
# - p0..p2      General purpose.
# - p3          Predicate True: always returns 1, writes are ignored.
PREGS = {
    'p0': 0,
    'p1': 1,
    'p2': 2,
    'p3': 3,

    'pt': 3,
}

PREGS_INV = {v: k for k, v in PREGS.items()}


# Encodings for each of the supported instructions. These strings list the bits
# from MSB to LSB, with letters indicating the positions of operands. Operands
# are divided into different types:
# - p   Predicate register used to control whether an instruction should be
#       exectued. Read only.
# - q   Predicate register used as the output of a comparisons. Write only.
# - a   General purpose destination register. This is read-write, with some
#       operations performing a read-modify-write operation.
# - b   General purpose source register. This is mostly read only, but can also
#       be written by writeback memory operations.
# - c   GREG source. This can only hold the values of r0..r6, with r7 being a
#       special value indicating the 16b following the instruction should be
#       treated as an immediate.
ENCODINGS = {
    # No-operation.
    'nop':      '0000000000000000',

    # Branch on compare register with zero.
    'beqz':     '0000000100bbbccc',
    'bnez':     '0000000101bbbccc',
    'bltz':     '0000000110bbbccc',
    'bgez':     '0000000111bbbccc',

    # Compare two sources and store the result in a predicate register.
    'eq':       '01000pp0qqbbbccc',
    'ne':       '01000pp1qqbbbccc',
    'lt':       '01001pp0qqbbbccc',
    'ltu':      '01001pp1qqbbbccc',
    'ge':       '01010pp0qqbbbccc',
    'geu':      '01010pp1qqbbbccc',

    # Extract bit from GREG and place result in PREG.
    'putp':     '01011pp0qqbbbccc',

    # Compare GREG with zero and write result to predicate register.
    'eqz':      '01011pp1qqbbb000',
    'nez':      '01011pp1qqbbb001',
    'ltz':      '01011pp1qqbbb010',
    'gez':      '01011pp1qqbbb011',

    # Clear or set PREG.
    'putpf':    '01011pp1qq000100',
    'putpt':    '01011pp1qq001100',

    # Shift and rotate.
    'srl':      '01100ppaaabbbccc',
    'sra':      '01101ppaaabbbccc',
    'ror':      '01110ppaaabbbccc',
    'sll':      '01111ppaaabbbccc',

    # Load/store 16b with pre-increment writeback.
    '!ld':      '10000ppaaabbbccc',
    '!st':      '10001ppaaabbbccc',

    # Load/store 16b with post-increment writeback.
    'ld!':      '10010ppaaabbbccc',
    'st!':      '10011ppaaabbbccc',

    # Load/store 16b without writeback.
    'ld':       '10100ppaaabbbccc',
    'st':       '10101ppaaabbbccc',

    # Push/pop register range to/from the stack.
    'push':     '10110ppaaabbb000',
    'pop':      '10110ppaaabbb001',

    # Extract and sign extend low or high byte from GREG.
    'extbl':    '10110ppaaabbb010',
    'extbh':    '10110ppaaabbb011',

    # Insert low byte into low or high byte of GREG.
    'insbl':    '10110ppaaabbb100',
    'insbh':    '10110ppaaabbb101',

    # Logical and arithmetic negation.
    'not':      '10110ppaaabbb110',
    'neg':      '10110ppaaabbb111',

    # Increment or decrement GREG by one.
    'inc':      '10111ppaaa000000',
    'dec':      '10111ppaaa000001',

    # Receive 8b or 16b over UART.
    'urxb':     '10111ppaaa000010',
    'urx':      '10111ppaaa000011',

    # Add/subtract two GREGs.
    'add':      '11000ppaaabbbccc',
    'sub':      '11001ppaaabbbccc',

    # Logical operations.
    'and':      '11010ppaaabbbccc',
    'andn':     '11011ppaaabbbccc',
    'or':       '11100ppaaabbbccc',
    'xor':      '11101ppaaabbbccc',

    # Move between GREGs.
    'mov':      '11110ppaaa000ccc',

    # Add GREG to PC.
    'addpc':    '11110ppaaa010ccc',

    # Branch if predicate true or false.
    'bt':       '11110pp000001ccc',
    'bf':       '11110pp000011ccc',

    # Branch and link on predicate.
    'blt':      '11110pp000101ccc',
    'blf':      '11110pp000111ccc',

    # Jump if predicate true or false.
    'jt':       '11110pp001001ccc',
    'jf':       '11110pp001011ccc',

    # Jump and link on predicate.
    'jlt':      '11110pp001101ccc',
    'jlf':      '11110pp001111ccc',

    # Send 8b or 16b over UART.
    'utxb':     '11110pp010001ccc',
    'utx':      '11110pp010011ccc',
}

OPCODES = {
    k: int(''.join(x if x in '01' else '0' for x in v), 2)
    for k, v in ENCODINGS.items()
}

OPCODE_MASKS = {
    k: int(''.join('1' if x in '01' else '0' for x in v), 2)
    for k, v in ENCODINGS.items()
}


# Syntax strings for instructions.
SYNTAX = {
    'nop':      'nop',
    'beqz':     'beqz {b}, {c}',
    'bnez':     'bnez {b}, {c}',
    'bltz':     'bltz {b}, {c}',
    'bgez':     'bgez {b}, {c}',
    'eq':       'eq.{p} {q}, {b}, {c}',
    'ne':       'ne.{p} {q}, {b}, {c}',
    'lt':       'lt.{p} {q}, {b}, {c}',
    'ltu':      'ltu.{p} {q}, {b}, {c}',
    'ge':       'ge.{p} {q}, {b}, {c}',
    'geu':      'geu.{p} {q}, {b}, {c}',
    'putp':     'putp.{p} {q}, {b}, {c}',
    'eqz':      'eqz.{p} {q}, {b}',
    'nez':      'nez.{p} {q}, {b}',
    'ltz':      'ltz.{p} {q}, {b}',
    'gez':      'gez.{p} {q}, {b}',
    'putpf':    'putpf.{p} {q}',
    'putpt':    'putpt.{p} {q}',
    'srl':      'srl.{p} {a}, {b}, {c}',
    'sra':      'sra.{p} {a}, {b}, {c}',
    'ror':      'ror.{p} {a}, {b}, {c}',
    'sll':      'sll.{p} {a}, {b}, {c}',
    '!ld':      '!ld.{p} {a}, {b}, {c}',
    '!st':      '!st.{p} {a}, {b}, {c}',
    'ld!':      'ld!.{p} {a}, {b}, {c}',
    'st!':      'st!.{p} {a}, {b}, {c}',
    'ld':       'ld.{p} {a}, {b}, {c}',
    'st':       'st.{p} {a}, {b}, {c}',
    'push':     'push.{p} {a}..{b}',
    'pop':      'pop.{p} {a}..{b}',
    'extbl':    'extbl.{p} {a}, {b}',
    'extbh':    'extbh.{p} {a}, {b}',
    'insbl':    'insbl.{p} {a}, {b}',
    'insbh':    'insbh.{p} {a}, {b}',
    'not':      'not.{p} {a}, {b}',
    'neg':      'neg.{p} {a}, {b}',
    'inc':      'inc.{p} {a}',
    'dec':      'dec.{p} {a}',
    'urxb':     'urxb.{p} {a}',
    'urx':      'urx.{p} {a}',
    'add':      'add.{p} {a}, {b}, {c}',
    'sub':      'sub.{p} {a}, {b}, {c}',
    'and':      'and.{p} {a}, {b}, {c}',
    'andn':     'andn.{p} {a}, {b}, {c}',
    'or':       'or.{p} {a}, {b}, {c}',
    'xor':      'xor.{p} {a}, {b}, {c}',
    'mov':      'mov.{p} {a}, {c}',
    'addpc':    'addpc.{p} {a}, {c}',
    'bt':       'bt.{p} {c}',
    'bf':       'bf.{p} {c}',
    'blt':      'blt.{p} {c}',
    'blf':      'blf.{p} {c}',
    'jt':       'jt.{p} {c}',
    'jf':       'jf.{p} {c}',
    'jlt':      'jlt.{p} {c}',
    'jlf':      'jlf.{p} {c}',
    'utxb':     'utxb.{p} {c}',
    'utx':      'utx.{p} {c}',
}


# Synonyms supported by the assembler. Each entry is a tuple of syntax, real
# instruction, and operand mapping for those that aren't present.
SYNONYMS = {
    # Move zero into GREG.
    'movz': ('movz.{p} {a}', 'xor', {'b': '{a}', 'c': '{a}'}),

    # Unconditional branch/jump with or without link.
    'b':    ('b {c}', 'bt', {'p': PREGS['pt']}),
    'j':    ('j {c}', 'jt', {'p': PREGS['pt']}),
    'bl':   ('bl {c}', 'blt', {'p': PREGS['pt']}),
    'jl':   ('jl {c}', 'jlt', {'p': PREGS['pt']}),

    # Return from function call.
    'ret':  ('ret.{p} lr', 'jt', {'c': GREGS['lr']}),

    # Get value of predicate register.
    'getp': ('getp {a}, {p}', 'inc', {}),
}


# Parse an immediate of the specified number of bits.
def parse_imm(data, error_prefix='', bits=16):
    try:
        imm = int(data, 0)
    except ValueError:
        imm = None

    if imm is None:
        raise Exception(f'{error_prefix}Bad immediate: {data}')

    # Immediates are internally represented as a signed vlaue, so if the value
    # is too large then subtract the bias to get back into rage.
    bias = 1 << (bits - 1)
    if imm >= bias:
        imm -= bias

    # If the immediate is out of range we have a problem.
    if imm >= bias:
        raise Exception(f'{error_prefix}Immediate is too large: {data}')
    if imm < -bias:
        raise Exception(f'{error_prefix}Immediate is too small: {data}')

    return imm


# Class representing a single instruction.
class Instruction:
    # Default to a NOP.
    def __init__(self):
        self.name = 'nop'
        self.ops = {}

    # Create instruction from parts parsed from a line of assembly.
    @staticmethod
    def from_parts(parts, error_prefix=''):
        instr = Instruction()

        # The first part should be the optionally predicated name of the
        # instruction.
        instr.name = parts.pop(0)

        if '.' in instr.name:
            instr.name, pred = instr.name.split('.', 1)
            parts.insert(0, pred)
        else:
            pred = None

        # Find the syntax string for the instruction.
        if instr.name in SYNONYMS:
            syntax, instr.name, op_map = SYNONYMS[instr.name]
        else:
            syntax = SYNTAX.get(instr.name)
            op_map = {}

        if not syntax:
            raise Exception(f'{error_prefix}Unknown instruction: {instr.name}')

        # Find all of the operands from the syntax string and parse them.
        op_pattern = re.compile(r'\{(?P<name>[abcpq])\}')
        for name in op_pattern.finditer(syntax):
            name = name.group('name')

            # If this is operand p but none was specified in the instruction
            # name then it defaults to pt.
            if name == 'p' and not pred:
                value = 'pt'
            else:
                if not parts:
                    raise Exception(f'{error_prefix}Missing operand: {name}')

                value = parts.pop(0)

            # Predicate registers.
            if name in 'pq':
                if value not in PREGS:
                    raise Exception(
                        f'{error_prefix}Bad predicate register for '
                        f'operand {name}: {value}'
                    )

                instr.ops[name] = PREGS[value]
                continue

            # If this is operand c then check for an immediate. This could be in
            # a number of forms:
            # - A numeric literal e.g. 0xab, 0b1101, 123
            # - A character literal e.g. 'A', '\n'
            # - An absolute reference to a label e.g. $target
            # - A relative reference to a label e.g. @target
            if name == 'c':
                imm = None

                if value[0] in '$@':
                    imm = value
                elif m := re.match(r"'(?P<value>[^\\]|\\[\\tn0])'", value):
                    value = m.group('value')
                    if value == '\\0':
                        imm = 0
                    elif value == '\\n':
                        imm = ord('\n')
                    elif value == '\\t':
                        imm = ord('\t')
                    else:
                        imm = ord(value)
                else:
                    # If we can't parse an immediate here then the value will be
                    # treated as a GREG.
                    try:
                        imm = parse_imm(value, error_prefix)
                    except:
                        pass

                # If an immediate was parsed then we should store it as an
                # operand and encode c as r7.
                if imm is not None:
                    instr.ops['imm'] = imm
                    value = 'r7'

            # Parse as a general purpose register.
            if value not in GREGS:
                raise Exception(
                    f'{error_prefix}Bad general purpose register for '
                    f'operand {name}: {value}'
                )

            instr.ops[name] = GREGS[value]

        if instr.ops.get('c') == GREGS['r7'] and 'imm' not in instr.ops:
            raise Exception(f'{error_prefix}Cannot have r7 as operand c.')

        # Add in an operands that come from the mapping from synonym to real
        # underlying instruction.
        for name, value in op_map.items():
            if m := op_pattern.match(str(value)):
                instr.ops[name] = instr.ops[m.group('name')]
            else:
                instr.ops[name] = value

        return instr

    # Return instruction as a string.
    def __str__(self):
        ops = {}

        for k, v in self.ops.items():
            if k == 'imm':
                continue

            if k in 'pq':
                ops[k] = PREGS_INV[v]
            elif k in 'ab':
                ops[k] = GREGS_INV[v]
            else:
                if 'imm' in self.ops:
                    v = self.ops['imm']
                    if isinstance(v, int):
                        ops[k] = hex(v)
                    else:
                        ops[k] = v
                else:
                    ops[k] = GREGS_INV[v]

        return SYNTAX[self.name].format(**ops)

    # Encode the instruction into raw bytes.
    def encode(self, error_prefix=''):
        bits = ENCODINGS[self.name]

        # Replace bits in the encoding with operand values.
        for name, value in self.ops.items():
            if name == 'imm':
                continue

            n = bits.count(name)
            enc = f'{value:0{n}b}'

            if len(enc) != n:
                raise Exception(
                    f'{error_prefix}Cannot encode operand {name}: {value}'
                )

            enc = iter(enc)
            bits = ''.join(next(enc) if x == name else x for x in bits)

        # Generate bytes for the instruction.
        enc = struct.pack('>H', int(bits, 2))

        # Append with immediate value if present.
        imm = self.ops.get('imm')
        if imm is None:
            return enc

        if not isinstance(imm, int):
            print(self)
            raise Exception(
                f'{error_prefix}Cannot encode non-int immediate: {imm}'
            )

        return enc + struct.pack('>h', imm)

    # Size of the instruction when encoded in number of 16b chunks.
    def size(self):
        return 1 + ('imm' in self.ops)
