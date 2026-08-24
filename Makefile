# Parameterized Synchronous FIFO — build targets
RTL  = rtl/sync_fifo.v
TB   = tb/tb_sync_fifo.v
SIM  = build/fifo_sim

.PHONY: all sim wave synth clean

all: sim

sim: $(SIM)
	cd build && vvp fifo_sim

$(SIM): $(RTL) $(TB)
	mkdir -p build
	iverilog -o $(SIM) $(RTL) $(TB)

wave: sim
	gtkwave build/fifo.vcd &

synth:
	yosys -p "read_verilog $(RTL); synth_xilinx -top sync_fifo; stat"

clean:
	rm -rf build
