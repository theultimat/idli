import argparse
import pathlib
import struct

import isa
import tb


# Callback used by the simulator to invoke functions when events of note occur.
# This is useful for comparisons with the RTL implementation of the core.
class IdliCallback:
    # Called when a new value is written to a GREG.
    def write_greg(self, reg, value):
        pass

    # Called when a new value is written to a PREG.
    def write_preg(self, reg, value):
        pass

    # Called when attempting to read data into the core over UART.
    # Expected to return the data.
    def read_uart(self, width):
        raise NotImplementedError()

    # Called when writing to the UART from the core.
    def write_uart(self, value, width):
        pass

    # Called when storing to memory.
    def write_mem(self, addr, value):
        pass

    # Called when loading from memory.
    def read_mem(self, addr, value):
        pass


# Behavioural simulator for the CPU at the instruction level. This is not cycle
# accurate!
class Idli:
    # Initialise and reset the CPU.
    def __init__(self, path, trace=False, callback=None):
        self.trace = trace
        self.cb = callback

        # Program counter always resets to zero.
        self.pc = 0

        # None of the GREGs are actually reset so set these to none at the start
        # of time.
        self.gregs = [None] * 8

        # This is also true for PREGs, except we also have PT which is always
        # set to 1.
        self.pregs = [None] * 4
        self.pregs[isa.PREGS['pt']] = True

        # Memory can be addressed at 16b granularity only. We create a memory
        # which takes up the entire 16b address space (unitialised) then load
        # the content of the specified binary.
        self.mem = []
        with open(path, 'rb') as f:
            while data := f.read(2):
                self.mem.append(data)

        self.mem += [None] * ((1 << 16) - len(self.mem))

        # Map from instruction name to function that implements the operation.
        # Each function returns a bool indicating whether the instruction has
        # modified the PC.
        self.instr_funcs = {
            'nop':      self._nop,
            'beqz':     self._branch_reg,
            'bnez':     self._branch_reg,
            'bltz':     self._branch_reg,
            'blez':     self._branch_reg,
            'bgtz':     self._branch_reg,
            'bgez':     self._branch_reg,
            'push':     self._push,
            'pop':      self._pop,
            'eq':       self._cmp,
            'ne':       self._cmp,
            'lt':       self._cmp,
            'ltu':      self._cmp,
            'ge':       self._cmp,
            'geu':      self._cmp,
            'putp':     self._putp,
            'eqz':      self._cmp,
            'nez':      self._cmp,
            'ltz':      self._cmp,
            'lez':      self._cmp,
            'gtz':      self._cmp,
            'gez':      self._cmp,
            'putpf':    self._putp,
            'putpt':    self._putp,
            'srl':      self._shift,
            'sra':      self._shift,
            'ror':      self._shift,
            'sll':      self._shift,
            '!ld':      self._ld_st,
            '!st':      self._ld_st,
            'ld!':      self._ld_st,
            'st!':      self._ld_st,
            'ld':       self._ld_st,
            'st':       self._ld_st,
            'extbl':    self._ext,
            'extbh':    self._ext,
            'insbl':    self._ins,
            'insbh':    self._ins,
            'not':      self._logic,
            'neg':      self._add_sub,
            'inc':      self._add_sub,
            'dec':      self._add_sub,
            'urxb':     self._uart_rx,
            'urx':      self._uart_rx,
            'add':      self._add_sub,
            'sub':      self._add_sub,
            'and':      self._logic,
            'andn':     self._logic,
            'or':       self._logic,
            'xor':      self._logic,
            'mov':      self._add_sub,
            'addpc':    self._add_sub,
            'bt':       self._branch_pred,
            'bf':       self._branch_pred,
            'blt':      self._branch_pred,
            'blf':      self._branch_pred,
            'jt':       self._branch_pred,
            'jf':       self._branch_pred,
            'jlt':      self._branch_pred,
            'jlf':      self._branch_pred,
            'utxb':     self._uart_tx,
            'utx':      self._uart_tx,
        }

    # Perform one "tick". This is equivalent to running a single instruction.
    def tick(self):
        # Fetch and decode the next instruction at the current PC.
        instr, next_pc = self.next_instr()

        if self.trace:
            print(f'RUN     0x{self.pc:04x}    {instr}')

        # Account for the PC being updated before the instruction actually
        # executes due to the pipeline in the RTL.
        self.pc = next_pc

        # Run the instruction if required.
        if self._check_run(instr):
            redirect = self.instr_funcs[instr.name](
                instr,
                self._get_operands(instr)
            )
        else:
            if self.trace:
                print(f'SKIP    {isa.PREGS_INV[instr.ops["p"]]}')

            redirect = False

        # If the instruction didn't redirect the PC and it took an immediate
        # then we need to increment the PC one more time.
        if not redirect:
            self.pc = (self.pc + instr.size() - 1) & 0xffff

    # Returns true if an instruction should be run. In most cases this is simply
    # checking if the predicate is true, but some instructions explicitly negate
    # the predicate before the check.
    def _check_run(self, instr):
        pred = instr.ops.get('p')

        # Non-predicated instructions always run.
        if pred is None:
            return True

        # Branches and jumps may negate the condition.
        pred = self.pregs[pred]
        if instr.name in('bf', 'blf', 'jf', 'jlf'):
            pred = not pred

        return pred

    # Get operand values for the instruction, correctly handling the immediate
    # and placing it in C if required.
    def _get_operands(self, instr):
        ops = {}

        for name, value in instr.ops.items():
            # These operands are never read directly so can be skipped.
            if name in ('p', 'imm'):
                continue

            # Only read A if the instruction uses it as a source operand.
            if name == 'a' and instr.name not in isa.INSTRS_READ_A:
                continue

            # If it's C then we may need to take the immediate value instead.
            if name == 'c' and value == isa.GREGS['r7']:
                ops[name] = instr.ops['imm']
                continue

            # If it's D then just take the value from the encoding.
            if name == 'd':
                ops[name] = value
                continue

            # Read the GREG directly, raising an exception if it hasn't been
            # initialised.
            ops[name] = self.gregs[value]

            if ops[name] is None:
                raise Exception(
                    f'Read of uninitialised register {isa.GREGS_INV[value]} '
                    f'in instruction: {instr}'
                )

        return ops

    # Write a GREG and invoke the callback if it's defined.
    def _write_greg(self, reg, value):
        value &= 0xffff

        if self.cb:
            self.cb.write_greg(reg, value)

        if self.trace:
            print(f'GREG    {isa.GREGS_INV[reg]}        0x{value:04x}')

        self.gregs[reg] = value

    # Write a PREG and invoke the callback.
    def _write_preg(self, reg, value):
        # Writes to p3 are ignored.
        if reg == isa.PREGS['pt']:
            return

        value = bool(value & 1)

        if self.cb:
            self.cb.write_preg(reg, value)

        if self.trace:
            print(f'PREG    {isa.PREGS_INV[reg]}        0x{int(value)}')

        self.pregs[reg] = value

    # Wirte a new value to the PC.
    def _write_pc(self, value):
        value &= 0xffff

        if self.trace:
            print(f'BRANCH  0x{value:04x}')

        self.pc = value

    # NOP doesn't do anything.
    def _nop(self, instr):
        return False

    # ADD/SUB are used to synthesise a number of other operations.
    def _add_sub(self, instr, ops):
        op = 'sub' if instr.name in ('neg', 'dec', 'sub') else 'add'

        if instr.name in ('neg', 'mov'):
            lhs = 0
        elif instr.name in ('inc', 'dec'):
            lhs = ops['a']
        elif instr.name == 'addpc':
            lhs = self.pc
        else:
            lhs = ops['b']

        if instr.name in ('inc', 'dec'):
            rhs = 1
        elif instr.name == 'neg':
            rhs = ops['b']
        else:
            rhs = ops['c']

        if op == 'add':
            value = lhs + rhs
        else:
            value = lhs - rhs

        self._write_greg(instr.ops['a'], value)

        return False

    # Write a value into a predicate register.
    def _putp(self, instr, ops):
        if instr.name == 'putp':
            value = (ops['b'] >> ops['c']) & 1
        elif instr.name == 'putpt':
            value = 1
        else:
            value = 0

        self._write_preg(instr.ops['q'], value)

        return False

    # Branch or jump to a new PC based on predicate. The predicate has already
    # been checked by this stage so we can just redirect the PC.
    def _branch_pred(self, instr, ops):
        # Some branches write to the link register. If the instruction has an
        # immediate then the PC needs to be incremented again.
        if 'l' in instr.name:
            next_pc = self.pc + int('imm' in instr.ops)
            self._write_greg(isa.GREGS['lr'], next_pc)

        # Branches are PC relative while jumps are absolute.
        lhs = self.pc if instr.name[0] == 'b' else 0
        self._write_pc(lhs + ops['c'])

        return True

    # Branch based on register comparison with zero.
    def _branch_reg(self, instr, ops):
        op = instr.name[1:2]
        lhs = self._make_signed(ops['b'])
        rhs = 0

        if op == 'eq':
            branch = lhs == rhs
        elif op == 'ne':
            branch = lhs != rhs
        elif op == 'lt':
            branch = lhs < rhs
        elif op == 'le':
            branch = lhs <= rhs
        elif op == 'gt':
            branch = lhs > rhs
        else:
            branch = lhs >= rhs

        if branch:
            self._write_pc(self.pc + ops['c'])

        return branch

    # Read bytes from UART.
    def _uart_rx(self, instr, ops):
        width = 1 if instr.name == 'urxb' else 2
        value = self.cb.read_uart(width)

        if self.trace:
            if width == 1:
                value_str = f'0x{value & 0xff:02x}'
            else:
                value_str = f'0x{value & 0xffff:04x}'
            print(f'URX     {value_str:6}')

        self._write_greg(instr.ops['a'], value)

        return False

    # Write bytes to UART.
    def _uart_tx(self, instr, ops):
        width = 1 if instr.name == 'utxb' else 2

        if self.trace:
            if width == 1:
                value_str = f'0x{ops["c"] & 0xff:02x}'
            else:
                value_str = f'0x{ops["c"] & 0xffff:04x}'
            print(f'UTX     {value_str:6}')

        self.cb.write_uart(ops['c'], width)

        return False

    # Compare register with another register or zero.
    def _cmp(self, instr, ops):
        lhs = ops['b']
        rhs = 0 if instr.name[-1] == 'z' else ops['c']

        # Convert values to signed if required.
        if instr.name not in ('ltu', 'geu'):
            lhs = self._make_signed(lhs)
            rhs = self._make_signed(rhs)

        if instr.name.startswith('eq'):
            value = lhs == rhs
        elif instr.name.startswith('ne'):
            value = lhs != rhs
        elif instr.name.startswith('lt'):
            value = lhs < rhs
        elif instr.name.startswith('le'):
            value = lhs <= rhs
        elif instr.name.startswith('gt'):
            value = lhs > rhs
        else:
            value = lhs >= rhs

        self._write_preg(instr.ops['q'], value)

        return False

    # Convert a value from unsigned to signed.
    def _make_signed(self, value, bits=16):
        sign_bit = 1 << (bits - 1)
        bias = 1 << bits

        if value & sign_bit:
            value -= bias

        return value

    # Logical ALU operations.
    def _logic(self, instr, ops):
        if instr.name == 'not':
            op = 'or'
            lhs = 0
            rhs = ops['b']
        else:
            op = instr.name[:3]
            lhs = ops['b']
            rhs = ops['c']

        if instr.name in ('not', 'andn'):
            rhs = ~rhs

        if op == 'and':
            value = lhs & rhs
        elif op == 'or':
            value = lhs | rhs
        else:
            value = lhs ^ rhs

        self._write_greg(instr.ops['a'], value)

        return False

    # Shift and rotate.
    def _shift(self, instr, ops):
        lhs = ops['b']
        rhs = ops['c']

        if instr.name == 'sra':
            lhs = self._make_signed(lhs)

        if instr.name in ('srl', 'sra'):
            value = lhs >> rhs
        elif instr.name == 'ror':
            value = (lhs >> rhs) | (lhs << (16 - rhs))
        else:
            value = lhs << rhs

        self._write_greg(instr.ops['a'], value)

        return False

    # Extract and sign extend the high or low byte.
    def _ext(self, instr, ops):
        if instr.name[-1] == 'l':
            value &= 0xff
        else:
            value = (value >> 8) & 0xff

        value = self._make_signed(value, 8)
        self._write_greg(instr.ops['a'], value)

        return False

    # Insert the low byte of B into the high or low byte of A.
    def _ins(self, instr, ops):
        if instr.name[-1] == 'l':
            value = (ops['a'] & 0xff00) | (ops['b'] & 0xff)
        else:
            value = (ops['a'] & 0xff) | ((ops['b'] & 0xff) << 8)

        self._write_greg(instr.ops['a'], value)

        return False

    # Load/store value from/to memory, optionally with writeback.
    def _ld_st(self, instr, ops):
        wb_pre = instr.name[0] == '!'
        wb_post = instr.name[-1] == '!'
        load = 'ld' in instr.name

        # Calcualte address - if it isn't post-writeback then we should add the
        # address before performing the access.
        addr = ops['b']
        addr_final = (addr + ops['c']) & 0xffff
        if not wb_post:
            addr = addr_final

        # If the writeback address is the value being stored then it should be
        # visible to the store - this is mainly to simplify the RTL.
        if not load and wb_pre and instr.ops['a'] == instr.ops['b']:
            self._write_greg(instr.ops['b'], addr_final)
            ops['a'] = addr_final

        # Load the value or store to the memory.
        if load:
            self._write_greg(instr.ops['a'], self._read_mem(addr))
        else:
            self._write_mem(addr, ops['a'])

        # Perform post-writeback if required.
        if wb_post:
            self._write_greg(instr.ops['b'], addr_final)

        return False

    # PUSH register range onto the stack and update SP.
    def _push(self, instr, ops):
        mask = instr.ops['d']
        sp = self.gregs[isa.GREGS['sp']]

        for idx in isa.GREGS_INV:
            if mask & (1 << idx):
                sp = (sp - 1) & 0xffff
                self._write_mem(sp, self.gregs[idx])

        self._write_greg(isa.GREGS['sp'], sp)

        return False

    # Reverse of push - operates similarly but it's from B to A instead.
    def _pop(self, instr, ops):
        mask = instr.ops['d']
        sp = self.gregs[isa.GREGS['sp']]

        for idx in reversed(isa.GREGS_INV):
            if mask & (1 << idx):
                self._write_greg(idx, self._read_mem(sp))
                sp = (sp + 1) & 0xffff

        self._write_greg(isa.GREGS['sp'], sp)

        return False

    # Write a value to memory.
    def _write_mem(self, addr, value):
        # While the core works in little-endian, the memory is big-endian so we
        # can deal with the SQI memory returning the high bits first.
        value = self._swap_endian(value)

        if self.cb:
            self.cb.write_mem(addr, value)

        if self.trace:
            print(f'STORE   0x{addr:04x}    0x{value:04x}')

        # Pack into LE as we've already converted manually to BE for tracing.
        self.mem[addr] = struct.pack('<H', value)

    # Load from memory.
    def _read_mem(self, addr):
        value, = struct.unpack('<H', self.mem[addr])

        if self.cb:
            self.cb.read_mem(addr, value)

        if self.trace:
            print(f'LOAD    0x{addr:04x}    0x{value:04x}')

        return self._swap_endian(value)

    # Swap the endianness of the 16b value.
    def _swap_endian(self, value):
        return ((value & 0xff) << 8) | ((value >> 8) & 0xff)

    # Get the instruction at the current PC.
    def next_instr(self):
        next_pc = (self.pc + 1) & 0xffff
        instr = isa.Instruction.from_bytes(self.mem[self.pc], self.mem[next_pc])

        return instr, next_pc


