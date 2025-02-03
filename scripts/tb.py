import struct

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles

import sim
import sqi


# Simulator callback for use with the test bench (defined below).
class TestBenchCallback(sim.IdliCallback):
    def __init__(self, tb, uart_in, uart_out):
        self.tb = tb
        self.uart_in = uart_in
        self.uart_out = uart_out

    def write_greg(self, reg, value):
        raise NotImplementedError()

    def write_preg(self, reg, value):
        raise NotImplementedError()

    def read_uart(self, width):
        fmt = f'<{"BH"[width - 1]}'
        value, = struct.unpack_from(fmt, self.uart_in)
        self.uart_in = self.uart_in[width:]

        self.tb.log(f'UART_RX: data=0x{value:x} width={width}')

        return value

    def write_uart(self, value, width):
        raise NotImplementedError()

    def write_mem(self, addr, value):
        raise NotImplementedError()

    def read_mem(self, addr, value):
        raise NotImplementedError()


# Test bench for use with cocotb. Loads the memories, sets up the simulator for
# comparison, etc.
class TestBench:
    def __init__(self, dut, path, uart_in, uart_out):
        self.dut = dut
        self.log = dut._log.info

        self.log('BENCH: INIT BEGIN')

        self.cb = TestBenchCallback(self, uart_in, uart_out)
        self.sim = sim.Idli(path, callback=self.cb)

        self.mem = [sqi.SQIMemory(), sqi.SQIMemory()]
        self._backdoor_load(path)

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

                self.mem[0].backdoor_load(addr, lo)
                self.mem[1].backdoor_load(addr, hi)

                self.log(f'SQI0: BACKDOOR addr=0x{addr:04x} data=0x{lo:02x}')
                self.log(f'SQI1: BACKDOOR addr=0x{addr:04x} data=0x{hi:02x}')

                addr += 1

    # Simulate the specified SQI memory.
    async def _check_sqi(self, mem_id, mem):
        # Wait for the chip to come out of reset.
        await RisingEdge(self.dut.rst_n)

        while True:
            await RisingEdge(self.dut.sqi_sck)

            cs = self.dut.sqi_cs.value
            sio = (self.dut.sqi_sio_in.value >> (mem_id * 4)) & 0xf

            mem.rising_edge(cs, sio)

            await FallingEdge(self.dut.sqi_gck)

            sio = mem.falling_edge()

            if sio is not None:
                # TODO Check output data.
                raise NotImplementedError()

    # Main simulation function.
    async def run(self):
        cocotb.start_soon(Clock(self.dut.gck, 2, units='ns').start())

        for i, mem in enumerate(self.mem):
            cocotb.start_soon(self._check_sqi(i, mem))

        self.log('BENCH: RESET BEGIN')

        self.dut.rst_n.value = 1
        await ClockCycles(self.dut.gck, 1)

        self.dut.rst_n.value = 0
        await ClockCycles(self.dut.gck, 1)

        self.dut.rst_n.value = 1

        self.log('BENCH: RESET COMPLETE')

        # TODO Run until test completion - for now just run for a few cycles.
        await ClockCycles(self.dut.gck, 10)


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
