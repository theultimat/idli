BUILD_ROOT   := build
SOURCE_ROOT  := src
SCRIPTS_ROOT := scripts
TESTS_ROOT   := tests


SHELL  := /bin/bash
PYTHON := python3
PIP    := pip3


all: tests

clean:
	rm -rf $(BUILD_ROOT)

.PHONY: all clean


# Create virtual environment for running tests using cocotb.
VENV 		  := $(BUILD_ROOT)/venv
VENV_ACTIVATE := $(VENV)/bin/activate
VENV_REQS     := $(SCRIPTS_ROOT)/requirements.txt
VENV_READY    := $(VENV)/.ready

venv: $(VENV_READY)

$(VENV):
	@mkdir -p $(dir $(VENV))
	$(PYTHON) -m venv $(VENV)

$(VENV_READY): $(VENV_REQS) $(VENV)
	source $(VENV_ACTIVATE) && $(PIP) install -r $<
	touch $@

.PHONY: venv


# Build all the tests using the assembler.
ASM_DIR := $(TESTS_ROOT)/asm
WRAPPER := $(ASM_DIR)/wrapper.ia

AS      := source $(VENV_ACTIVATE) && $(PYTHON) $(SCRIPTS_ROOT)/asm.py
OBJDUMP := source $(VENV_ACTIVATE) && $(PYTHON) $(SCRIPTS_ROOT)/objdump.py

TEST_SOURCES := $(filter-out $(WRAPPER),$(wildcard $(ASM_DIR)/*.ia))
TEST_BINS    := $(patsubst %.ia,$(BUILD_ROOT)/%.iout,$(TEST_SOURCES))
TEST_DISS    := $(addsuffix .dis,$(TEST_BINS))

tests: venv $(TEST_BINS) $(TEST_DISS)

$(BUILD_ROOT)/%.iout: %.ia $(WRAPPER) $(VENV_READY)
	@mkdir -p $(@D)
	$(AS) -o $@ $<

$(BUILD_ROOT)/%.iout.dis: $(BUILD_ROOT)/%.iout $(VENV_READY)
	@mkdir -p $(@D)
	$(OBJDUMP) $< > $@

.PHONY: tests


# Run a single test on the simulator.
SIM_TEST        ?= $(BUILD_ROOT)/$(ASM_DIR)/bsort.iout
SIM_TEST_IN     ?= $(ASM_DIR)/bsort.in
SIM_TEST_OUT    ?= $(ASM_DIR)/bsort.out
SIM_TEST_TIMEOUT ?= 5000

SIM := source $(VENV_ACTIVATE) && $(PYTHON) $(SCRIPTS_ROOT)/sim.py

run_test_sim: $(SIM_TEST) $(VENV_READY)
	$(SIM) -i $(SIM_TEST_IN) -o $(SIM_TEST_OUT) -t $(SIM_TEST_TIMEOUT) $<

.PHONY: run_test_sim


# Convert SystemVerilog to Verilog.
SV2V_ROOT       := $(BUILD_ROOT)/sv2v
SV2V_SOURCE_DIR := $(SV2V_ROOT)/$(SOURCE_ROOT)
SV2V_TEST_DIR   := $(SV2V_ROOT)/$(TESTS_ROOT)

SV_SOURCES := $(wildcard $(SOURCE_ROOT)/*.sv $(TESTS_ROOT)/*.sv)
SV_HEADERS := $(wildcard $(SOURCE_ROOT)/*.svh)
V_SOURCES  := $(patsubst %.sv,$(SV2V_ROOT)/%.v,$(SV_SOURCES))

SV2V       := sv2v
SV2V_FLAGS := -I$(SOURCE_ROOT)

sv2v: $(V_SOURCES)

$(SV2V_ROOT)/%.v: %.sv $(SV_HEADERS)
	@mkdir -p $(@D)
	$(SV2V) $(SV2V_FLAGS) $< > $@

.PHONY: sv2v


# Run test on the RTL.
run_test_veri: $(SIM_TEST) $(VENV_READY)
	source $(VENV_ACTIVATE) && make -C tests \
		SIM=verilator \
		TEST_MODULE=run_test \
		IDLI_RUN_TEST_BINARY=../$(SIM_TEST) \
		IDLI_RUN_TEST_TIMEOUT=$(SIM_TEST_TIMEOUT) \
		IDLI_RUN_TEST_IN=$(SIM_TEST_IN) \
		IDLI_RUN_TEST_OUT=$(SIM_TEST_OUT)

run_test_icarus: $(SIM_TEST) $(VENV_READY) $(V_SOURCES)
	source $(VENV_ACTIVATE) && make -C tests \
		SIM=icarus \
		TEST_MODULE=run_test \
		IDLI_RUN_TEST_BINARY=../$(SIM_TEST) \
		IDLI_RUN_TEST_TIMEOUT=$(SIM_TEST_TIMEOUT) \
		IDLI_RUN_TEST_IN=$(SIM_TEST_IN) \
		IDLI_RUN_TEST_OUT=$(SIM_TEST_OUT)

.PHONY: run_test_veri run_test_icarus
