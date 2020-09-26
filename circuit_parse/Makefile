all:
	# iverilog -o PicoRV32_02 ./testbench.v ./picorv32_rewrite_format.v  ./picorv32_pcpi_div.v ./picorv32_pcpi_fast_mul.v 
	iverilog -o PicoRV32_02 ./testbench.v ./picorv32_display.v  ./picorv32_pcpi_div_display.v ./picorv32_pcpi_fast_mul_display.v 

	# ./PicoRV32_02 +hex=../../dhrystone/dhry.hex +vcd=dhrystone.vcd
	./PicoRV32_02 +hex=./string.hex +vcd=string.vcd

clean:
	rm -rf INCA_libs nWaveLog
	rm -rf ncverilog.log
	rm -rf novas_dump.log
	rm -rf *~
	rm -rf *.rc
	rm -rf *.vec
	rm -rf PicoRV32_0*
	rm -rf *.vcd
	rm -rf *.txt
