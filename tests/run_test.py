# Run a single test as specified by the environment variables.
# - IDLI_RUN_TEST_BINARY    Path to the binary of the test to run.
# - IDLI_RUN_TEST_TIMEOUT   Maximum timeout for the test in clock cycles.
# - IDLI_RUN_TEST_IN        Path to UART input file.
# - IDLI_RUN_TEST_OUT       Path to UART expected output file.

import os
import pathlib

import cocotb

import tb


# Main test running function.
@cocotb.test()
async def run_test(dut):
    # Parse arguments from the environment.
    path = pathlib.Path(os.environ['IDLI_RUN_TEST_BINARY'])
    timeout = int(os.environ['IDLI_RUN_TEST_TIMEOUT'])
    inputs = tb.load_uart_file(os.environ['IDLI_RUN_TEST_IN'])
    outputs = tb.load_uart_file(os.environ['IDLI_RUN_TEST_OUT'])

    if not path.is_file():
        raise Exception(f'Bad input binary: {path}')

    # Create the test bench for cosimulation.
    bench = tb.TestBench(dut, path, inputs, outputs)

    # Run the test.
    await bench.run()
