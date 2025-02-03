BUILD_ROOT := ../build
SV_ROOT    := ../src
V_ROOT     := ../build/sv2v

# Allow the simulator to be controlled externally, but default to verilator.
export SIM    ?= verilator
TOPLEVEL_LANG := verilog

# Get a list of all the source files. If the simulator is verilator then we can
# use the SystemVerilog sources, but if not we need to use the built Verilog.
SOURCE_NAMES := $(basename $(notdir $(wildcard $(SV_ROOT)/*.sv)))
BENCH_NAME   := idli_tb_m

# Handle simulator specific details.
COMPILE_ARGS := -I$(SV_ROOT)
EXTRA_ARGS   :=
PLUSARGS     :=

ifeq ($(SIM),verilator)

COMPILE_ARGS += -Wall

EXTRA_ARGS += --trace --trace-fst --trace-structs
EXTRA_ARGS += --x-assign unique --x-initial unique

PLUSARGS += +verilator+rand+reset+2

SOURCE_DIR := $(SV_ROOT)
SOURCE_EXT := sv
BENCH_DIR  := .

else ifeq ($(SIM),icarus)

SOURCE_DIR := $(V_ROOT)/src
SOURCE_EXT := v
BENCH_DIR  := $(V_ROOT)/tests

else

$(error Unknown verilog simulator: $(SIM))

endif

# Build the full paths to the source files.
VERILOG_SOURCES := $(addprefix $(SOURCE_DIR)/,$(SOURCE_NAMES))
VERILOG_SOURCES += $(addprefix $(BENCH_DIR)/,$(BENCH_NAME))
VERILOG_SOURCES := $(addsuffix .$(SOURCE_EXT),$(VERILOG_SOURCES))

# Configure the test and module to run.
COCOTB_RESULTS_FILE := $(BUILD_ROOT)/tests/results.xml
SIM_BUILD           := $(BUILD_ROOT)/tests/sim_build
TOPLEVEL            := $(BENCH_NAME)
MODULE              ?= run_test

# Set the various environment variables. These are largely configured by the
# main Makefile in the root of the repository.
export IDLI_RUN_TEST_BINARY  ?=
export IDLI_RUN_TEST_TIMEOUT ?=
export IDLI_RUN_TEST_IN      ?=
export IDLI_RUN_TEST_OUT     ?=

# Make sure the python path includes the path to the scripts.
export PYTHONPATH := ../scripts:$(PYTHONPATH)


# Include the main cocotb Makefile.
include $(shell cocotb-config --makefiles)/Makefile.sim
