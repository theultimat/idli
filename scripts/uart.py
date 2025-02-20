# UART transmitter and receiver for connecting to the RTL.
class UART:
    def __init__(self, rx_cb, verbose=False, log=print):
        self.verbose = verbose
        self.log = log

        # Only support 8b data frames and a single stop bit.
        self.data_bits = 8
        self.stop_bits = 1

        # Byte buffers for sending and receiving data.
        # TODO Sending into core.
        self.rx_data = None

        # Current state.
        # TODO Transmitter state.
        self.rx_state = 'idle'

        # Callbacks for pushing/pulling new data.
        # TODO TX
        self.rx_cb = rx_cb

    # Rising edge of the clock.
    def rising_edge(self, rx):
        if rx is None:
            raise Exception('RX is not connected!')

        self._rising_edge_rx(rx)
        return self._rising_edge_tx()

    # Handle incoming data.
    def _rising_edge_rx(self, rx):
        if self.rx_state == 'idle':
            # Move out of the idle state if we see the start bit (0).
            if rx == 0:
                self.rx_state = 'start'
        elif self.rx_state == 'start':
            # Next is the incoming data so zero out buffer.
            if self.rx_data is not None:
                raise Exception(f'Data in RX buffer at start: {self.rx_data}')

            if self.verbose:
                self.log('UART RX start')

            self.rx_data = ''
            self.rx_state = 'data'
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
    def _rising_edge_tx(self):
        # TODO For now just always send the idle bit.
        return 1
