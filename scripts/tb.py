import struct


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
