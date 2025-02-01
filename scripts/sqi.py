# Cycle-accurate model of Microchip 23A512/23LC512 memory when configured in
# sequential SQI mode. Intended for use with the cocotb test bench.

# Modes supported by the memory.
SQI_MODE_WRITE = 0x2
SQI_MODE_READ = 0x3

SQI_MODE_STR = {
    SQI_MODE_WRITE: 'WRITE',
    SQI_MODE_READ:  'READ',
}


# Main class which implements the model.
class SQIMemory:
    def __init__(self, verbose=False):
        # Size of the memory in bytes.
        self.size = 1 << 16

        # Data contained by the memory. Default all values to None so we can
        # check for uninitialised reads.
        self.data = [None] * self.size

        # Current address register and mask for wrapping.
        self.addr = None
        self.addr_mask = self.size - 1

        # Current state and mode of the memory.
        self.state = None
        self.mode = None

        # Whether verbose output tracing should be enabled.
        self.verbose =  verbose

    # Backdoor load data into the memory.
    def backdoor_load(self, addr, data):
        self.data[addr] = data & 0xff

    # Rising edge of the clock.
    def rising_edge(self, cs, sio):
        if cs is None:
            raise Exception('CS is not connected!')

        # Check chip select is pulled low otherwise we reset the address and
        # state back to their original values.
        if cs != 0:
            if self.addr is not None or self.state is not None:
                if self.verbose:
                    print('Resetting SQI memory.')

                if self.state in ('read1', 'write1'):
                    raise Exception(f'CS pulled low half way through a byte!')

                self.addr = None
                self.state = None

            return

        # Determine behaviour based on the current state.
        if self.state is None:
            # First cycle of instruction so write to the mode register.
            self.mode = sio & 0xf
            self.state = 'instr'
        elif self.state == 'instr':
            # Read second half of the instruction from the memory.
            self.mode = (self.mode << 4) | (sio & 0xf)
            self.state = 'addr0'

            if self.mode not in (SQI_MODE_READ, SQI_MODE_WRITE):
                raise Exception(f'Unknown SQI mode: 0x{self.mode:04x}')

            if self.verbose:
                mode_str = SQI_MODE_STR[self.mode]
                print(f'SQI command: {mode_str} (0x{self.mode:04x})')
        elif self.state in ('addr0', 'addr1', 'addr2', 'addr3'):
            # Read address data from the input pins.
            stage = int(self.state[-1])

            if stage == 0:
                self.addr = sio & 0xf
            else:
                self.addr = (self.addr << 4) | (sio & 0xf)

            if stage == 3:
                if self.verbose:
                    print(f'SQI address: 0x{self.addr:04x}')

                if self.mode == SQI_MODE_READ:
                    self.state = 'dummy0'
                else:
                    self.state = 'write0'
            else:
                self.state = f'addr{stage + 1}'
        elif self.state in ('dummy0', 'dummy1'):
            # Reads start with two dummy cycles.
            if self.state[-1] == '1':
                self.state = 'read0'
            else:
                self.state = 'dummy1'
        elif self.state in ('read0', 'read1'):
            # Read data is presented on the falling edge, so just skip between
            # the two states.
            if self.state[-1] == '1':
                self.state = 'read0'
            else:
                self.state = 'read1'
        elif self.state == 'write0':
            # Store into the high bits of the byte.
            value = self.data[self.addr]
            if value is None:
                value = 0

            value = ((sio & 0xf) << 4) | (value & 0xf)

            self.data[self.addr] = value
            self.state = 'write1'
        elif self.state == 'write1':
            # Store the low bits of the byte.
            value = self.data[self.addr]
            value = (value & 0xf0) | (sio & 0xf)

            self.data[self.addr] = value
            self.state = 'write0'

            if self.verbose:
                print('SQI write 0x{self.addr:04x}: 0x{value:02x}')

            # Increment the address.
            self.addr = (self.addr + 1) & self.addr_mask
        else:
            raise Exception(f'Unknown state: {self.state}')

    # Falling edge of the clock, returning any generated data if required.
    def falling_edge(self):
        if self.state not in('read0', 'read1'):
            return None

        value = self.data[self.addr]
        if value is None:
            raise Exception(f'Uninitialised read: 0x{self.addr:04x}')

        if self.state[-1] == '0':
            if self.verbose:
                print('SQI read 0x{self.addr}: 0x{value:02x}')

            value = (value >> 4) & 0xf
        else:
            value &= 0xf
            self.addr = (self.addr + 1) & self.addr_mask

        return value
