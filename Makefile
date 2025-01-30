BUILD_ROOT   := build
SCRIPTS_ROOT := scripts
TESTS_ROOT   := tests


PYTHON := python3


all: tests

clean:
	rm -rf $(BUILD_ROOT)


# Build all the tests using the assembler.
ASM_DIR := $(TESTS_ROOT)/asm
WRAPPER := $(ASM_DIR)/wrapper.ia

AS      := $(PYTHON) $(SCRIPTS_ROOT)/asm.py
OBJDUMP := $(PYTHON) $(SCRIPTS_ROOT)/objdump.py

TEST_SOURCES := $(filter-out $(WRAPPER),$(wildcard $(ASM_DIR)/*.ia))
TEST_BINS    := $(patsubst %.ia,$(BUILD_ROOT)/%.iout,$(TEST_SOURCES))
TEST_DISS    := $(addsuffix .dis,$(TEST_BINS))

tests: $(TEST_BINS) $(TEST_DISS)

$(BUILD_ROOT)/%.iout: %.ia
	@mkdir -p $(@D)
	$(AS) -o $@ $<

$(BUILD_ROOT)/%.iout.dis: $(BUILD_ROOT)/%.iout
	@mkdir -p $(@D)
	$(OBJDUMP) $< > $@


# Run a single test on the simulator.
SIM_TEST     ?= $(BUILD_ROOT)/$(ASM_DIR)/bsort.iout
SIM_TEST_IN  ?= 5:-4:10:-100:44:999
SIM_TEST_OUT ?= :-100:-4:10:44:999

SIM := $(PYTHON) $(SCRIPTS_ROOT)/sim.py

run_sim_test: $(SIM_TEST)
	$(SIM) -i $(SIM_TEST_IN) -o $(SIM_TEST_OUT) $(SIM_TEST)


.PHONY: all clean tests run_sim_test
