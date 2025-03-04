import struct

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import (
    RisingEdge, FallingEdge, ClockCycles, Event, with_timeout
)

import sim
import sqi
import uart


# Simulator callback for use with the test bench (defined below).
class TestBenchCallback(sim.IdliCallback):
    def __init__(self, tb, uart_in):
        self.tb = tb
        self.uart_in = uart_in

    def write_greg(self, reg, value):
        self.tb.check_greg_write(reg, value)

    def write_preg(self, reg, value):
        self.tb.check_preg_write(reg, value)

    def read_uart(self, width):
        fmt = f'<{"BH"[width - 1]}'
        value, = struct.unpack_from(fmt, self.uart_in)
        self.uart_in = self.uart_in[width:]

        return value

    def write_uart(self, value, width):
        lo = (value >> 0) & 0xff
        hi = (value >> 8) & 0xff

        self.tb.sim_uart_rx.append(lo)

        if width > 1:
            self.tb.sim_uart_rx.append(hi)

    def write_mem(self, addr, value):
        raise NotImplementedError()

    def read_mem(self, addr, value):
        raise NotImplementedError()


# Test bench for use with cocotb. Loads the memories, sets up the simulator for
# comparison, etc.
class TestBench:
    def __init__(self, dut, path, uart_in, uart_out, timeout=1000):
        self.dut = dut
        self.log = dut._log.info

        self.log('BENCH: INIT BEGIN')

        self.cb = TestBenchCallback(self, uart_in)
        self.sim = sim.Idli(path, callback=self.cb)

        self.mem = [
            sqi.SQIMemory(verbose=True, log=lambda x: self.log(f'SQI0: {x}')),
            sqi.SQIMemory(verbose=True, log=lambda x: self.log(f'SQI1: {x}')),
        ]
        self._backdoor_load(path)

        self.sim_uart_rx = []
        self.rtl_uart_rx = []
        self.ref_uart_rx = [x for x, in struct.iter_unpack('<B', uart_out)]

        # Add 'END' to the expected UART RX output - this will be followed by
        # the exit code.
        self.ref_uart_rx.extend([ord(x) for x in 'END'])

        self.uart = uart.UART(
            rx_cb=lambda x: self.rtl_uart_rx.append(x),
            tx_data=uart_in,
            verbose=True,
            log=lambda x: self.log(f'UART: {x}'),
        )

        self.timeout = timeout
        self.exit_code = []
        self.end_of_test = Event()

        self.log('BENCH: INIT COMPLETE')

    # Load the data into the pair of connected memories, with the low nibbles
    # packed one memory and the high into the other.
    def _backdoor_load(self, path):
        with open(path, 'rb') as f:
            addr = 0
            while data := f.read(2):
                data, = struct.unpack('>H', data)

                lo = ((data & 0x0f) >> 0) | ((data & 0x0f00) >> 4)
                hi = ((data & 0xf0) >> 4) | ((data & 0xf000) >> 8)

                self.mem[0].backdoor_load(addr, hi)
                self.mem[1].backdoor_load(addr, lo)

                self.log(f'SQI0: BACKDOOR addr=0x{addr:04x} data=0x{hi:02x}')
                self.log(f'SQI1: BACKDOOR addr=0x{addr:04x} data=0x{lo:02x}')

                addr += 1

    # Simulate the specified SQI memory.
    async def _check_sqi(self, mem_id, mem):
        if mem_id == 0:
            dut_sck = self.dut.sqi_sck_lo
            dut_cs = self.dut.sqi_cs_lo
            dut_sio_in = self.dut.sqi_sio_in_lo
            dut_sio_out = self.dut.sqi_sio_out_lo
        else:
            dut_sck = self.dut.sqi_sck_hi
            dut_cs = self.dut.sqi_cs_hi
            dut_sio_in = self.dut.sqi_sio_in_hi
            dut_sio_out = self.dut.sqi_sio_out_hi

        # Wait for the chip to come out of reset.
        await RisingEdge(self.dut.rst_n)

        while True:
            await RisingEdge(dut_sck)

            cs = dut_cs.value
            sio = dut_sio_out.value

            mem.rising_edge(cs, sio)

            await FallingEdge(dut_sck)

            sio = mem.falling_edge()

            if sio is not None:
                dut_sio_in.value = sio

            # TODO Check stores

    # Check PC matches.
    def _check_pc(self):
        sim = self.sim.pc
        rtl = self.dut.ex_pc.value.integer

        self.log(f'PC: sim=0x{sim:04x} rtl=0x{rtl:04x}')
        assert sim == rtl

    # Wait for instructions to complete in RTL then run on the behavioural
    # model to compare.
    async def _check_instr(self):
        instr_done = self.dut.ex_instr_done
        instr_skip = self.dut.ex_instr_skip_q

        await RisingEdge(self.dut.rst_n)

        while True:
            await RisingEdge(self.dut.gck)

            done = instr_done.value
            skip = instr_skip.value

            if not done and not skip:
                continue

            # Check PC is correct. Only do this if the instruction actually ran
            # as the skip signal is out of sync with the PC.
            if done:
                self._check_pc()

            # Log the instruction that we think just executed.
            instr, _ = self.sim.next_instr()
            self.log(f'RUN: pc=0x{self.sim.pc:04x} instr={instr}')

            # Run the behavioural model to fire the callbacks that perform the
            # checks.
            self.sim.tick()

    # Check simulator and RTL UART match.
    def _check_uart_data(self):
        while self.sim_uart_rx and self.rtl_uart_rx:
            sim = self.sim_uart_rx.pop(0)
            rtl = self.rtl_uart_rx.pop(0)

            self.log(f'UART: sim=0x{sim:02x} rtl=0x{rtl:02x}')
            assert sim == rtl

            # Check the output matches the expected from the file, and if we've
            # reached the end of the test then this is the exit code.
            if self.ref_uart_rx:
                ref = self.ref_uart_rx.pop(0)
                assert ref == rtl
            else:
                self.exit_code.append(sim)

                # If we have 16b of exit code then the test is complete.
                if len(self.exit_code) == 2:
                    lo, hi = self.exit_code
                    self.exit_code = (hi << 8) | lo
                    self.end_of_test.set()

    # Check UART RX and transmit for TX.
    async def _check_uart(self):
        rx = self.dut.uart_tx
        tx = self.dut.uart_rx

        tx_start = self.dut.sync_uart_rx_stall

        await RisingEdge(self.dut.rst_n)

        while True:
            await RisingEdge(self.dut.gck)

            tx.value = self.uart.rising_edge(
                rx.value.integer & 1,
                tx_start.value.integer & 1,
            )
            self._check_uart_data()

    # Check a GREG write was correct by comparing the value the sim has just
    # written with what's now in the RTL.
    def check_greg_write(self, reg, value):
        sim = value
        rtl = self.dut.ex_gregs[reg].value.integer

        self.log(f'GREG: r{reg} sim=0x{sim:04x} rtl=0x{rtl:04x}')
        assert sim == rtl

    # Check a PREG write is the correct value.
    def check_preg_write(self, reg, value):
        sim = int(value)
        rtl = (self.dut.ex_pregs.value.integer >> reg) & 1

        self.log(f'PREG: p{reg} sim=0x{sim} rtl=0x{rtl}')
        assert sim == rtl

    # Main simulation function.
    async def run(self):
        cocotb.start_soon(Clock(self.dut.gck, 2, units='ns').start())

        for i, mem in enumerate(self.mem):
            cocotb.start_soon(self._check_sqi(i, mem))

        cocotb.start_soon(self._check_instr())
        cocotb.start_soon(self._check_uart())

        self.log('BENCH: RESET BEGIN')

        self.dut.rst_n.setimmediatevalue(1)
        await ClockCycles(self.dut.gck, 1)

        self.dut.rst_n.setimmediatevalue(0)
        await ClockCycles(self.dut.gck, 1)

        self.dut.rst_n.setimmediatevalue(1)

        self.log('BENCH: RESET COMPLETE')

        # Run until test completion or timeout.
        await with_timeout(self.end_of_test.wait(), self.timeout, 'ns')

        if self.end_of_test.is_set():
            self.log(f'BENCH: exit_code={self.exit_code}')
        else:
            self.log('BENCH: TEST TIMEOUT')

        self._check_uart_data()
        if self.sim_uart_rx:
            raise Exception(f'Outstanding sim UART: {self.sim_uart_rx}')
        if self.rtl_uart_rx:
            raise Exception(f'Outstanding RTL UART: {self.rtl_uart_rx}')

        # Check the exit code is correct.
        if self.exit_code != 0:
            raise Exception(f'Bad exit code from test: {self.exit_code}')


# Load UART values for test input or output. These files are formatted as a
# single 16b value per line.
def load_uart_file(path):
    data = bytes()

    with open(path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            data += struct.pack('<h', int(line, 0))

    return data
