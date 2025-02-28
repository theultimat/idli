import struct


# UART transmitter and receiver for connecting to the RTL.
class UART:
    def __init__(self, rx_cb, tx_data, verbose=False, log=print):
        self.verbose = verbose
        self.log = log

        # Only support 8b data frames and a single stop bit.
        self.data_bits = 8
        self.stop_bits = 1

        # Byte buffers for sending and receiving data.
        self.rx_data = None
        self.tx_data = tx_data

        # Current state.
        self.rx_state = 'idle'
        self.tx_state = 'idle'

        # Callbacks for pushing/pulling new data.
        self.rx_cb = rx_cb

        # Convert TX data into an array of 8b integers for pushing data in one
        # bit at a time in 8b chunks.
        self.tx_data = [x for x, in struct.iter_unpack('<B', self.tx_data)]

    # Rising edge of the clock.
    def rising_edge(self, rx, tx_start):
        if rx is None:
            raise Exception('RX is not connected!')

        self._rising_edge_rx(rx)
        return self._rising_edge_tx(tx_start)

    # Handle incoming data.
    def _rising_edge_rx(self, rx):
        if self.rx_state == 'idle':
            # Move out of the idle state if we see the start bit (0). This means
            # the chip is now in START so the next cycle will be data.
            if rx == 0:
                if self.verbose:
                    self.log('UART RX start')

                if self.rx_data is not None:
                    raise Exception(
                        f'Data in RX buffer at start: {self.rx_data}'
                    )

                self.rx_state = 'data'
                self.rx_data = ''
        elif self.rx_state == 'data':
            # Stay in the data state until we have all the required bits.
            self.rx_data = f'{rx}{self.rx_data}'

            if len(self.rx_data) == self.data_bits:
                data = int(self.rx_data, 2)
                self.rx_data = None
                self.rx_state = 'idle'

                if self.verbose:
                    self.log(f'UART RX data: 0x{data:02x}')

                self.rx_cb(data)
        else:
            raise Exception(f'Unknown RX state: {self.rx_state}')

    # Handle outgoing data.
    def _rising_edge_tx(self, tx_start):
        tx_data = 1

        if self.tx_state == 'idle':
            # If we're idle and get a new start signal then send START and move
            # into the first data state.
            if tx_start:
                tx_data = 0
                self.tx_state = 'data0'

                if self.verbose:
                    self.log('UART TX start')

                if not self.tx_data:
                    raise Exception('No UART TX data to send!')

                if self.verbose:
                    self.log(f'UART TX data: 0x{self.tx_data[0]:02x}')
        elif self.tx_state.startswith('data'):
            cycle = int(self.tx_state[-1])

            # Extract the next bit and shift it out.
            tx_data = self.tx_data[0] & 1
            self.tx_data[0] >>= 1

            # If this is the final cycle then pop it of the input buffer and
            # move back to idle, otherwise send the next bit.
            if cycle >= 7:
                self.tx_state = 'idle'
            else:
                self.tx_start = f'data{cycle + 1}'
        else:
            raise Exception(f'Unknown TX state: {self.tx_state}')

        return tx_data
