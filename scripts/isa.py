import re


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
    'eq':       'eq.{p} {b}, {c}',
    'ne':       'ne.{p} {b}, {c}',
    'lt':       'lt.{p} {b}, {c}',
    'ltu':      'ltu.{p} {b}, {c}',
    'ge':       'ge.{p} {b}, {c}',
    'geu':      'geu.{p} {b}, {c}',
    'putp':     'putp.{p} {q}, {b}, {c}',
    'eqz':      'eqz.{p} {b}',
    'nez':      'nez.{p} {b}',
    'ltz':      'ltz.{p} {b}',
    'gez':      'gez.{p} {b}',
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


# Synonyms supported by the assembler.
SYNONYMS = {
    # Move zero into GREG.
    'movz.{p} {a}':     'xor.{p} {a}, {a}, {a}',

    # Unconditional branch/jump with or without link.
    'b {c}':            'bt.pt {c}',
    'j {c}':            'jt.pt {c}',
    'bl {c}':           'blt.pt {c}',
    'jl {c}':           'jlt.pt {c}',

    # Return from function call.
    'ret.{p}':          'jt.{p} lr',

    # Get value of predicate register.
    'getp {a}, {p}':    'inc.{p} {a}',
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