# Parse command line arguments if running in standalone mode.
def parse_args():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        'input',
        metavar='INPUT',
        type=pathlib.Path,
        help='Path to input binary.'
    )

    parser.add_argument(
        '-t',
        '--timeout',
        type=int,
        default=5000,
        help='Maximum ticks to run before ending the test.'
    )

    parser.add_argument(
        '-i',
        '--uart-in',
        default='',
        help='UART input file.'
    )

    parser.add_argument(
        '-o',
        '--uart-out',
        default='',
        help='UART expected output file.'
    )

    args = parser.parse_args()

    if not args.input.is_file():
        raise Exception(f'Bad input file: {args.input}')

    # Convert input and output data into byte buffers.
    args.uart_in = tb.load_uart_file(args.uart_in)
    args.uart_out = tb.load_uart_file(args.uart_out)

    return args


# Entry point for standalone simulation.
if __name__ == '__main__':
    args = parse_args()

    # Create a callback to feed the data into the core and read it out.
    class Callback(IdliCallback):
        def __init__(self, uart_in):
            self.uart_in = uart_in
            self.uart_out = bytes()

        def read_uart(self, width):
            if width == 1:
                value, = struct.unpack_from('<b', self.uart_in)
                self.uart_in = self.uart_in[1:]
            else:
                value, = struct.unpack_from('<h', self.uart_in)
                self.uart_in = self.uart_in[2:]

            return value

        def write_uart(self, value, width):
            fmt = '<B' if width == 1 else '<H'
            self.uart_out += struct.pack(fmt, value)

    # Create the simulator.
    cb = Callback(args.uart_in)
    sim = Idli(args.input, trace=True, callback=cb)

    # Run the test until we see the END string followed by return value or hit
    # the timeout.
    end_str = 'END'.encode('utf-8')
    finished = False

    for i in range(args.timeout):
        sim.tick()

        finished = cb.uart_out[-5:-2] == end_str
        if finished:
            break

    # Check we passed.
    if not finished:
        raise Exception(f'Test exceeded timeout!')

    exit_code, = struct.unpack_from('<h', cb.uart_out[-2:])
    if exit_code:
        raise Exception(f'Test exited with code: {exit_code}')

    # Check the output matched the expected value.
    if args.uart_out != cb.uart_out[:-5]:
        raise Exception(
            f'Test UART output differed from expected value:\n'
            f'  Expected: {args.uart_out}\n'
            f'  Actual:   {cb.uart_out[:-5]}'
        )
