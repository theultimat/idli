# Run a single test as specified by the environment variables.

import os
import pathlib
import sys

import cocotb


# Main test running function.
@cocotb.test()
async def run_test(dut):
    # Parse arguments from the environment.
    path = pathlib.Path(os.environ['IDLI_RUN_TEST_BINARY'])
    timeout = int(os.environ['IDLI_RUN_TEST_TIMEOUT'])

    if not path.is_file():
        raise Exception(f'Bad input binary: {path}')

    dut._log.info(f'Hello! {path} {timeout}')
