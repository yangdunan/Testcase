/* 
*  PicoRV32 -- A Small RISC-V (RV32I) Processor Core 
* 
$fwrite(f,"%0d cycle :picorv32.v:5\n"  , count_cycle); 
*  Copyright (C) 2015  Clifford Wolf <clifford@clifford.at> 
* 
*  Permission to use, copy, modify, and/or distribute this software for any 
*  purpose with or without fee is hereby granted, provided that the above 
*  copyright notice and this permission notice appear in all copies. 
* 
*  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES 
*  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF 
*  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR 
*  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES 
*  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN 
*  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF 
*  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE. 
* 
*/ 
 
`timescale 1 ns / 1 ps 
// `default_nettype none 
// `define DEBUGNETS 
`define DEBUGREGS 
// `define DEBUGASM 
// `define DEBUG 
 
`ifdef DEBUG 
`define debug(debug_command) debug_command 
`else 
`define debug(debug_command) 
`endif 
 
`ifdef FORMAL 
`define FORMAL_KEEP (* keep *) 
`define assert(assert_expr) assert(assert_expr) 
`else 
`ifdef DEBUGNETS 
`define FORMAL_KEEP (* keep *) 
`else 
`define FORMAL_KEEP 
`endif 
`define assert(assert_expr) empty_statement 
`endif 
 
// uncomment this for register file in extra module 
// `define PICORV32_REGS picorv32_regs 
 
// this macro can be used to check if the verilog files in your 
// design are read in the correct order. 
`define PICORV32_V 
 
 
/*************************************************************** 
* picorv32 
***************************************************************/ 
 
module picorv32 #( 
parameter [ 0:0] ENABLE_COUNTERS = 1, 
parameter [ 0:0] ENABLE_COUNTERS64 = 1, 
parameter [ 0:0] ENABLE_REGS_16_31 = 1, 
parameter [ 0:0] ENABLE_REGS_DUALPORT = 1, 
parameter [ 0:0] LATCHED_MEM_RDATA = 0, 
parameter [ 0:0] TWO_STAGE_SHIFT = 1, 
parameter [ 0:0] BARREL_SHIFTER = 1, // ssliao 
parameter [ 0:0] TWO_CYCLE_COMPARE = 0, 
parameter [ 0:0] TWO_CYCLE_ALU = 0, 
parameter [ 0:0] COMPRESSED_ISA = 0, 
parameter [ 0:0] CATCH_MISALIGN = 1, 
parameter [ 0:0] CATCH_ILLINSN = 1, 
parameter [ 0:0] ENABLE_PCPI = 0, 
parameter [ 0:0] ENABLE_MUL = 0, 
parameter [ 0:0] ENABLE_FAST_MUL = 1, // ssliao 
parameter [ 0:0] ENABLE_DIV = 1, // ssliao 
parameter [ 0:0] ENABLE_IRQ = 0, 
parameter [ 0:0] ENABLE_IRQ_QREGS = 1, 
parameter [ 0:0] ENABLE_IRQ_TIMER = 1, 
parameter [ 0:0] ENABLE_TRACE = 0, 
parameter [ 0:0] REGS_INIT_ZERO = 0, 
parameter [31:0] MASKED_IRQ = 32'h 0000_0000, 
parameter [31:0] LATCHED_IRQ = 32'h ffff_ffff, 
parameter [31:0] PROGADDR_RESET = 32'h 0001_0000, // ssliao 
parameter [31:0] PROGADDR_IRQ = 32'h 0000_0010, 
parameter [31:0] STACKADDR = 32'h 0001_0000 // ssliao 
) ( 
input clk, resetn, 
output reg trap, 
 
output reg        mem_valid, 
output reg        mem_instr, 
input             mem_ready, 
 
output reg [31:0] mem_addr, 
output reg [31:0] mem_wdata, 
output reg [ 3:0] mem_wstrb, 
input      [31:0] mem_rdata, 
 
// Look-Ahead Interface 
output            mem_la_read, 
output            mem_la_write, 
output     [31:0] mem_la_addr, 
output reg [31:0] mem_la_wdata, 
output reg [ 3:0] mem_la_wstrb, 
 
// Pico Co-Processor Interface (PCPI) 
output reg        pcpi_valid, 
output reg [31:0] pcpi_insn, 
output     [31:0] pcpi_rs1, 
output     [31:0] pcpi_rs2, 
input             pcpi_wr, 
input      [31:0] pcpi_rd, 
input             pcpi_wait, 
input             pcpi_ready, 
 
// IRQ Interface 
input      [31:0] irq, 
output reg [31:0] eoi, 
 
`ifdef RISCV_FORMAL 
output reg        rvfi_valid, 
output reg [63:0] rvfi_order, 
output reg [31:0] rvfi_insn, 
output reg        rvfi_trap, 
output reg        rvfi_halt, 
output reg        rvfi_intr, 
output reg [ 1:0] rvfi_mode, 
output reg [ 4:0] rvfi_rs1_addr, 
output reg [ 4:0] rvfi_rs2_addr, 
output reg [31:0] rvfi_rs1_rdata, 
output reg [31:0] rvfi_rs2_rdata, 
output reg [ 4:0] rvfi_rd_addr, 
output reg [31:0] rvfi_rd_wdata, 
output reg [31:0] rvfi_pc_rdata, 
output reg [31:0] rvfi_pc_wdata, 
output reg [31:0] rvfi_mem_addr, 
output reg [ 3:0] rvfi_mem_rmask, 
output reg [ 3:0] rvfi_mem_wmask, 
output reg [31:0] rvfi_mem_rdata, 
output reg [31:0] rvfi_mem_wdata, 
`endif 
 
// Trace Interface 
output reg        trace_valid, 
output reg [35:0] trace_data 
); 
integer f ; 
localparam integer irq_timer = 0; 
localparam integer irq_ebreak = 1; 
localparam integer irq_buserror = 2; 
 
localparam integer irqregs_offset = ENABLE_REGS_16_31 ? 32 : 16; 
localparam integer regfile_size = (ENABLE_REGS_16_31 ? 32 : 16) + 4*ENABLE_IRQ*ENABLE_IRQ_QREGS; 
localparam integer regindex_bits = (ENABLE_REGS_16_31 ? 5 : 4) + ENABLE_IRQ*ENABLE_IRQ_QREGS; 
 
localparam WITH_PCPI = ENABLE_PCPI || ENABLE_MUL || ENABLE_FAST_MUL || ENABLE_DIV; 
 
localparam [35:0] TRACE_BRANCH = {4'b 0001, 32'b 0}; 
localparam [35:0] TRACE_ADDR   = {4'b 0010, 32'b 0}; 
localparam [35:0] TRACE_IRQ    = {4'b 1000, 32'b 0}; 
 
reg [63:0] count_cycle, count_instr; 
reg [31:0] reg_pc, reg_next_pc, reg_op1, reg_op2, reg_out; 
reg [4:0] reg_sh; 
 
reg [31:0] next_insn_opcode; 
reg [31:0] dbg_insn_opcode; 
reg [31:0] dbg_insn_addr; 
 
wire dbg_mem_valid = mem_valid; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:169\n"  , count_cycle); 
end 
wire dbg_mem_instr = mem_instr; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:173\n"  , count_cycle); 
end 
wire dbg_mem_ready = mem_ready; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:177\n"  , count_cycle); 
end 
wire [31:0] dbg_mem_addr  = mem_addr; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:181\n"  , count_cycle); 
end 
wire [31:0] dbg_mem_wdata = mem_wdata; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:185\n"  , count_cycle); 
end 
wire [ 3:0] dbg_mem_wstrb = mem_wstrb; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:189\n"  , count_cycle); 
end 
wire [31:0] dbg_mem_rdata = mem_rdata; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:193\n"  , count_cycle); 
end 
 
assign pcpi_rs1 = reg_op1; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:198\n"  , count_cycle); 
end 
assign pcpi_rs2 = reg_op2; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:202\n"  , count_cycle); 
end 
 
wire [31:0] next_pc; 
 
reg irq_delay; 
reg irq_active; 
reg [31:0] irq_mask; 
reg [31:0] irq_pending; 
reg [31:0] timer; 
 
`ifndef PICORV32_REGS 
reg [31:0] cpuregs [0:regfile_size-1]; 
 
integer i; 
initial begin 
f = $fopen("cpu_rw_1.txt", "w"); 
$fwrite(f,"%0d cycle :picorv32.v:220\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:223\n"  , count_cycle); 
if (REGS_INIT_ZERO) begin 
for (i = 0; i < regfile_size; i = i+1)cpuregs[i] = 0; 
end 
end 
`endif 
 
task empty_statement; 
// This task is used by the `assert directive in non-formal mode to 
// avoid empty statement (which are unsupported by plain Verilog syntax). 
begin end 
endtask 
 
`ifdef DEBUGREGS 
wire [31:0] dbg_reg_x0  = 0; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:236\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x1  = cpuregs[1]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:240\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x2  = cpuregs[2]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:244\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x3  = cpuregs[3]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:248\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x4  = cpuregs[4]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:252\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x5  = cpuregs[5]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:256\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x6  = cpuregs[6]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:260\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x7  = cpuregs[7]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:264\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x8  = cpuregs[8]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:268\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x9  = cpuregs[9]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:272\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x10 = cpuregs[10]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:276\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x11 = cpuregs[11]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:280\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x12 = cpuregs[12]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:284\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x13 = cpuregs[13]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:288\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x14 = cpuregs[14]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:292\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x15 = cpuregs[15]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:296\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x16 = cpuregs[16]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:300\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x17 = cpuregs[17]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:304\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x18 = cpuregs[18]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:308\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x19 = cpuregs[19]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:312\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x20 = cpuregs[20]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:316\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x21 = cpuregs[21]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:320\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x22 = cpuregs[22]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:324\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x23 = cpuregs[23]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:328\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x24 = cpuregs[24]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:332\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x25 = cpuregs[25]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:336\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x26 = cpuregs[26]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:340\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x27 = cpuregs[27]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:344\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x28 = cpuregs[28]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:348\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x29 = cpuregs[29]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:352\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x30 = cpuregs[30]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:356\n"  , count_cycle); 
end 
wire [31:0] dbg_reg_x31 = cpuregs[31]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:360\n"  , count_cycle); 
end 
`endif 
 
// Internal PCPI Cores 
 
wire        pcpi_mul_wr; 
wire [31:0] pcpi_mul_rd; 
wire        pcpi_mul_wait; 
wire        pcpi_mul_ready; 
 
wire        pcpi_div_wr; 
wire [31:0] pcpi_div_rd; 
wire        pcpi_div_wait; 
wire        pcpi_div_ready; 
 
reg        pcpi_int_wr; 
reg [31:0] pcpi_int_rd; 
reg        pcpi_int_wait; 
reg        pcpi_int_ready; 
 

generate if (ENABLE_FAST_MUL) begin 
picorv32_pcpi_fast_mul pcpi_mul ( 
.clk       (clk            ), 
.resetn    (resetn         ), 
.pcpi_valid(pcpi_valid     ), 
.pcpi_insn (pcpi_insn      ), 
.pcpi_rs1  (pcpi_rs1       ), 
.pcpi_rs2  (pcpi_rs2       ), 
.pcpi_wr   (pcpi_mul_wr    ), 
.pcpi_rd   (pcpi_mul_rd    ), 
.pcpi_wait (pcpi_mul_wait  ), 
.pcpi_ready(pcpi_mul_ready ) 
); 

end else if (ENABLE_MUL) begin 
picorv32_pcpi_mul pcpi_mul ( 
.clk       (clk            ), 
.resetn    (resetn         ), 
.pcpi_valid(pcpi_valid     ), 
.pcpi_insn (pcpi_insn      ), 
.pcpi_rs1  (pcpi_rs1       ), 
.pcpi_rs2  (pcpi_rs2       ), 
.pcpi_wr   (pcpi_mul_wr    ), 
.pcpi_rd   (pcpi_mul_rd    ), 
.pcpi_wait (pcpi_mul_wait  ), 
.pcpi_ready(pcpi_mul_ready ) 
); 
end else begin 
assign pcpi_mul_wr = 0; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:412\n"  , count_cycle); 
end 
assign pcpi_mul_rd = 32'bx; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:416\n"  , count_cycle); 
end 
assign pcpi_mul_wait = 0; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:420\n"  , count_cycle); 
end 
assign pcpi_mul_ready = 0; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:424\n"  , count_cycle); 
end 
end endgenerate 
 

generate if (ENABLE_DIV) begin 
picorv32_pcpi_div pcpi_div ( 
.clk       (clk            ), 
.resetn    (resetn         ), 
.pcpi_valid(pcpi_valid     ), 
.pcpi_insn (pcpi_insn      ), 
.pcpi_rs1  (pcpi_rs1       ), 
.pcpi_rs2  (pcpi_rs2       ), 
.pcpi_wr   (pcpi_div_wr    ), 
.pcpi_rd   (pcpi_div_rd    ), 
.pcpi_wait (pcpi_div_wait  ), 
.pcpi_ready(pcpi_div_ready ) 
); 
end else begin 
assign pcpi_div_wr = 0; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:445\n"  , count_cycle); 
end 
assign pcpi_div_rd = 32'bx; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:449\n"  , count_cycle); 
end 
assign pcpi_div_wait = 0; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:453\n"  , count_cycle); 
end 
assign pcpi_div_ready = 0; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:457\n"  , count_cycle); 
end 
end endgenerate 
 
always @* begin 
pcpi_int_wr = 0; 
$fwrite(f,"%0d cycle :picorv32.v:464\n"  , count_cycle); 
pcpi_int_rd = 32'bx; 
$fwrite(f,"%0d cycle :picorv32.v:466\n"  , count_cycle); 
pcpi_int_wait  = |{ENABLE_PCPI && pcpi_wait,  (ENABLE_MUL || ENABLE_FAST_MUL) && pcpi_mul_wait,  ENABLE_DIV && pcpi_div_wait}; 
$fwrite(f,"%0d cycle :picorv32.v:468\n"  , count_cycle); 
pcpi_int_ready = |{ENABLE_PCPI && pcpi_ready, (ENABLE_MUL || ENABLE_FAST_MUL) && pcpi_mul_ready, ENABLE_DIV && pcpi_div_ready}; 
$fwrite(f,"%0d cycle :picorv32.v:470\n"  , count_cycle); 
 

(* parallel_case *) 

case (1'b1) 
ENABLE_PCPI && pcpi_ready: begin 
pcpi_int_wr = ENABLE_PCPI ? pcpi_wr : 0; 
$fwrite(f,"%0d cycle :picorv32.v:478\n"  , count_cycle); 
pcpi_int_rd = ENABLE_PCPI ? pcpi_rd : 0; 
$fwrite(f,"%0d cycle :picorv32.v:480\n"  , count_cycle); 
end 
(ENABLE_MUL || ENABLE_FAST_MUL) && pcpi_mul_ready: begin 
pcpi_int_wr = pcpi_mul_wr; 
$fwrite(f,"%0d cycle :picorv32.v:484\n"  , count_cycle); 
pcpi_int_rd = pcpi_mul_rd; 
$fwrite(f,"%0d cycle :picorv32.v:486\n"  , count_cycle); 
end 
ENABLE_DIV && pcpi_div_ready: begin 
pcpi_int_wr = pcpi_div_wr; 
$fwrite(f,"%0d cycle :picorv32.v:490\n"  , count_cycle); 
pcpi_int_rd = pcpi_div_rd; 
$fwrite(f,"%0d cycle :picorv32.v:492\n"  , count_cycle); 
end 
endcase 
end 
 
 
// Memory Interface 
 
reg [1:0] mem_state; 
reg [1:0] mem_wordsize; 
reg [31:0] mem_rdata_word; 
reg [31:0] mem_rdata_q; 
reg mem_do_prefetch; 
reg mem_do_rinst; 
reg mem_do_rdata; 
reg mem_do_wdata; 
 
wire mem_xfer; 
reg mem_la_secondword, mem_la_firstword_reg, last_mem_valid; 
wire mem_la_firstword = COMPRESSED_ISA && (mem_do_prefetch || mem_do_rinst) && next_pc[1] && !mem_la_secondword; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:512\n"  , count_cycle); 
end 
wire mem_la_firstword_xfer = COMPRESSED_ISA && mem_xfer && (!last_mem_valid ? mem_la_firstword : mem_la_firstword_reg); 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:516\n"  , count_cycle); 
end 
 
reg prefetched_high_word; 
reg clear_prefetched_high_word; 
reg [15:0] mem_16bit_buffer; 
 
wire [31:0] mem_rdata_latched_noshuffle; 
wire [31:0] mem_rdata_latched; 
 
wire mem_la_use_prefetched_high_word = COMPRESSED_ISA && mem_la_firstword && prefetched_high_word && !clear_prefetched_high_word; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:528\n"  , count_cycle); 
end 
assign mem_xfer = (mem_valid && mem_ready) || (mem_la_use_prefetched_high_word && mem_do_rinst); 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:532\n"  , count_cycle); 
end 
 
wire mem_busy = |{mem_do_prefetch, mem_do_rinst, mem_do_rdata, mem_do_wdata}; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:537\n"  , count_cycle); 
end 
wire mem_done = resetn && ((mem_xfer && |mem_state && (mem_do_rinst || mem_do_rdata || mem_do_wdata)) || (&mem_state && mem_do_rinst)) &&(!mem_la_firstword || (~&mem_rdata_latched[1:0] && mem_xfer)); 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:541\n"  , count_cycle); 
end 
 
assign mem_la_write = resetn && !mem_state && mem_do_wdata; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:546\n"  , count_cycle); 
end 
assign mem_la_read = resetn && ((!mem_la_use_prefetched_high_word && !mem_state && (mem_do_rinst || mem_do_prefetch || mem_do_rdata)) ||(COMPRESSED_ISA && mem_xfer && (!last_mem_valid ? mem_la_firstword : mem_la_firstword_reg) && !mem_la_secondword && &mem_rdata_latched[1:0])); 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:550\n"  , count_cycle); 
end 
assign mem_la_addr = (mem_do_prefetch || mem_do_rinst) ? {next_pc[31:2] + mem_la_firstword_xfer, 2'b00} : {reg_op1[31:2], 2'b00}; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:554\n"  , count_cycle); 
end 
 
assign mem_rdata_latched_noshuffle = (mem_xfer || LATCHED_MEM_RDATA) ? mem_rdata : mem_rdata_q; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:559\n"  , count_cycle); 
end 
 
assign mem_rdata_latched = COMPRESSED_ISA && mem_la_use_prefetched_high_word ? {16'bx, mem_16bit_buffer} :COMPRESSED_ISA && mem_la_secondword ? {mem_rdata_latched_noshuffle[15:0], mem_16bit_buffer} :COMPRESSED_ISA && mem_la_firstword ? {16'bx, mem_rdata_latched_noshuffle[31:16]} : mem_rdata_latched_noshuffle; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:564\n"  , count_cycle); 
end 
 
always @(posedge clk) begin 
$fwrite(f,"%0d cycle :picorv32.v:571\n"  , count_cycle); 
if (!resetn) begin 
mem_la_firstword_reg <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:572\n"  , count_cycle); 
last_mem_valid <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:574\n"  , count_cycle); 
end else begin 
$fwrite(f,"%0d cycle :picorv32.v:578\n"  , count_cycle); 
if (!last_mem_valid) begin 
mem_la_firstword_reg <= mem_la_firstword; 
$fwrite(f,"%0d cycle :picorv32.v:579\n"  , count_cycle); 
end 
last_mem_valid <= mem_valid && !mem_ready; 
$fwrite(f,"%0d cycle :picorv32.v:582\n"  , count_cycle); 
end 
end 
 
always @* begin 
$fwrite(f,"%0d cycle :picorv32.v:589\n"  , count_cycle); 
(* full_case *) 
$fwrite(f,"%0d cycle :picorv32.v:591\n"  , count_cycle); 
case (mem_wordsize) 
0: begin 
mem_la_wdata = reg_op2; 
$fwrite(f,"%0d cycle :picorv32.v:593\n"  , count_cycle); 
mem_la_wstrb = 4'b1111; 
$fwrite(f,"%0d cycle :picorv32.v:595\n"  , count_cycle); 
mem_rdata_word = mem_rdata; 
$fwrite(f,"%0d cycle :picorv32.v:597\n"  , count_cycle); 
end 
1: begin 
mem_la_wdata = {2{reg_op2[15:0]}}; 
$fwrite(f,"%0d cycle :picorv32.v:601\n"  , count_cycle); 
mem_la_wstrb = reg_op1[1] ? 4'b1100 : 4'b0011; 
$fwrite(f,"%0d cycle :picorv32.v:603\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:606\n"  , count_cycle); 
case (reg_op1[1]) 
1'b0: begin 
mem_rdata_word = {16'b0, mem_rdata[15: 0]}; 
$fwrite(f,"%0d cycle :picorv32.v:608\n"  , count_cycle); 
end 
1'b1: begin 
mem_rdata_word = {16'b0, mem_rdata[31:16]}; 
$fwrite(f,"%0d cycle :picorv32.v:612\n"  , count_cycle); 
end 
endcase 
end 
2: begin 
mem_la_wdata = {4{reg_op2[7:0]}}; 
$fwrite(f,"%0d cycle :picorv32.v:618\n"  , count_cycle); 
mem_la_wstrb = 4'b0001 << reg_op1[1:0]; 
$fwrite(f,"%0d cycle :picorv32.v:620\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:623\n"  , count_cycle); 
case (reg_op1[1:0]) 
2'b00: begin 
mem_rdata_word = {24'b0, mem_rdata[ 7: 0]}; 
$fwrite(f,"%0d cycle :picorv32.v:625\n"  , count_cycle); 
end 
2'b01: begin 
mem_rdata_word = {24'b0, mem_rdata[15: 8]}; 
$fwrite(f,"%0d cycle :picorv32.v:629\n"  , count_cycle); 
end 
2'b10: begin 
mem_rdata_word = {24'b0, mem_rdata[23:16]}; 
$fwrite(f,"%0d cycle :picorv32.v:633\n"  , count_cycle); 
end 
2'b11: begin 
mem_rdata_word = {24'b0, mem_rdata[31:24]}; 
$fwrite(f,"%0d cycle :picorv32.v:637\n"  , count_cycle); 
end 
endcase 
end 
endcase 
end 
 
always @(posedge clk) begin 
$fwrite(f,"%0d cycle :picorv32.v:647\n"  , count_cycle); 
if (mem_xfer) begin 
mem_rdata_q <= COMPRESSED_ISA ? mem_rdata_latched : mem_rdata; 
$fwrite(f,"%0d cycle :picorv32.v:648\n"  , count_cycle); 
next_insn_opcode <= COMPRESSED_ISA ? mem_rdata_latched : mem_rdata; 
$fwrite(f,"%0d cycle :picorv32.v:650\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :picorv32.v:655\n"  , count_cycle); 
if (COMPRESSED_ISA && mem_done && (mem_do_prefetch || mem_do_rinst)) begin 
$fwrite(f,"%0d cycle :picorv32.v:657\n"  , count_cycle); 
case (mem_rdata_latched[1:0]) 
2'b00: begin // Quadrant 0 
$fwrite(f,"%0d cycle :picorv32.v:660\n"  , count_cycle); 
case (mem_rdata_latched[15:13]) 
3'b000: begin // C.ADDI4SPN 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0d cycle :picorv32.v:662\n"  , count_cycle); 
mem_rdata_q[31:20] <= {2'b0, mem_rdata_latched[10:7], mem_rdata_latched[12:11], mem_rdata_latched[5], mem_rdata_latched[6], 2'b00}; 
$fwrite(f,"%0d cycle :picorv32.v:664\n"  , count_cycle); 
end 
3'b010: begin // C.LW 
mem_rdata_q[31:20] <= {5'b0, mem_rdata_latched[5], mem_rdata_latched[12:10], mem_rdata_latched[6], 2'b00}; 
$fwrite(f,"%0d cycle :picorv32.v:668\n"  , count_cycle); 
mem_rdata_q[14:12] <= 3'b 010; 
$fwrite(f,"%0d cycle :picorv32.v:670\n"  , count_cycle); 
end 
3'b 110: begin // C.SW 
{mem_rdata_q[31:25], mem_rdata_q[11:7]} <= {5'b0, mem_rdata_latched[5], mem_rdata_latched[12:10], mem_rdata_latched[6], 2'b00}; 
$fwrite(f,"%0d cycle :picorv32.v:674\n"  , count_cycle); 
mem_rdata_q[14:12] <= 3'b 010; 
$fwrite(f,"%0d cycle :picorv32.v:676\n"  , count_cycle); 
end 
endcase 
end 
2'b01: begin // Quadrant 1 
$fwrite(f,"%0d cycle :picorv32.v:683\n"  , count_cycle); 
case (mem_rdata_latched[15:13]) 
3'b 000: begin // C.ADDI 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0d cycle :picorv32.v:685\n"  , count_cycle); 
mem_rdata_q[31:20] <= $signed({mem_rdata_latched[12], mem_rdata_latched[6:2]}); 
$fwrite(f,"%0d cycle :picorv32.v:687\n"  , count_cycle); 
end 
3'b 010: begin // C.LI 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0d cycle :picorv32.v:691\n"  , count_cycle); 
mem_rdata_q[31:20] <= $signed({mem_rdata_latched[12], mem_rdata_latched[6:2]}); 
$fwrite(f,"%0d cycle :picorv32.v:693\n"  , count_cycle); 
end 
3'b 011: begin 
$fwrite(f,"%0d cycle :picorv32.v:697\n"  , count_cycle); 
if (mem_rdata_latched[11:7] == 2) begin // C.ADDI16SP 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0d cycle :picorv32.v:699\n"  , count_cycle); 
mem_rdata_q[31:20] <= $signed({mem_rdata_latched[12], mem_rdata_latched[4:3],mem_rdata_latched[5], mem_rdata_latched[2], mem_rdata_latched[6], 4'b 0000}); 
$fwrite(f,"%0d cycle :picorv32.v:701\n"  , count_cycle); 
end else begin // C.LUI 
mem_rdata_q[31:12] <= $signed({mem_rdata_latched[12], mem_rdata_latched[6:2]}); 
$fwrite(f,"%0d cycle :picorv32.v:704\n"  , count_cycle); 
end 
end 
3'b100: begin 
$fwrite(f,"%0d cycle :picorv32.v:709\n"  , count_cycle); 
if (mem_rdata_latched[11:10] == 2'b00) begin // C.SRLI 
mem_rdata_q[31:25] <= 7'b0000000; 
$fwrite(f,"%0d cycle :picorv32.v:711\n"  , count_cycle); 
mem_rdata_q[14:12] <= 3'b 101; 
$fwrite(f,"%0d cycle :picorv32.v:713\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:716\n"  , count_cycle); 
if (mem_rdata_latched[11:10] == 2'b01) begin // C.SRAI 
mem_rdata_q[31:25] <= 7'b0100000; 
$fwrite(f,"%0d cycle :picorv32.v:718\n"  , count_cycle); 
mem_rdata_q[14:12] <= 3'b 101; 
$fwrite(f,"%0d cycle :picorv32.v:720\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:723\n"  , count_cycle); 
if (mem_rdata_latched[11:10] == 2'b10) begin // C.ANDI 
mem_rdata_q[14:12] <= 3'b111; 
$fwrite(f,"%0d cycle :picorv32.v:725\n"  , count_cycle); 
mem_rdata_q[31:20] <= $signed({mem_rdata_latched[12], mem_rdata_latched[6:2]}); 
$fwrite(f,"%0d cycle :picorv32.v:727\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:730\n"  , count_cycle); 
if (mem_rdata_latched[12:10] == 3'b011) begin // C.SUB, C.XOR, C.OR, C.AND 
$fwrite(f,"%0d cycle :picorv32.v:732\n"  , count_cycle); 
if (mem_rdata_latched[6:5] == 2'b00) begin 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0d cycle :picorv32.v:734\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:737\n"  , count_cycle); 
if (mem_rdata_latched[6:5] == 2'b01) begin 
mem_rdata_q[14:12] <= 3'b100; 
$fwrite(f,"%0d cycle :picorv32.v:739\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:742\n"  , count_cycle); 
if (mem_rdata_latched[6:5] == 2'b10) begin 
mem_rdata_q[14:12] <= 3'b110; 
$fwrite(f,"%0d cycle :picorv32.v:744\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:747\n"  , count_cycle); 
if (mem_rdata_latched[6:5] == 2'b11) begin 
mem_rdata_q[14:12] <= 3'b111; 
$fwrite(f,"%0d cycle :picorv32.v:749\n"  , count_cycle); 
end 
mem_rdata_q[31:25] <= mem_rdata_latched[6:5] == 2'b00 ? 7'b0100000 : 7'b0000000; 
$fwrite(f,"%0d cycle :picorv32.v:752\n"  , count_cycle); 
end 
end 
3'b 110: begin // C.BEQZ 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0d cycle :picorv32.v:757\n"  , count_cycle); 
{ mem_rdata_q[31], mem_rdata_q[7], mem_rdata_q[30:25], mem_rdata_q[11:8] } <=$signed({mem_rdata_latched[12], mem_rdata_latched[6:5], mem_rdata_latched[2],mem_rdata_latched[11:10], mem_rdata_latched[4:3]}); 
$fwrite(f,"%0d cycle :picorv32.v:759\n"  , count_cycle); 
end 
3'b 111: begin // C.BNEZ 
mem_rdata_q[14:12] <= 3'b001; 
$fwrite(f,"%0d cycle :picorv32.v:763\n"  , count_cycle); 
{ mem_rdata_q[31], mem_rdata_q[7], mem_rdata_q[30:25], mem_rdata_q[11:8] } <=$signed({mem_rdata_latched[12], mem_rdata_latched[6:5], mem_rdata_latched[2],mem_rdata_latched[11:10], mem_rdata_latched[4:3]}); 
$fwrite(f,"%0d cycle :picorv32.v:765\n"  , count_cycle); 
end 
endcase 
end 
2'b10: begin // Quadrant 2 
$fwrite(f,"%0d cycle :picorv32.v:772\n"  , count_cycle); 
case (mem_rdata_latched[15:13]) 
3'b000: begin // C.SLLI 
mem_rdata_q[31:25] <= 7'b0000000; 
$fwrite(f,"%0d cycle :picorv32.v:774\n"  , count_cycle); 
mem_rdata_q[14:12] <= 3'b 001; 
$fwrite(f,"%0d cycle :picorv32.v:776\n"  , count_cycle); 
end 
3'b010: begin // C.LWSP 
mem_rdata_q[31:20] <= {4'b0, mem_rdata_latched[3:2], mem_rdata_latched[12], mem_rdata_latched[6:4], 2'b00}; 
$fwrite(f,"%0d cycle :picorv32.v:780\n"  , count_cycle); 
mem_rdata_q[14:12] <= 3'b 010; 
$fwrite(f,"%0d cycle :picorv32.v:782\n"  , count_cycle); 
end 
3'b100: begin 
$fwrite(f,"%0d cycle :picorv32.v:786\n"  , count_cycle); 
if (mem_rdata_latched[12] == 0 && mem_rdata_latched[6:2] == 0) begin // C.JR 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0d cycle :picorv32.v:788\n"  , count_cycle); 
mem_rdata_q[31:20] <= 12'b0; 
$fwrite(f,"%0d cycle :picorv32.v:790\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:793\n"  , count_cycle); 
if (mem_rdata_latched[12] == 0 && mem_rdata_latched[6:2] != 0) begin // C.MV 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0d cycle :picorv32.v:795\n"  , count_cycle); 
mem_rdata_q[31:25] <= 7'b0000000; 
$fwrite(f,"%0d cycle :picorv32.v:797\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:800\n"  , count_cycle); 
if (mem_rdata_latched[12] != 0 && mem_rdata_latched[11:7] != 0 && mem_rdata_latched[6:2] == 0) begin // C.JALR 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0d cycle :picorv32.v:802\n"  , count_cycle); 
mem_rdata_q[31:20] <= 12'b0; 
$fwrite(f,"%0d cycle :picorv32.v:804\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:807\n"  , count_cycle); 
if (mem_rdata_latched[12] != 0 && mem_rdata_latched[6:2] != 0) begin // C.ADD 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0d cycle :picorv32.v:809\n"  , count_cycle); 
mem_rdata_q[31:25] <= 7'b0000000; 
$fwrite(f,"%0d cycle :picorv32.v:811\n"  , count_cycle); 
end 
end 
3'b110: begin // C.SWSP 
{mem_rdata_q[31:25], mem_rdata_q[11:7]} <= {4'b0, mem_rdata_latched[8:7], mem_rdata_latched[12:9], 2'b00}; 
$fwrite(f,"%0d cycle :picorv32.v:816\n"  , count_cycle); 
mem_rdata_q[14:12] <= 3'b 010; 
$fwrite(f,"%0d cycle :picorv32.v:818\n"  , count_cycle); 
end 
endcase 
end 
endcase 
end 
end 
 
always @(posedge clk) begin 
$fwrite(f,"%0d cycle :picorv32.v:829\n"  , count_cycle); 
if (resetn && !trap) begin 
$fwrite(f,"%0d cycle :picorv32.v:831\n"  , count_cycle); 
if (mem_do_prefetch || mem_do_rinst || mem_do_rdata) begin 
`assert(!mem_do_wdata); 
end 
 
$fwrite(f,"%0d cycle :picorv32.v:836\n"  , count_cycle); 
if (mem_do_prefetch || mem_do_rinst) begin 
`assert(!mem_do_rdata); 
end 
 
$fwrite(f,"%0d cycle :picorv32.v:841\n"  , count_cycle); 
if (mem_do_rdata) begin 
`assert(!mem_do_prefetch && !mem_do_rinst); 
end 
 
$fwrite(f,"%0d cycle :picorv32.v:846\n"  , count_cycle); 
if (mem_do_wdata) begin 
`assert(!(mem_do_prefetch || mem_do_rinst || mem_do_rdata)); 
end 
 
$fwrite(f,"%0d cycle :picorv32.v:850\n"  , count_cycle); 
if (mem_state == 2 || mem_state == 3) begin 
`assert(mem_valid || mem_do_prefetch); 
end 
end 
end 
 
always @(posedge clk) begin 
$fwrite(f,"%0d cycle :picorv32.v:859\n"  , count_cycle); 
if (!resetn || trap) begin 
$fwrite(f,"%0d cycle :picorv32.v:861\n"  , count_cycle); 
if (!resetn) begin 
mem_state <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:862\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:866\n"  , count_cycle); 
if (!resetn || mem_ready) begin 
mem_valid <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:867\n"  , count_cycle); 
end 
mem_la_secondword <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:870\n"  , count_cycle); 
prefetched_high_word <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:872\n"  , count_cycle); 
end else begin 
$fwrite(f,"%0d cycle :picorv32.v:876\n"  , count_cycle); 
if (mem_la_read || mem_la_write) begin 
mem_addr <= mem_la_addr; 
$fwrite(f,"%0d cycle :picorv32.v:877\n"  , count_cycle); 
mem_wstrb <= mem_la_wstrb & {4{mem_la_write}}; 
$fwrite(f,"%0d cycle :picorv32.v:879\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:883\n"  , count_cycle); 
if (mem_la_write) begin 
mem_wdata <= mem_la_wdata; 
$fwrite(f,"%0d cycle :picorv32.v:884\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:888\n"  , count_cycle); 
case (mem_state) 
0: begin 
$fwrite(f,"%0d cycle :picorv32.v:891\n"  , count_cycle); 
if (mem_do_prefetch || mem_do_rinst || mem_do_rdata) begin 
mem_valid <= !mem_la_use_prefetched_high_word; 
$fwrite(f,"%0d cycle :picorv32.v:892\n"  , count_cycle); 
mem_instr <= mem_do_prefetch || mem_do_rinst; 
$fwrite(f,"%0d cycle :picorv32.v:894\n"  , count_cycle); 
mem_wstrb <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:896\n"  , count_cycle); 
mem_state <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:898\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:902\n"  , count_cycle); 
if (mem_do_wdata) begin 
mem_valid <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:903\n"  , count_cycle); 
mem_instr <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:905\n"  , count_cycle); 
mem_state <= 2; 
$fwrite(f,"%0d cycle :picorv32.v:907\n"  , count_cycle); 
end 
end 
1: begin 
`assert(mem_wstrb == 0); 
$fwrite(f,"%0d cycle :picorv32.v:912\n"  , count_cycle); 
`assert(mem_do_prefetch || mem_do_rinst || mem_do_rdata); 
`assert(mem_valid == !mem_la_use_prefetched_high_word); 
$fwrite(f,"%0d cycle :picorv32.v:915\n"  , count_cycle); 
`assert(mem_instr == (mem_do_prefetch || mem_do_rinst)); 
$fwrite(f,"%0d cycle :picorv32.v:917\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:920\n"  , count_cycle); 
if (mem_xfer) begin 
$fwrite(f,"%0d cycle :picorv32.v:922\n"  , count_cycle); 
if (COMPRESSED_ISA && mem_la_read) begin 
mem_valid <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:923\n"  , count_cycle); 
mem_la_secondword <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:925\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:928\n"  , count_cycle); 
if (!mem_la_use_prefetched_high_word) begin 
mem_16bit_buffer <= mem_rdata[31:16]; 
$fwrite(f,"%0d cycle :picorv32.v:929\n"  , count_cycle); 
end 
end else begin 
mem_valid <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:933\n"  , count_cycle); 
mem_la_secondword <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:935\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:938\n"  , count_cycle); 
if (COMPRESSED_ISA && !mem_do_rdata) begin 
$fwrite(f,"%0d cycle :picorv32.v:940\n"  , count_cycle); 
if (~&mem_rdata[1:0] || mem_la_secondword) begin 
mem_16bit_buffer <= mem_rdata[31:16]; 
$fwrite(f,"%0d cycle :picorv32.v:941\n"  , count_cycle); 
prefetched_high_word <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:943\n"  , count_cycle); 
end else begin 
prefetched_high_word <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:946\n"  , count_cycle); 
end 
end 
mem_state <= mem_do_rinst || mem_do_rdata ? 0 : 3; 
$fwrite(f,"%0d cycle :picorv32.v:950\n"  , count_cycle); 
end 
end 
end 
2: begin 
`assert(mem_wstrb != 0); 
$fwrite(f,"%0d cycle :picorv32.v:956\n"  , count_cycle); 
`assert(mem_do_wdata); 
$fwrite(f,"%0d cycle :picorv32.v:960\n"  , count_cycle); 
if (mem_xfer) begin 
mem_valid <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:961\n"  , count_cycle); 
mem_state <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:963\n"  , count_cycle); 
end 
end 
3: begin 
`assert(mem_wstrb == 0); 
$fwrite(f,"%0d cycle :picorv32.v:968\n"  , count_cycle); 
`assert(mem_do_prefetch); 
$fwrite(f,"%0d cycle :picorv32.v:972\n"  , count_cycle); 
if (mem_do_rinst) begin 
mem_state <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:973\n"  , count_cycle); 
end 
end 
endcase 
end 
 
$fwrite(f,"%0d cycle :picorv32.v:981\n"  , count_cycle); 
if (clear_prefetched_high_word) begin 
prefetched_high_word <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:982\n"  , count_cycle); 
end 
end 
 
 
// Instruction Decoder 
 
reg instr_lui, instr_auipc, instr_jal, instr_jalr; 
reg instr_beq, instr_bne, instr_blt, instr_bge, instr_bltu, instr_bgeu; 
reg instr_lb, instr_lh, instr_lw, instr_lbu, instr_lhu, instr_sb, instr_sh, instr_sw; 
reg instr_addi, instr_slti, instr_sltiu, instr_xori, instr_ori, instr_andi, instr_slli, instr_srli, instr_srai; 
reg instr_add, instr_sub, instr_sll, instr_slt, instr_sltu, instr_xor, instr_srl, instr_sra, instr_or, instr_and; 
reg instr_rdcycle, instr_rdcycleh, instr_rdinstr, instr_rdinstrh, instr_ecall_ebreak; 
reg instr_getq, instr_setq, instr_retirq, instr_maskirq, instr_waitirq, instr_timer; 
wire instr_trap; 
 
reg [regindex_bits-1:0] decoded_rd, decoded_rs1, decoded_rs2; 
reg [31:0] decoded_imm, decoded_imm_j; 
reg decoder_trigger; 
reg decoder_trigger_q; 
reg decoder_pseudo_trigger; 
reg decoder_pseudo_trigger_q; 
reg compressed_instr; 
 
reg is_lui_auipc_jal; 
reg is_lb_lh_lw_lbu_lhu; 
reg is_slli_srli_srai; 
reg is_jalr_addi_slti_sltiu_xori_ori_andi; 
reg is_sb_sh_sw; 
reg is_sll_srl_sra; 
reg is_lui_auipc_jal_jalr_addi_add_sub; 
reg is_slti_blt_slt; 
reg is_sltiu_bltu_sltu; 
reg is_beq_bne_blt_bge_bltu_bgeu; 
reg is_lbu_lhu_lw; 
reg is_alu_reg_imm; 
reg is_alu_reg_reg; 
reg is_compare; 
 
assign instr_trap = (CATCH_ILLINSN || WITH_PCPI) && !{instr_lui, instr_auipc, instr_jal, instr_jalr,instr_beq, instr_bne, instr_blt, instr_bge, instr_bltu, instr_bgeu,instr_lb, instr_lh, instr_lw, instr_lbu, instr_lhu, instr_sb, instr_sh, instr_sw,instr_addi, instr_slti, instr_sltiu, instr_xori, instr_ori, instr_andi, instr_slli, instr_srli, instr_srai,instr_add, instr_sub, instr_sll, instr_slt, instr_sltu, instr_xor, instr_srl, instr_sra, instr_or, instr_and,instr_rdcycle, instr_rdcycleh, instr_rdinstr, instr_rdinstrh,instr_getq, instr_setq, instr_retirq, instr_maskirq, instr_waitirq, instr_timer}; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:1022\n"  , count_cycle); 
end 
 
wire is_rdcycle_rdcycleh_rdinstr_rdinstrh; 
assign is_rdcycle_rdcycleh_rdinstr_rdinstrh = |{instr_rdcycle, instr_rdcycleh, instr_rdinstr, instr_rdinstrh}; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:1028\n"  , count_cycle); 
end 
 
reg [63:0] new_ascii_instr; 
`FORMAL_KEEP reg [63:0] dbg_ascii_instr; 
`FORMAL_KEEP reg [31:0] dbg_insn_imm; 
`FORMAL_KEEP reg [4:0] dbg_insn_rs1; 
`FORMAL_KEEP reg [4:0] dbg_insn_rs2; 
`FORMAL_KEEP reg [4:0] dbg_insn_rd; 
`FORMAL_KEEP reg [31:0] dbg_rs1val; 
`FORMAL_KEEP reg [31:0] dbg_rs2val; 
`FORMAL_KEEP reg dbg_rs1val_valid; 
`FORMAL_KEEP reg dbg_rs2val_valid; 
 
always @* begin 
new_ascii_instr = ""; 
$fwrite(f,"%0d cycle :picorv32.v:1045\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :picorv32.v:1049\n"  , count_cycle); 
if (instr_lui) begin 
new_ascii_instr = "lui"; 
$fwrite(f,"%0d cycle :picorv32.v:1050\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1054\n"  , count_cycle); 
if (instr_auipc) begin 
new_ascii_instr = "auipc"; 
$fwrite(f,"%0d cycle :picorv32.v:1055\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1059\n"  , count_cycle); 
if (instr_jal) begin 
new_ascii_instr = "jal"; 
$fwrite(f,"%0d cycle :picorv32.v:1060\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1064\n"  , count_cycle); 
if (instr_jalr) begin 
new_ascii_instr = "jalr"; 
$fwrite(f,"%0d cycle :picorv32.v:1065\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :picorv32.v:1070\n"  , count_cycle); 
if (instr_beq) begin 
new_ascii_instr = "beq"; 
$fwrite(f,"%0d cycle :picorv32.v:1071\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1075\n"  , count_cycle); 
if (instr_bne) begin 
new_ascii_instr = "bne"; 
$fwrite(f,"%0d cycle :picorv32.v:1076\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1080\n"  , count_cycle); 
if (instr_blt) begin 
new_ascii_instr = "blt"; 
$fwrite(f,"%0d cycle :picorv32.v:1081\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1085\n"  , count_cycle); 
if (instr_bge) begin 
new_ascii_instr = "bge"; 
$fwrite(f,"%0d cycle :picorv32.v:1086\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1090\n"  , count_cycle); 
if (instr_bltu) begin 
new_ascii_instr = "bltu"; 
$fwrite(f,"%0d cycle :picorv32.v:1091\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1095\n"  , count_cycle); 
if (instr_bgeu) begin 
new_ascii_instr = "bgeu"; 
$fwrite(f,"%0d cycle :picorv32.v:1096\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :picorv32.v:1101\n"  , count_cycle); 
if (instr_lb) begin 
new_ascii_instr = "lb"; 
$fwrite(f,"%0d cycle :picorv32.v:1102\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1106\n"  , count_cycle); 
if (instr_lh) begin 
new_ascii_instr = "lh"; 
$fwrite(f,"%0d cycle :picorv32.v:1107\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1111\n"  , count_cycle); 
if (instr_lw) begin 
new_ascii_instr = "lw"; 
$fwrite(f,"%0d cycle :picorv32.v:1112\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1116\n"  , count_cycle); 
if (instr_lbu) begin 
new_ascii_instr = "lbu"; 
$fwrite(f,"%0d cycle :picorv32.v:1117\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1121\n"  , count_cycle); 
if (instr_lhu) begin 
new_ascii_instr = "lhu"; 
$fwrite(f,"%0d cycle :picorv32.v:1122\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1126\n"  , count_cycle); 
if (instr_sb) begin 
new_ascii_instr = "sb"; 
$fwrite(f,"%0d cycle :picorv32.v:1127\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1131\n"  , count_cycle); 
if (instr_sh) begin 
new_ascii_instr = "sh"; 
$fwrite(f,"%0d cycle :picorv32.v:1132\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1136\n"  , count_cycle); 
if (instr_sw) begin 
new_ascii_instr = "sw"; 
$fwrite(f,"%0d cycle :picorv32.v:1137\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :picorv32.v:1142\n"  , count_cycle); 
if (instr_addi) begin 
new_ascii_instr = "addi"; 
$fwrite(f,"%0d cycle :picorv32.v:1143\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1147\n"  , count_cycle); 
if (instr_slti) begin 
new_ascii_instr = "slti"; 
$fwrite(f,"%0d cycle :picorv32.v:1148\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1152\n"  , count_cycle); 
if (instr_sltiu) begin 
new_ascii_instr = "sltiu"; 
$fwrite(f,"%0d cycle :picorv32.v:1153\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1157\n"  , count_cycle); 
if (instr_xori) begin 
new_ascii_instr = "xori"; 
$fwrite(f,"%0d cycle :picorv32.v:1158\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1162\n"  , count_cycle); 
if (instr_ori) begin 
new_ascii_instr = "ori"; 
$fwrite(f,"%0d cycle :picorv32.v:1163\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1167\n"  , count_cycle); 
if (instr_andi) begin 
new_ascii_instr = "andi"; 
$fwrite(f,"%0d cycle :picorv32.v:1168\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1172\n"  , count_cycle); 
if (instr_slli) begin 
new_ascii_instr = "slli"; 
$fwrite(f,"%0d cycle :picorv32.v:1173\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1177\n"  , count_cycle); 
if (instr_srli) begin 
new_ascii_instr = "srli"; 
$fwrite(f,"%0d cycle :picorv32.v:1178\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1182\n"  , count_cycle); 
if (instr_srai) begin 
new_ascii_instr = "srai"; 
$fwrite(f,"%0d cycle :picorv32.v:1183\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :picorv32.v:1188\n"  , count_cycle); 
if (instr_add) begin 
new_ascii_instr = "add"; 
$fwrite(f,"%0d cycle :picorv32.v:1189\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1193\n"  , count_cycle); 
if (instr_sub) begin 
new_ascii_instr = "sub"; 
$fwrite(f,"%0d cycle :picorv32.v:1194\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1198\n"  , count_cycle); 
if (instr_sll) begin 
new_ascii_instr = "sll"; 
$fwrite(f,"%0d cycle :picorv32.v:1199\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1203\n"  , count_cycle); 
if (instr_slt) begin 
new_ascii_instr = "slt"; 
$fwrite(f,"%0d cycle :picorv32.v:1204\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1208\n"  , count_cycle); 
if (instr_sltu) begin 
new_ascii_instr = "sltu"; 
$fwrite(f,"%0d cycle :picorv32.v:1209\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1213\n"  , count_cycle); 
if (instr_xor) begin 
new_ascii_instr = "xor"; 
$fwrite(f,"%0d cycle :picorv32.v:1214\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1218\n"  , count_cycle); 
if (instr_srl) begin 
new_ascii_instr = "srl"; 
$fwrite(f,"%0d cycle :picorv32.v:1219\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1223\n"  , count_cycle); 
if (instr_sra) begin 
new_ascii_instr = "sra"; 
$fwrite(f,"%0d cycle :picorv32.v:1224\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1228\n"  , count_cycle); 
if (instr_or) begin 
new_ascii_instr = "or"; 
$fwrite(f,"%0d cycle :picorv32.v:1229\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1233\n"  , count_cycle); 
if (instr_and) begin 
new_ascii_instr = "and"; 
$fwrite(f,"%0d cycle :picorv32.v:1234\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :picorv32.v:1239\n"  , count_cycle); 
if (instr_rdcycle) begin 
new_ascii_instr = "rdcycle"; 
$fwrite(f,"%0d cycle :picorv32.v:1240\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1244\n"  , count_cycle); 
if (instr_rdcycleh) begin 
new_ascii_instr = "rdcycleh"; 
$fwrite(f,"%0d cycle :picorv32.v:1245\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1249\n"  , count_cycle); 
if (instr_rdinstr) begin 
new_ascii_instr = "rdinstr"; 
$fwrite(f,"%0d cycle :picorv32.v:1250\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1254\n"  , count_cycle); 
if (instr_rdinstrh) begin 
new_ascii_instr = "rdinstrh"; 
$fwrite(f,"%0d cycle :picorv32.v:1255\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :picorv32.v:1260\n"  , count_cycle); 
if (instr_getq) begin 
new_ascii_instr = "getq"; 
$fwrite(f,"%0d cycle :picorv32.v:1261\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1265\n"  , count_cycle); 
if (instr_setq) begin 
new_ascii_instr = "setq"; 
$fwrite(f,"%0d cycle :picorv32.v:1266\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1270\n"  , count_cycle); 
if (instr_retirq) begin 
new_ascii_instr = "retirq"; 
$fwrite(f,"%0d cycle :picorv32.v:1271\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1275\n"  , count_cycle); 
if (instr_maskirq) begin 
new_ascii_instr = "maskirq"; 
$fwrite(f,"%0d cycle :picorv32.v:1276\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1280\n"  , count_cycle); 
if (instr_waitirq) begin 
new_ascii_instr = "waitirq"; 
$fwrite(f,"%0d cycle :picorv32.v:1281\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1285\n"  , count_cycle); 
if (instr_timer) begin 
new_ascii_instr = "timer"; 
$fwrite(f,"%0d cycle :picorv32.v:1286\n"  , count_cycle); 
end 
end 
 
reg [63:0] q_ascii_instr; 
reg [31:0] q_insn_imm; 
reg [31:0] q_insn_opcode; 
reg [4:0] q_insn_rs1; 
reg [4:0] q_insn_rs2; 
reg [4:0] q_insn_rd; 
reg dbg_next; 
 
wire launch_next_insn; 
reg dbg_valid_insn; 
 
reg [63:0] cached_ascii_instr; 
reg [31:0] cached_insn_imm; 
reg [31:0] cached_insn_opcode; 
reg [4:0] cached_insn_rs1; 
reg [4:0] cached_insn_rs2; 
reg [4:0] cached_insn_rd; 
 
always @(posedge clk) begin 
q_ascii_instr <= dbg_ascii_instr; 
$fwrite(f,"%0d cycle :picorv32.v:1310\n"  , count_cycle); 
q_insn_imm <= dbg_insn_imm; 
$fwrite(f,"%0d cycle :picorv32.v:1312\n"  , count_cycle); 
q_insn_opcode <= dbg_insn_opcode; 
$fwrite(f,"%0d cycle :picorv32.v:1314\n"  , count_cycle); 
q_insn_rs1 <= dbg_insn_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:1316\n"  , count_cycle); 
q_insn_rs2 <= dbg_insn_rs2; 
$fwrite(f,"%0d cycle :picorv32.v:1318\n"  , count_cycle); 
q_insn_rd <= dbg_insn_rd; 
$fwrite(f,"%0d cycle :picorv32.v:1320\n"  , count_cycle); 
dbg_next <= launch_next_insn; 
$fwrite(f,"%0d cycle :picorv32.v:1322\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :picorv32.v:1326\n"  , count_cycle); 
if (!resetn || trap) begin 
dbg_valid_insn <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1327\n"  , count_cycle); 
end 

else if (launch_next_insn) 
dbg_valid_insn <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:1332\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :picorv32.v:1336\n"  , count_cycle); 
if (decoder_trigger_q) begin 
cached_ascii_instr <= new_ascii_instr; 
$fwrite(f,"%0d cycle :picorv32.v:1337\n"  , count_cycle); 
cached_insn_imm <= decoded_imm; 
$fwrite(f,"%0d cycle :picorv32.v:1339\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:1342\n"  , count_cycle); 
if (&next_insn_opcode[1:0]) begin 
cached_insn_opcode <= next_insn_opcode; 
$fwrite(f,"%0d cycle :picorv32.v:1343\n"  , count_cycle); 
end 
else 
cached_insn_opcode <= {16'b0, next_insn_opcode[15:0]}; 
$fwrite(f,"%0d cycle :picorv32.v:1347\n"  , count_cycle); 
cached_insn_rs1 <= decoded_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:1349\n"  , count_cycle); 
cached_insn_rs2 <= decoded_rs2; 
$fwrite(f,"%0d cycle :picorv32.v:1351\n"  , count_cycle); 
cached_insn_rd <= decoded_rd; 
$fwrite(f,"%0d cycle :picorv32.v:1353\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :picorv32.v:1358\n"  , count_cycle); 
if (launch_next_insn) begin 
dbg_insn_addr <= next_pc; 
$fwrite(f,"%0d cycle :picorv32.v:1359\n"  , count_cycle); 
end 
end 
 
always @* begin 
dbg_ascii_instr = q_ascii_instr; 
$fwrite(f,"%0d cycle :picorv32.v:1365\n"  , count_cycle); 
dbg_insn_imm = q_insn_imm; 
$fwrite(f,"%0d cycle :picorv32.v:1367\n"  , count_cycle); 
dbg_insn_opcode = q_insn_opcode; 
$fwrite(f,"%0d cycle :picorv32.v:1369\n"  , count_cycle); 
dbg_insn_rs1 = q_insn_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:1371\n"  , count_cycle); 
dbg_insn_rs2 = q_insn_rs2; 
$fwrite(f,"%0d cycle :picorv32.v:1373\n"  , count_cycle); 
dbg_insn_rd = q_insn_rd; 
$fwrite(f,"%0d cycle :picorv32.v:1375\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :picorv32.v:1379\n"  , count_cycle); 
if (dbg_next) begin 
$fwrite(f,"%0d cycle :picorv32.v:1381\n"  , count_cycle); 
if (decoder_pseudo_trigger_q) begin 
dbg_ascii_instr = cached_ascii_instr; 
$fwrite(f,"%0d cycle :picorv32.v:1382\n"  , count_cycle); 
dbg_insn_imm = cached_insn_imm; 
$fwrite(f,"%0d cycle :picorv32.v:1384\n"  , count_cycle); 
dbg_insn_opcode = cached_insn_opcode; 
$fwrite(f,"%0d cycle :picorv32.v:1386\n"  , count_cycle); 
dbg_insn_rs1 = cached_insn_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:1388\n"  , count_cycle); 
dbg_insn_rs2 = cached_insn_rs2; 
$fwrite(f,"%0d cycle :picorv32.v:1390\n"  , count_cycle); 
dbg_insn_rd = cached_insn_rd; 
$fwrite(f,"%0d cycle :picorv32.v:1392\n"  , count_cycle); 
end else begin 
dbg_ascii_instr = new_ascii_instr; 
$fwrite(f,"%0d cycle :picorv32.v:1395\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:1398\n"  , count_cycle); 
if (&next_insn_opcode[1:0]) begin 
dbg_insn_opcode = next_insn_opcode; 
$fwrite(f,"%0d cycle :picorv32.v:1399\n"  , count_cycle); 
end 
else 
dbg_insn_opcode = {16'b0, next_insn_opcode[15:0]}; 
$fwrite(f,"%0d cycle :picorv32.v:1403\n"  , count_cycle); 
dbg_insn_imm = decoded_imm; 
$fwrite(f,"%0d cycle :picorv32.v:1405\n"  , count_cycle); 
dbg_insn_rs1 = decoded_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:1407\n"  , count_cycle); 
dbg_insn_rs2 = decoded_rs2; 
$fwrite(f,"%0d cycle :picorv32.v:1409\n"  , count_cycle); 
dbg_insn_rd = decoded_rd; 
$fwrite(f,"%0d cycle :picorv32.v:1411\n"  , count_cycle); 
end 
end 
end 
 
`ifdef DEBUGASM 
always @(posedge clk) begin 
$fwrite(f,"%0d cycle :picorv32.v:1420\n"  , count_cycle); 
if (dbg_next) begin 
$display("debugasm %x %x %s", dbg_insn_addr, dbg_insn_opcode, dbg_ascii_instr ? dbg_ascii_instr : "*"); 
end 
end 
`endif 
 
`ifdef DEBUG 
always @(posedge clk) begin 
$fwrite(f,"%0d cycle :picorv32.v:1429\n"  , count_cycle); 
if (dbg_next) begin 
$fwrite(f,"%0d cycle :picorv32.v:1431\n"  , count_cycle); 
if (&dbg_insn_opcode[1:0]) begin 
$display("DECODE: 0x%08x 0x%08x %-0s", dbg_insn_addr, dbg_insn_opcode, dbg_ascii_instr ? dbg_ascii_instr : "UNKNOWN"); 
end 
else 
$display("DECODE: 0x%08x     0x%04x %-0s", dbg_insn_addr, dbg_insn_opcode[15:0], dbg_ascii_instr ? dbg_ascii_instr : "UNKNOWN"); 
end 
end 
`endif 
 
always @(posedge clk) begin 
is_lui_auipc_jal <= |{instr_lui, instr_auipc, instr_jal}; 
$fwrite(f,"%0d cycle :picorv32.v:1441\n"  , count_cycle); 
is_lui_auipc_jal_jalr_addi_add_sub <= |{instr_lui, instr_auipc, instr_jal, instr_jalr, instr_addi, instr_add, instr_sub}; 
$fwrite(f,"%0d cycle :picorv32.v:1443\n"  , count_cycle); 
is_slti_blt_slt <= |{instr_slti, instr_blt, instr_slt}; 
$fwrite(f,"%0d cycle :picorv32.v:1445\n"  , count_cycle); 
is_sltiu_bltu_sltu <= |{instr_sltiu, instr_bltu, instr_sltu}; 
$fwrite(f,"%0d cycle :picorv32.v:1447\n"  , count_cycle); 
is_lbu_lhu_lw <= |{instr_lbu, instr_lhu, instr_lw}; 
$fwrite(f,"%0d cycle :picorv32.v:1449\n"  , count_cycle); 
is_compare <= |{is_beq_bne_blt_bge_bltu_bgeu, instr_slti, instr_slt, instr_sltiu, instr_sltu}; 
$fwrite(f,"%0d cycle :picorv32.v:1451\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :picorv32.v:1455\n"  , count_cycle); 
if (mem_do_rinst && mem_done) begin 
instr_lui     <= mem_rdata_latched[6:0] == 7'b0110111; 
$fwrite(f,"%0d cycle :picorv32.v:1456\n"  , count_cycle); 
instr_auipc   <= mem_rdata_latched[6:0] == 7'b0010111; 
$fwrite(f,"%0d cycle :picorv32.v:1458\n"  , count_cycle); 
instr_jal     <= mem_rdata_latched[6:0] == 7'b1101111; 
$fwrite(f,"%0d cycle :picorv32.v:1460\n"  , count_cycle); 
instr_jalr    <= mem_rdata_latched[6:0] == 7'b1100111 && mem_rdata_latched[14:12] == 3'b000; 
$fwrite(f,"%0d cycle :picorv32.v:1462\n"  , count_cycle); 
instr_retirq  <= mem_rdata_latched[6:0] == 7'b0001011 && mem_rdata_latched[31:25] == 7'b0000010 && ENABLE_IRQ; 
$fwrite(f,"%0d cycle :picorv32.v:1464\n"  , count_cycle); 
instr_waitirq <= mem_rdata_latched[6:0] == 7'b0001011 && mem_rdata_latched[31:25] == 7'b0000100 && ENABLE_IRQ; 
$fwrite(f,"%0d cycle :picorv32.v:1466\n"  , count_cycle); 
 
is_beq_bne_blt_bge_bltu_bgeu <= mem_rdata_latched[6:0] == 7'b1100011; 
$fwrite(f,"%0d cycle :picorv32.v:1469\n"  , count_cycle); 
is_lb_lh_lw_lbu_lhu          <= mem_rdata_latched[6:0] == 7'b0000011; 
$fwrite(f,"%0d cycle :picorv32.v:1471\n"  , count_cycle); 
is_sb_sh_sw                  <= mem_rdata_latched[6:0] == 7'b0100011; 
$fwrite(f,"%0d cycle :picorv32.v:1473\n"  , count_cycle); 
is_alu_reg_imm               <= mem_rdata_latched[6:0] == 7'b0010011; 
$fwrite(f,"%0d cycle :picorv32.v:1475\n"  , count_cycle); 
is_alu_reg_reg               <= mem_rdata_latched[6:0] == 7'b0110011; 
$fwrite(f,"%0d cycle :picorv32.v:1477\n"  , count_cycle); 
 
{ decoded_imm_j[31:20], decoded_imm_j[10:1], decoded_imm_j[11], decoded_imm_j[19:12], decoded_imm_j[0] } <= $signed({mem_rdata_latched[31:12], 1'b0}); 
$fwrite(f,"%0d cycle :picorv32.v:1480\n"  , count_cycle); 
 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1483\n"  , count_cycle); 
decoded_rs1 <= mem_rdata_latched[19:15]; 
$fwrite(f,"%0d cycle :picorv32.v:1485\n"  , count_cycle); 
decoded_rs2 <= mem_rdata_latched[24:20]; 
$fwrite(f,"%0d cycle :picorv32.v:1487\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :picorv32.v:1490\n"  , count_cycle); 
if (mem_rdata_latched[6:0] == 7'b0001011 && mem_rdata_latched[31:25] == 7'b0000000 && ENABLE_IRQ && ENABLE_IRQ_QREGS) begin 
decoded_rs1[regindex_bits-1] <= 1; // instr_getq 
$fwrite(f,"%0d cycle :picorv32.v:1492\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :picorv32.v:1496\n"  , count_cycle); 
if (mem_rdata_latched[6:0] == 7'b0001011 && mem_rdata_latched[31:25] == 7'b0000010 && ENABLE_IRQ) begin 
decoded_rs1 <= ENABLE_IRQ_QREGS ? irqregs_offset : 3; // instr_retirq 
$fwrite(f,"%0d cycle :picorv32.v:1498\n"  , count_cycle); 
end 
 
compressed_instr <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1502\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:1504\n"  , count_cycle); 
if (COMPRESSED_ISA && mem_rdata_latched[1:0] != 2'b11) begin 
compressed_instr <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:1506\n"  , count_cycle); 
decoded_rd <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1508\n"  , count_cycle); 
decoded_rs1 <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1510\n"  , count_cycle); 
decoded_rs2 <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1512\n"  , count_cycle); 
 
{ decoded_imm_j[31:11], decoded_imm_j[4], decoded_imm_j[9:8], decoded_imm_j[10], decoded_imm_j[6], 
decoded_imm_j[7], decoded_imm_j[3:1], decoded_imm_j[5], decoded_imm_j[0] } <= $signed({mem_rdata_latched[12:2], 1'b0}); 
$fwrite(f,"%0d cycle :picorv32.v:1516\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :picorv32.v:1520\n"  , count_cycle); 
case (mem_rdata_latched[1:0]) 
2'b00: begin // Quadrant 0 
$fwrite(f,"%0d cycle :picorv32.v:1523\n"  , count_cycle); 
case (mem_rdata_latched[15:13]) 
3'b000: begin // C.ADDI4SPN 
is_alu_reg_imm <= |mem_rdata_latched[12:5]; 
$fwrite(f,"%0d cycle :picorv32.v:1525\n"  , count_cycle); 
decoded_rs1 <= 2; 
$fwrite(f,"%0d cycle :picorv32.v:1527\n"  , count_cycle); 
decoded_rd <= 8 + mem_rdata_latched[4:2]; 
$fwrite(f,"%0d cycle :picorv32.v:1529\n"  , count_cycle); 
end 
3'b010: begin // C.LW 
is_lb_lh_lw_lbu_lhu <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:1533\n"  , count_cycle); 
decoded_rs1 <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1535\n"  , count_cycle); 
decoded_rd <= 8 + mem_rdata_latched[4:2]; 
$fwrite(f,"%0d cycle :picorv32.v:1537\n"  , count_cycle); 
end 
3'b110: begin // C.SW 
is_sb_sh_sw <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:1541\n"  , count_cycle); 
decoded_rs1 <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1543\n"  , count_cycle); 
decoded_rs2 <= 8 + mem_rdata_latched[4:2]; 
$fwrite(f,"%0d cycle :picorv32.v:1545\n"  , count_cycle); 
end 
endcase 
end 
2'b01: begin // Quadrant 1 
$fwrite(f,"%0d cycle :picorv32.v:1552\n"  , count_cycle); 
case (mem_rdata_latched[15:13]) 
3'b000: begin // C.NOP / C.ADDI 
is_alu_reg_imm <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:1554\n"  , count_cycle); 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1556\n"  , count_cycle); 
decoded_rs1 <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1558\n"  , count_cycle); 
end 
3'b001: begin // C.JAL 
instr_jal <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:1562\n"  , count_cycle); 
decoded_rd <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:1564\n"  , count_cycle); 
end 
3'b 010: begin // C.LI 
is_alu_reg_imm <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:1568\n"  , count_cycle); 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1570\n"  , count_cycle); 
decoded_rs1 <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1572\n"  , count_cycle); 
end 
3'b 011: begin 
$fwrite(f,"%0d cycle :picorv32.v:1577\n"  , count_cycle); 
if (mem_rdata_latched[12] || mem_rdata_latched[6:2]) begin 
$fwrite(f,"%0d cycle :picorv32.v:1578\n"  , count_cycle); 
if (mem_rdata_latched[11:7] == 2) begin // C.ADDI16SP 
is_alu_reg_imm <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:1580\n"  , count_cycle); 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1582\n"  , count_cycle); 
decoded_rs1 <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1584\n"  , count_cycle); 
end else begin // C.LUI 
instr_lui <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:1587\n"  , count_cycle); 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1589\n"  , count_cycle); 
decoded_rs1 <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1591\n"  , count_cycle); 
end 
end 
end 
3'b100: begin 
$fwrite(f,"%0d cycle :picorv32.v:1598\n"  , count_cycle); 
if (!mem_rdata_latched[11] && !mem_rdata_latched[12]) begin // C.SRLI, C.SRAI 
is_alu_reg_imm <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:1599\n"  , count_cycle); 
decoded_rd <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1601\n"  , count_cycle); 
decoded_rs1 <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1603\n"  , count_cycle); 
decoded_rs2 <= {mem_rdata_latched[12], mem_rdata_latched[6:2]}; 
$fwrite(f,"%0d cycle :picorv32.v:1605\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1608\n"  , count_cycle); 
if (mem_rdata_latched[11:10] == 2'b10) begin // C.ANDI 
is_alu_reg_imm <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:1610\n"  , count_cycle); 
decoded_rd <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1612\n"  , count_cycle); 
decoded_rs1 <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1614\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1617\n"  , count_cycle); 
if (mem_rdata_latched[12:10] == 3'b011) begin // C.SUB, C.XOR, C.OR, C.AND 
is_alu_reg_reg <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:1619\n"  , count_cycle); 
decoded_rd <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1621\n"  , count_cycle); 
decoded_rs1 <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1623\n"  , count_cycle); 
decoded_rs2 <= 8 + mem_rdata_latched[4:2]; 
$fwrite(f,"%0d cycle :picorv32.v:1625\n"  , count_cycle); 
end 
end 
3'b101: begin // C.J 
instr_jal <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:1630\n"  , count_cycle); 
end 
3'b110: begin // C.BEQZ 
is_beq_bne_blt_bge_bltu_bgeu <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:1634\n"  , count_cycle); 
decoded_rs1 <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1636\n"  , count_cycle); 
decoded_rs2 <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1638\n"  , count_cycle); 
end 
3'b111: begin // C.BNEZ 
is_beq_bne_blt_bge_bltu_bgeu <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:1642\n"  , count_cycle); 
decoded_rs1 <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1644\n"  , count_cycle); 
decoded_rs2 <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1646\n"  , count_cycle); 
end 
endcase 
end 
2'b10: begin // Quadrant 2 
$fwrite(f,"%0d cycle :picorv32.v:1653\n"  , count_cycle); 
case (mem_rdata_latched[15:13]) 
3'b000: begin // C.SLLI 
$fwrite(f,"%0d cycle :picorv32.v:1656\n"  , count_cycle); 
if (!mem_rdata_latched[12]) begin 
is_alu_reg_imm <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:1657\n"  , count_cycle); 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1659\n"  , count_cycle); 
decoded_rs1 <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1661\n"  , count_cycle); 
decoded_rs2 <= {mem_rdata_latched[12], mem_rdata_latched[6:2]}; 
$fwrite(f,"%0d cycle :picorv32.v:1663\n"  , count_cycle); 
end 
end 
3'b010: begin // C.LWSP 
$fwrite(f,"%0d cycle :picorv32.v:1669\n"  , count_cycle); 
if (mem_rdata_latched[11:7]) begin 
is_lb_lh_lw_lbu_lhu <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:1670\n"  , count_cycle); 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1672\n"  , count_cycle); 
decoded_rs1 <= 2; 
$fwrite(f,"%0d cycle :picorv32.v:1674\n"  , count_cycle); 
end 
end 
3'b100: begin 
$fwrite(f,"%0d cycle :picorv32.v:1679\n"  , count_cycle); 
if (mem_rdata_latched[12] == 0 && mem_rdata_latched[11:7] != 0 && mem_rdata_latched[6:2] == 0) begin // C.JR 
instr_jalr <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:1681\n"  , count_cycle); 
decoded_rd <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1683\n"  , count_cycle); 
decoded_rs1 <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1685\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1688\n"  , count_cycle); 
if (mem_rdata_latched[12] == 0 && mem_rdata_latched[6:2] != 0) begin // C.MV 
is_alu_reg_reg <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:1690\n"  , count_cycle); 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1692\n"  , count_cycle); 
decoded_rs1 <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1694\n"  , count_cycle); 
decoded_rs2 <= mem_rdata_latched[6:2]; 
$fwrite(f,"%0d cycle :picorv32.v:1696\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1699\n"  , count_cycle); 
if (mem_rdata_latched[12] != 0 && mem_rdata_latched[11:7] != 0 && mem_rdata_latched[6:2] == 0) begin // C.JALR 
instr_jalr <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:1701\n"  , count_cycle); 
decoded_rd <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:1703\n"  , count_cycle); 
decoded_rs1 <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1705\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1708\n"  , count_cycle); 
if (mem_rdata_latched[12] != 0 && mem_rdata_latched[6:2] != 0) begin // C.ADD 
is_alu_reg_reg <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:1710\n"  , count_cycle); 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1712\n"  , count_cycle); 
decoded_rs1 <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :picorv32.v:1714\n"  , count_cycle); 
decoded_rs2 <= mem_rdata_latched[6:2]; 
$fwrite(f,"%0d cycle :picorv32.v:1716\n"  , count_cycle); 
end 
end 
3'b110: begin // C.SWSP 
is_sb_sh_sw <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:1721\n"  , count_cycle); 
decoded_rs1 <= 2; 
$fwrite(f,"%0d cycle :picorv32.v:1723\n"  , count_cycle); 
decoded_rs2 <= mem_rdata_latched[6:2]; 
$fwrite(f,"%0d cycle :picorv32.v:1725\n"  , count_cycle); 
end 
endcase 
end 
endcase 
end 
end 
 
$fwrite(f,"%0d cycle :picorv32.v:1735\n"  , count_cycle); 
if (decoder_trigger && !decoder_pseudo_trigger) begin 
pcpi_insn <= WITH_PCPI ? mem_rdata_q : 'bx; 
$fwrite(f,"%0d cycle :picorv32.v:1736\n"  , count_cycle); 
 
instr_beq   <= is_beq_bne_blt_bge_bltu_bgeu && mem_rdata_q[14:12] == 3'b000; 
$fwrite(f,"%0d cycle :picorv32.v:1739\n"  , count_cycle); 
instr_bne   <= is_beq_bne_blt_bge_bltu_bgeu && mem_rdata_q[14:12] == 3'b001; 
$fwrite(f,"%0d cycle :picorv32.v:1741\n"  , count_cycle); 
instr_blt   <= is_beq_bne_blt_bge_bltu_bgeu && mem_rdata_q[14:12] == 3'b100; 
$fwrite(f,"%0d cycle :picorv32.v:1743\n"  , count_cycle); 
instr_bge   <= is_beq_bne_blt_bge_bltu_bgeu && mem_rdata_q[14:12] == 3'b101; 
$fwrite(f,"%0d cycle :picorv32.v:1745\n"  , count_cycle); 
instr_bltu  <= is_beq_bne_blt_bge_bltu_bgeu && mem_rdata_q[14:12] == 3'b110; 
$fwrite(f,"%0d cycle :picorv32.v:1747\n"  , count_cycle); 
instr_bgeu  <= is_beq_bne_blt_bge_bltu_bgeu && mem_rdata_q[14:12] == 3'b111; 
$fwrite(f,"%0d cycle :picorv32.v:1749\n"  , count_cycle); 
 
instr_lb    <= is_lb_lh_lw_lbu_lhu && mem_rdata_q[14:12] == 3'b000; 
$fwrite(f,"%0d cycle :picorv32.v:1752\n"  , count_cycle); 
instr_lh    <= is_lb_lh_lw_lbu_lhu && mem_rdata_q[14:12] == 3'b001; 
$fwrite(f,"%0d cycle :picorv32.v:1754\n"  , count_cycle); 
instr_lw    <= is_lb_lh_lw_lbu_lhu && mem_rdata_q[14:12] == 3'b010; 
$fwrite(f,"%0d cycle :picorv32.v:1756\n"  , count_cycle); 
instr_lbu   <= is_lb_lh_lw_lbu_lhu && mem_rdata_q[14:12] == 3'b100; 
$fwrite(f,"%0d cycle :picorv32.v:1758\n"  , count_cycle); 
instr_lhu   <= is_lb_lh_lw_lbu_lhu && mem_rdata_q[14:12] == 3'b101; 
$fwrite(f,"%0d cycle :picorv32.v:1760\n"  , count_cycle); 
 
instr_sb    <= is_sb_sh_sw && mem_rdata_q[14:12] == 3'b000; 
$fwrite(f,"%0d cycle :picorv32.v:1763\n"  , count_cycle); 
instr_sh    <= is_sb_sh_sw && mem_rdata_q[14:12] == 3'b001; 
$fwrite(f,"%0d cycle :picorv32.v:1765\n"  , count_cycle); 
instr_sw    <= is_sb_sh_sw && mem_rdata_q[14:12] == 3'b010; 
$fwrite(f,"%0d cycle :picorv32.v:1767\n"  , count_cycle); 
 
instr_addi  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b000; 
$fwrite(f,"%0d cycle :picorv32.v:1770\n"  , count_cycle); 
instr_slti  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b010; 
$fwrite(f,"%0d cycle :picorv32.v:1772\n"  , count_cycle); 
instr_sltiu <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b011; 
$fwrite(f,"%0d cycle :picorv32.v:1774\n"  , count_cycle); 
instr_xori  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b100; 
$fwrite(f,"%0d cycle :picorv32.v:1776\n"  , count_cycle); 
instr_ori   <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b110; 
$fwrite(f,"%0d cycle :picorv32.v:1778\n"  , count_cycle); 
instr_andi  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b111; 
$fwrite(f,"%0d cycle :picorv32.v:1780\n"  , count_cycle); 
 
instr_slli  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b001 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0d cycle :picorv32.v:1783\n"  , count_cycle); 
instr_srli  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b101 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0d cycle :picorv32.v:1785\n"  , count_cycle); 
instr_srai  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b101 && mem_rdata_q[31:25] == 7'b0100000; 
$fwrite(f,"%0d cycle :picorv32.v:1787\n"  , count_cycle); 
 
instr_add   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b000 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0d cycle :picorv32.v:1790\n"  , count_cycle); 
instr_sub   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b000 && mem_rdata_q[31:25] == 7'b0100000; 
$fwrite(f,"%0d cycle :picorv32.v:1792\n"  , count_cycle); 
instr_sll   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b001 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0d cycle :picorv32.v:1794\n"  , count_cycle); 
instr_slt   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b010 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0d cycle :picorv32.v:1796\n"  , count_cycle); 
instr_sltu  <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b011 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0d cycle :picorv32.v:1798\n"  , count_cycle); 
instr_xor   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b100 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0d cycle :picorv32.v:1800\n"  , count_cycle); 
instr_srl   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b101 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0d cycle :picorv32.v:1802\n"  , count_cycle); 
instr_sra   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b101 && mem_rdata_q[31:25] == 7'b0100000; 
$fwrite(f,"%0d cycle :picorv32.v:1804\n"  , count_cycle); 
instr_or    <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b110 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0d cycle :picorv32.v:1806\n"  , count_cycle); 
instr_and   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b111 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0d cycle :picorv32.v:1808\n"  , count_cycle); 
 
instr_rdcycle  <= ((mem_rdata_q[6:0] == 7'b1110011 && mem_rdata_q[31:12] == 'b11000000000000000010) ||(mem_rdata_q[6:0] == 7'b1110011 && mem_rdata_q[31:12] == 'b11000000000100000010)) && ENABLE_COUNTERS; 
$fwrite(f,"%0d cycle :picorv32.v:1811\n"  , count_cycle); 
instr_rdcycleh <= ((mem_rdata_q[6:0] == 7'b1110011 && mem_rdata_q[31:12] == 'b11001000000000000010) ||(mem_rdata_q[6:0] == 7'b1110011 && mem_rdata_q[31:12] == 'b11001000000100000010)) && ENABLE_COUNTERS && ENABLE_COUNTERS64; 
$fwrite(f,"%0d cycle :picorv32.v:1813\n"  , count_cycle); 
instr_rdinstr  <=  (mem_rdata_q[6:0] == 7'b1110011 && mem_rdata_q[31:12] == 'b11000000001000000010) && ENABLE_COUNTERS; 
$fwrite(f,"%0d cycle :picorv32.v:1815\n"  , count_cycle); 
instr_rdinstrh <=  (mem_rdata_q[6:0] == 7'b1110011 && mem_rdata_q[31:12] == 'b11001000001000000010) && ENABLE_COUNTERS && ENABLE_COUNTERS64; 
$fwrite(f,"%0d cycle :picorv32.v:1817\n"  , count_cycle); 
 
instr_ecall_ebreak <= ((mem_rdata_q[6:0] == 7'b1110011 && !mem_rdata_q[31:21] && !mem_rdata_q[19:7]) ||(COMPRESSED_ISA && mem_rdata_q[15:0] == 16'h9002)); 
$fwrite(f,"%0d cycle :picorv32.v:1820\n"  , count_cycle); 
 
instr_getq    <= mem_rdata_q[6:0] == 7'b0001011 && mem_rdata_q[31:25] == 7'b0000000 && ENABLE_IRQ && ENABLE_IRQ_QREGS; 
$fwrite(f,"%0d cycle :picorv32.v:1823\n"  , count_cycle); 
instr_setq    <= mem_rdata_q[6:0] == 7'b0001011 && mem_rdata_q[31:25] == 7'b0000001 && ENABLE_IRQ && ENABLE_IRQ_QREGS; 
$fwrite(f,"%0d cycle :picorv32.v:1825\n"  , count_cycle); 
instr_maskirq <= mem_rdata_q[6:0] == 7'b0001011 && mem_rdata_q[31:25] == 7'b0000011 && ENABLE_IRQ; 
$fwrite(f,"%0d cycle :picorv32.v:1827\n"  , count_cycle); 
instr_timer   <= mem_rdata_q[6:0] == 7'b0001011 && mem_rdata_q[31:25] == 7'b0000101 && ENABLE_IRQ && ENABLE_IRQ_TIMER; 
$fwrite(f,"%0d cycle :picorv32.v:1829\n"  , count_cycle); 
 
is_slli_srli_srai <= is_alu_reg_imm && |{mem_rdata_q[14:12] == 3'b001 && mem_rdata_q[31:25] == 7'b0000000,mem_rdata_q[14:12] == 3'b101 && mem_rdata_q[31:25] == 7'b0000000,mem_rdata_q[14:12] == 3'b101 && mem_rdata_q[31:25] == 7'b0100000}; 
$fwrite(f,"%0d cycle :picorv32.v:1832\n"  , count_cycle); 
 
is_jalr_addi_slti_sltiu_xori_ori_andi <= instr_jalr || is_alu_reg_imm && |{mem_rdata_q[14:12] == 3'b000,mem_rdata_q[14:12] == 3'b010,mem_rdata_q[14:12] == 3'b011,mem_rdata_q[14:12] == 3'b100,mem_rdata_q[14:12] == 3'b110,mem_rdata_q[14:12] == 3'b111}; 
$fwrite(f,"%0d cycle :picorv32.v:1835\n"  , count_cycle); 
 
is_sll_srl_sra <= is_alu_reg_reg && |{mem_rdata_q[14:12] == 3'b001 && mem_rdata_q[31:25] == 7'b0000000,mem_rdata_q[14:12] == 3'b101 && mem_rdata_q[31:25] == 7'b0000000,mem_rdata_q[14:12] == 3'b101 && mem_rdata_q[31:25] == 7'b0100000}; 
$fwrite(f,"%0d cycle :picorv32.v:1838\n"  , count_cycle); 
 
is_lui_auipc_jal_jalr_addi_add_sub <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1841\n"  , count_cycle); 
is_compare <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1843\n"  , count_cycle); 
 

(* parallel_case *) 

case (1'b1) 
instr_jal: begin 
decoded_imm <= decoded_imm_j; 
$fwrite(f,"%0d cycle :picorv32.v:1851\n"  , count_cycle); 
end 
|{instr_lui, instr_auipc}: begin 
decoded_imm <= mem_rdata_q[31:12] << 12; 
$fwrite(f,"%0d cycle :picorv32.v:1855\n"  , count_cycle); 
end 
|{instr_jalr, is_lb_lh_lw_lbu_lhu, is_alu_reg_imm}: begin 
decoded_imm <= $signed(mem_rdata_q[31:20]); 
$fwrite(f,"%0d cycle :picorv32.v:1859\n"  , count_cycle); 
end 
is_beq_bne_blt_bge_bltu_bgeu: begin 
decoded_imm <= $signed({mem_rdata_q[31], mem_rdata_q[7], mem_rdata_q[30:25], mem_rdata_q[11:8], 1'b0}); 
$fwrite(f,"%0d cycle :picorv32.v:1863\n"  , count_cycle); 
end 
is_sb_sh_sw: begin 
decoded_imm <= $signed({mem_rdata_q[31:25], mem_rdata_q[11:7]}); 
$fwrite(f,"%0d cycle :picorv32.v:1867\n"  , count_cycle); 
end 
default: begin 
decoded_imm <= 1'bx; 
$fwrite(f,"%0d cycle :picorv32.v:1871\n"  , count_cycle); 
end 
endcase 
end 
 
$fwrite(f,"%0d cycle :picorv32.v:1878\n"  , count_cycle); 
if (!resetn) begin 
is_beq_bne_blt_bge_bltu_bgeu <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1879\n"  , count_cycle); 
is_compare <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1881\n"  , count_cycle); 
 
instr_beq   <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1884\n"  , count_cycle); 
instr_bne   <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1886\n"  , count_cycle); 
instr_blt   <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1888\n"  , count_cycle); 
instr_bge   <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1890\n"  , count_cycle); 
instr_bltu  <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1892\n"  , count_cycle); 
instr_bgeu  <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1894\n"  , count_cycle); 
 
instr_addi  <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1897\n"  , count_cycle); 
instr_slti  <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1899\n"  , count_cycle); 
instr_sltiu <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1901\n"  , count_cycle); 
instr_xori  <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1903\n"  , count_cycle); 
instr_ori   <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1905\n"  , count_cycle); 
instr_andi  <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1907\n"  , count_cycle); 
 
instr_add   <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1910\n"  , count_cycle); 
instr_sub   <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1912\n"  , count_cycle); 
instr_sll   <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1914\n"  , count_cycle); 
instr_slt   <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1916\n"  , count_cycle); 
instr_sltu  <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1918\n"  , count_cycle); 
instr_xor   <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1920\n"  , count_cycle); 
instr_srl   <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1922\n"  , count_cycle); 
instr_sra   <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1924\n"  , count_cycle); 
instr_or    <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1926\n"  , count_cycle); 
instr_and   <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:1928\n"  , count_cycle); 
end 
end 
 
 
// Main State Machine 
 
localparam cpu_state_trap   = 8'b10000000; 
localparam cpu_state_fetch  = 8'b01000000; 
localparam cpu_state_ld_rs1 = 8'b00100000; 
localparam cpu_state_ld_rs2 = 8'b00010000; 
localparam cpu_state_exec   = 8'b00001000; 
localparam cpu_state_shift  = 8'b00000100; 
localparam cpu_state_stmem  = 8'b00000010; 
localparam cpu_state_ldmem  = 8'b00000001; 
 
reg [7:0] cpu_state; 
reg [1:0] irq_state; 
 
`FORMAL_KEEP reg [127:0] dbg_ascii_state; 
 
always @* begin 
dbg_ascii_state = ""; 
$fwrite(f,"%0d cycle :picorv32.v:1951\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:1953\n"  , count_cycle); 
if (cpu_state == cpu_state_trap) begin 
dbg_ascii_state = "trap"; 
$fwrite(f,"%0d cycle :picorv32.v:1955\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1958\n"  , count_cycle); 
if (cpu_state == cpu_state_fetch) begin 
dbg_ascii_state = "fetch"; 
$fwrite(f,"%0d cycle :picorv32.v:1960\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1963\n"  , count_cycle); 
if (cpu_state == cpu_state_ld_rs1) begin 
dbg_ascii_state = "ld_rs1"; 
$fwrite(f,"%0d cycle :picorv32.v:1965\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1968\n"  , count_cycle); 
if (cpu_state == cpu_state_ld_rs2) begin 
dbg_ascii_state = "ld_rs2"; 
$fwrite(f,"%0d cycle :picorv32.v:1970\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1973\n"  , count_cycle); 
if (cpu_state == cpu_state_exec) begin 
dbg_ascii_state = "exec"; 
$fwrite(f,"%0d cycle :picorv32.v:1975\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1978\n"  , count_cycle); 
if (cpu_state == cpu_state_shift) begin 
$fwrite(f,"%0d cycle :picorv32.v:1980\n"  , count_cycle); 
dbg_ascii_state = "shift"; 
end 
$fwrite(f,"%0d cycle :picorv32.v:1983\n"  , count_cycle); 
if (cpu_state == cpu_state_stmem) begin 
dbg_ascii_state = "stmem"; 
$fwrite(f,"%0d cycle :picorv32.v:1985\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:1988\n"  , count_cycle); 
if (cpu_state == cpu_state_ldmem) begin 
dbg_ascii_state = "ldmem"; 
$fwrite(f,"%0d cycle :picorv32.v:1990\n"  , count_cycle); 
end 
end 
 
reg set_mem_do_rinst; 
reg set_mem_do_rdata; 
reg set_mem_do_wdata; 
 
reg latched_store; 
reg latched_stalu; 
reg latched_branch; 
reg latched_compr; 
reg latched_trace; 
reg latched_is_lu; 
reg latched_is_lh; 
reg latched_is_lb; 
reg [regindex_bits-1:0] latched_rd; 
 
reg [31:0] current_pc; 
assign next_pc = latched_store && latched_branch ? reg_out & ~1 : reg_next_pc; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:2010\n"  , count_cycle); 
end 
 
reg [3:0] pcpi_timeout_counter; 
reg pcpi_timeout; 
 
reg [31:0] next_irq_pending; 
reg do_waitirq; 
 
reg [31:0] alu_out, alu_out_q; 
reg alu_out_0, alu_out_0_q; 
reg alu_wait, alu_wait_2; 
 
reg [31:0] alu_add_sub; 
reg [31:0] alu_shl, alu_shr; 
reg alu_eq, alu_ltu, alu_lts; 
 

generate if (TWO_CYCLE_ALU) begin 
always @(posedge clk) begin 
alu_add_sub <= instr_sub ? reg_op1 - reg_op2 : reg_op1 + reg_op2; 
$fwrite(f,"%0d cycle :picorv32.v:2032\n"  , count_cycle); 
alu_eq <= reg_op1 == reg_op2; 
$fwrite(f,"%0d cycle :picorv32.v:2034\n"  , count_cycle); 
alu_lts <= $signed(reg_op1) < $signed(reg_op2); 
$fwrite(f,"%0d cycle :picorv32.v:2036\n"  , count_cycle); 
alu_ltu <= reg_op1 < reg_op2; 
$fwrite(f,"%0d cycle :picorv32.v:2038\n"  , count_cycle); 
alu_shl <= reg_op1 << reg_op2[4:0]; 
$fwrite(f,"%0d cycle :picorv32.v:2040\n"  , count_cycle); 
alu_shr <= $signed({instr_sra || instr_srai ? reg_op1[31] : 1'b0, reg_op1}) >>> reg_op2[4:0]; 
$fwrite(f,"%0d cycle :picorv32.v:2042\n"  , count_cycle); 
end 
end else begin 
always @* begin 
alu_add_sub = instr_sub ? reg_op1 - reg_op2 : reg_op1 + reg_op2; 
$fwrite(f,"%0d cycle :picorv32.v:2047\n"  , count_cycle); 
alu_eq = reg_op1 == reg_op2; 
$fwrite(f,"%0d cycle :picorv32.v:2049\n"  , count_cycle); 
alu_lts = $signed(reg_op1) < $signed(reg_op2); 
$fwrite(f,"%0d cycle :picorv32.v:2051\n"  , count_cycle); 
alu_ltu = reg_op1 < reg_op2; 
$fwrite(f,"%0d cycle :picorv32.v:2053\n"  , count_cycle); 
alu_shl = reg_op1 << reg_op2[4:0]; 
$fwrite(f,"%0d cycle :picorv32.v:2055\n"  , count_cycle); 
alu_shr = $signed({instr_sra || instr_srai ? reg_op1[31] : 1'b0, reg_op1}) >>> reg_op2[4:0]; 
$fwrite(f,"%0d cycle :picorv32.v:2057\n"  , count_cycle); 
end 
end endgenerate 
 
always @* begin 
alu_out_0 = 'bx; 
$fwrite(f,"%0d cycle :picorv32.v:2063\n"  , count_cycle); 

(* parallel_case, full_case *) 

case (1'b1) 
instr_beq: begin 
alu_out_0 = alu_eq; 
$fwrite(f,"%0d cycle :picorv32.v:2070\n"  , count_cycle); 
end 
instr_bne: begin 
alu_out_0 = !alu_eq; 
$fwrite(f,"%0d cycle :picorv32.v:2074\n"  , count_cycle); 
end 
instr_bge: begin 
alu_out_0 = !alu_lts; 
$fwrite(f,"%0d cycle :picorv32.v:2078\n"  , count_cycle); 
end 
instr_bgeu: begin 
alu_out_0 = !alu_ltu; 
$fwrite(f,"%0d cycle :picorv32.v:2082\n"  , count_cycle); 
end 
is_slti_blt_slt && (!TWO_CYCLE_COMPARE || !{instr_beq,instr_bne,instr_bge,instr_bgeu}): begin 
alu_out_0 = alu_lts; 
$fwrite(f,"%0d cycle :picorv32.v:2086\n"  , count_cycle); 
end 
is_sltiu_bltu_sltu && (!TWO_CYCLE_COMPARE || !{instr_beq,instr_bne,instr_bge,instr_bgeu}): begin 
alu_out_0 = alu_ltu; 
$fwrite(f,"%0d cycle :picorv32.v:2090\n"  , count_cycle); 
end 
endcase 
 
alu_out = 'bx; 
$fwrite(f,"%0d cycle :picorv32.v:2095\n"  , count_cycle); 

(* parallel_case, full_case *) 

case (1'b1) 
is_lui_auipc_jal_jalr_addi_add_sub: begin 
alu_out = alu_add_sub; 
$fwrite(f,"%0d cycle :picorv32.v:2102\n"  , count_cycle); 
end 
is_compare: begin 
alu_out = alu_out_0; 
$fwrite(f,"%0d cycle :picorv32.v:2106\n"  , count_cycle); 
end 
instr_xori || instr_xor: begin 
alu_out = reg_op1 ^ reg_op2; 
$fwrite(f,"%0d cycle :picorv32.v:2110\n"  , count_cycle); 
end 
instr_ori || instr_or: begin 
alu_out = reg_op1 | reg_op2; 
$fwrite(f,"%0d cycle :picorv32.v:2114\n"  , count_cycle); 
end 
instr_andi || instr_and: begin 
alu_out = reg_op1 & reg_op2; 
$fwrite(f,"%0d cycle :picorv32.v:2118\n"  , count_cycle); 
end 
BARREL_SHIFTER && (instr_sll || instr_slli): begin 
alu_out = alu_shl; 
$fwrite(f,"%0d cycle :picorv32.v:2122\n"  , count_cycle); 
end 
BARREL_SHIFTER && (instr_srl || instr_srli || instr_sra || instr_srai): begin 
alu_out = alu_shr; 
$fwrite(f,"%0d cycle :picorv32.v:2126\n"  , count_cycle); 
end 
endcase 
 
`ifdef RISCV_FORMAL_BLACKBOX_ALU 
alu_out_0 = $anyseq; 
$fwrite(f,"%0d cycle :picorv32.v:2132\n"  , count_cycle); 
alu_out = $anyseq; 
$fwrite(f,"%0d cycle :picorv32.v:2134\n"  , count_cycle); 
`endif 
end 
 
reg clear_prefetched_high_word_q; 
always @(posedge clk) begin 
clear_prefetched_high_word_q <= clear_prefetched_high_word; 
$fwrite(f,"%0d cycle :picorv32.v:2141\n"  , count_cycle); 
end 
 
always @* begin 
clear_prefetched_high_word = clear_prefetched_high_word_q; 
$fwrite(f,"%0d cycle :picorv32.v:2146\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:2149\n"  , count_cycle); 
if (!prefetched_high_word) begin 
clear_prefetched_high_word = 0; 
$fwrite(f,"%0d cycle :picorv32.v:2150\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:2154\n"  , count_cycle); 
if (latched_branch || irq_state || !resetn) begin 
clear_prefetched_high_word = COMPRESSED_ISA; 
$fwrite(f,"%0d cycle :picorv32.v:2155\n"  , count_cycle); 
end 
end 
 
reg cpuregs_write; 
reg [31:0] cpuregs_wrdata; 
reg [31:0] cpuregs_rs1; 
reg [31:0] cpuregs_rs2; 
reg [regindex_bits-1:0] decoded_rs; 
 
always @* begin 
cpuregs_write = 0; 
$fwrite(f,"%0d cycle :picorv32.v:2167\n"  , count_cycle); 
cpuregs_wrdata = 'bx; 
$fwrite(f,"%0d cycle :picorv32.v:2169\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :picorv32.v:2172\n"  , count_cycle); 
if (cpu_state == cpu_state_fetch) begin 

(* parallel_case *) 

case (1'b1) 
latched_branch: begin 
cpuregs_wrdata = reg_pc + (latched_compr ? 2 : 4); 
$fwrite(f,"%0d cycle :picorv32.v:2179\n"  , count_cycle); 
cpuregs_write = 1; 
$fwrite(f,"%0d cycle :picorv32.v:2181\n"  , count_cycle); 
end 
latched_store && !latched_branch: begin 
cpuregs_wrdata = latched_stalu ? alu_out_q : reg_out; 
$fwrite(f,"%0d cycle :picorv32.v:2185\n"  , count_cycle); 
cpuregs_write = 1; 
$fwrite(f,"%0d cycle :picorv32.v:2187\n"  , count_cycle); 
end 
ENABLE_IRQ && irq_state[0]: begin 
cpuregs_wrdata = reg_next_pc | latched_compr; 
$fwrite(f,"%0d cycle :picorv32.v:2191\n"  , count_cycle); 
cpuregs_write = 1; 
$fwrite(f,"%0d cycle :picorv32.v:2193\n"  , count_cycle); 
end 
ENABLE_IRQ && irq_state[1]: begin 
cpuregs_wrdata = irq_pending & ~irq_mask; 
$fwrite(f,"%0d cycle :picorv32.v:2197\n"  , count_cycle); 
cpuregs_write = 1; 
$fwrite(f,"%0d cycle :picorv32.v:2199\n"  , count_cycle); 
end 
endcase 
end 
end 
 
`ifndef PICORV32_REGS 
always @(posedge clk) begin 
$fwrite(f,"%0d cycle :picorv32.v:2209\n"  , count_cycle); 
if (resetn && cpuregs_write && latched_rd) begin 
cpuregs[latched_rd] <= cpuregs_wrdata; 
$fwrite(f,"%0d cycle :picorv32.v:2210\n"  , count_cycle); 
end 
end 
 
always @* begin 
decoded_rs = 'bx; 
$fwrite(f,"%0d cycle :picorv32.v:2216\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:2219\n"  , count_cycle); 
if (ENABLE_REGS_DUALPORT) begin 
`ifndef RISCV_FORMAL_BLACKBOX_REGS 
cpuregs_rs1 = decoded_rs1 ? cpuregs[decoded_rs1] : 0; 
$fwrite(f,"%0d cycle :picorv32.v:2221\n"  , count_cycle); 
cpuregs_rs2 = decoded_rs2 ? cpuregs[decoded_rs2] : 0; 
$fwrite(f,"%0d cycle :picorv32.v:2223\n"  , count_cycle); 
`else 
cpuregs_rs1 = decoded_rs1 ? $anyseq : 0; 
$fwrite(f,"%0d cycle :picorv32.v:2226\n"  , count_cycle); 
cpuregs_rs2 = decoded_rs2 ? $anyseq : 0; 
$fwrite(f,"%0d cycle :picorv32.v:2228\n"  , count_cycle); 
`endif 
end else begin 
decoded_rs = (cpu_state == cpu_state_ld_rs2) ? decoded_rs2 : decoded_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:2232\n"  , count_cycle); 
`ifndef RISCV_FORMAL_BLACKBOX_REGS 
cpuregs_rs1 = decoded_rs ? cpuregs[decoded_rs] : 0; 
$fwrite(f,"%0d cycle :picorv32.v:2235\n"  , count_cycle); 
`else 
cpuregs_rs1 = decoded_rs ? $anyseq : 0; 
$fwrite(f,"%0d cycle :picorv32.v:2238\n"  , count_cycle); 
`endif 
cpuregs_rs2 = cpuregs_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:2241\n"  , count_cycle); 
end 
end 
`else 
wire[31:0] cpuregs_rdata1; 
wire[31:0] cpuregs_rdata2; 
 
wire [5:0] cpuregs_waddr = latched_rd; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:2249\n"  , count_cycle); 
end 
wire [5:0] cpuregs_raddr1 = ENABLE_REGS_DUALPORT ? decoded_rs1 : decoded_rs; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:2253\n"  , count_cycle); 
end 
wire [5:0] cpuregs_raddr2 = ENABLE_REGS_DUALPORT ? decoded_rs2 : 0; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:2257\n"  , count_cycle); 
end 
 
`PICORV32_REGS cpuregs ( 
.clk(clk), 
.wen(resetn && cpuregs_write && latched_rd), 
.waddr(cpuregs_waddr), 
.raddr1(cpuregs_raddr1), 
.raddr2(cpuregs_raddr2), 
.wdata(cpuregs_wrdata), 
.rdata1(cpuregs_rdata1), 
.rdata2(cpuregs_rdata2) 
); 
 
always @* begin 
decoded_rs = 'bx; 
$fwrite(f,"%0d cycle :picorv32.v:2274\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:2277\n"  , count_cycle); 
if (ENABLE_REGS_DUALPORT) begin 
cpuregs_rs1 = decoded_rs1 ? cpuregs_rdata1 : 0; 
$fwrite(f,"%0d cycle :picorv32.v:2278\n"  , count_cycle); 
cpuregs_rs2 = decoded_rs2 ? cpuregs_rdata2 : 0; 
$fwrite(f,"%0d cycle :picorv32.v:2280\n"  , count_cycle); 
end else begin 
decoded_rs = (cpu_state == cpu_state_ld_rs2) ? decoded_rs2 : decoded_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:2283\n"  , count_cycle); 
cpuregs_rs1 = decoded_rs ? cpuregs_rdata1 : 0; 
$fwrite(f,"%0d cycle :picorv32.v:2285\n"  , count_cycle); 
cpuregs_rs2 = cpuregs_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:2287\n"  , count_cycle); 
end 
end 
`endif 
 
assign launch_next_insn = cpu_state == cpu_state_fetch && decoder_trigger && (!ENABLE_IRQ || irq_delay || irq_active || !(irq_pending & ~irq_mask)); 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:2293\n"  , count_cycle); 
end 
 
always @(posedge clk) begin 
trap <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2299\n"  , count_cycle); 
reg_sh <= 'bx; 
$fwrite(f,"%0d cycle :picorv32.v:2301\n"  , count_cycle); 
reg_out <= 'bx; 
$fwrite(f,"%0d cycle :picorv32.v:2303\n"  , count_cycle); 
set_mem_do_rinst = 0; 
$fwrite(f,"%0d cycle :picorv32.v:2305\n"  , count_cycle); 
set_mem_do_rdata = 0; 
$fwrite(f,"%0d cycle :picorv32.v:2307\n"  , count_cycle); 
set_mem_do_wdata = 0; 
$fwrite(f,"%0d cycle :picorv32.v:2309\n"  , count_cycle); 
 
alu_out_0_q <= alu_out_0; 
$fwrite(f,"%0d cycle :picorv32.v:2312\n"  , count_cycle); 
alu_out_q <= alu_out; 
$fwrite(f,"%0d cycle :picorv32.v:2314\n"  , count_cycle); 
 
alu_wait <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2317\n"  , count_cycle); 
alu_wait_2 <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2319\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :picorv32.v:2323\n"  , count_cycle); 
if (launch_next_insn) begin 
dbg_rs1val <= 'bx; 
$fwrite(f,"%0d cycle :picorv32.v:2324\n"  , count_cycle); 
dbg_rs2val <= 'bx; 
$fwrite(f,"%0d cycle :picorv32.v:2326\n"  , count_cycle); 
dbg_rs1val_valid <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2328\n"  , count_cycle); 
dbg_rs2val_valid <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2330\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :picorv32.v:2335\n"  , count_cycle); 
if (WITH_PCPI && CATCH_ILLINSN) begin 
$fwrite(f,"%0d cycle :picorv32.v:2337\n"  , count_cycle); 
if (resetn && pcpi_valid && !pcpi_int_wait) begin 
$fwrite(f,"%0d cycle :picorv32.v:2339\n"  , count_cycle); 
if (pcpi_timeout_counter) begin 
pcpi_timeout_counter <= pcpi_timeout_counter - 1; 
$fwrite(f,"%0d cycle :picorv32.v:2340\n"  , count_cycle); 
end 
end else 
pcpi_timeout_counter <= ~0; 
$fwrite(f,"%0d cycle :picorv32.v:2344\n"  , count_cycle); 
pcpi_timeout <= !pcpi_timeout_counter; 
$fwrite(f,"%0d cycle :picorv32.v:2346\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :picorv32.v:2351\n"  , count_cycle); 
if (ENABLE_COUNTERS) begin 
count_cycle <= resetn ? count_cycle + 1 : 0; 
$fwrite(f,"%0d cycle :picorv32.v:2352\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:2355\n"  , count_cycle); 
if (!ENABLE_COUNTERS64) begin 
count_cycle[63:32] <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2356\n"  , count_cycle); 
end 
end else begin 
count_cycle <= 'bx; 
$fwrite(f,"%0d cycle :picorv32.v:2360\n"  , count_cycle); 
count_instr <= 'bx; 
$fwrite(f,"%0d cycle :picorv32.v:2362\n"  , count_cycle); 
end 
 
next_irq_pending = ENABLE_IRQ ? irq_pending & LATCHED_IRQ : 'bx; 
$fwrite(f,"%0d cycle :picorv32.v:2366\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :picorv32.v:2370\n"  , count_cycle); 
if (ENABLE_IRQ && ENABLE_IRQ_TIMER && timer) begin 
$fwrite(f,"%0d cycle :picorv32.v:2371\n"  , count_cycle); 
if (timer - 1 == 0) begin 
next_irq_pending[irq_timer] = 1; 
$fwrite(f,"%0d cycle :picorv32.v:2373\n"  , count_cycle); 
end 
timer <= timer - 1; 
$fwrite(f,"%0d cycle :picorv32.v:2376\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :picorv32.v:2381\n"  , count_cycle); 
if (ENABLE_IRQ) begin 
next_irq_pending = next_irq_pending | irq; 
$fwrite(f,"%0d cycle :picorv32.v:2382\n"  , count_cycle); 
end 
 
decoder_trigger <= mem_do_rinst && mem_done; 
$fwrite(f,"%0d cycle :picorv32.v:2386\n"  , count_cycle); 
decoder_trigger_q <= decoder_trigger; 
$fwrite(f,"%0d cycle :picorv32.v:2388\n"  , count_cycle); 
decoder_pseudo_trigger <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2390\n"  , count_cycle); 
decoder_pseudo_trigger_q <= decoder_pseudo_trigger; 
$fwrite(f,"%0d cycle :picorv32.v:2392\n"  , count_cycle); 
do_waitirq <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2394\n"  , count_cycle); 
 
trace_valid <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2397\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :picorv32.v:2401\n"  , count_cycle); 
if (!ENABLE_TRACE) begin 
trace_data <= 'bx; 
$fwrite(f,"%0d cycle :picorv32.v:2402\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :picorv32.v:2407\n"  , count_cycle); 
if (!resetn) begin 
reg_pc <= PROGADDR_RESET; 
$fwrite(f,"%0d cycle :picorv32.v:2408\n"  , count_cycle); 
reg_next_pc <= PROGADDR_RESET; 
$fwrite(f,"%0d cycle :picorv32.v:2410\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:2413\n"  , count_cycle); 
if (ENABLE_COUNTERS) begin 
count_instr <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2414\n"  , count_cycle); 
end 
latched_store <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2417\n"  , count_cycle); 
latched_stalu <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2419\n"  , count_cycle); 
latched_branch <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2421\n"  , count_cycle); 
latched_trace <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2423\n"  , count_cycle); 
latched_is_lu <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2425\n"  , count_cycle); 
latched_is_lh <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2427\n"  , count_cycle); 
latched_is_lb <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2429\n"  , count_cycle); 
pcpi_valid <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2431\n"  , count_cycle); 
pcpi_timeout <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2433\n"  , count_cycle); 
irq_active <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2435\n"  , count_cycle); 
irq_delay <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2437\n"  , count_cycle); 
irq_mask <= ~0; 
$fwrite(f,"%0d cycle :picorv32.v:2439\n"  , count_cycle); 
next_irq_pending = 0; 
$fwrite(f,"%0d cycle :picorv32.v:2441\n"  , count_cycle); 
irq_state <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2443\n"  , count_cycle); 
eoi <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2445\n"  , count_cycle); 
timer <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2447\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:2450\n"  , count_cycle); 
if (~STACKADDR) begin 
latched_store <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2451\n"  , count_cycle); 
latched_rd <= 2; 
$fwrite(f,"%0d cycle :picorv32.v:2453\n"  , count_cycle); 
reg_out <= STACKADDR; 
$fwrite(f,"%0d cycle :picorv32.v:2455\n"  , count_cycle); 
end 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :picorv32.v:2458\n"  , count_cycle); 
end else 

(* parallel_case, full_case *) 

case (cpu_state) 
cpu_state_trap: begin 
trap <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2466\n"  , count_cycle); 
end 
 
cpu_state_fetch: begin 
mem_do_rinst <= !decoder_trigger && !do_waitirq; 
$fwrite(f,"%0d cycle :picorv32.v:2471\n"  , count_cycle); 
mem_wordsize <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2473\n"  , count_cycle); 
 
current_pc = reg_next_pc; 
$fwrite(f,"%0d cycle :picorv32.v:2476\n"  , count_cycle); 
 

(* parallel_case *) 

case (1'b1) 
latched_branch: begin 
current_pc = latched_store ? (latched_stalu ? alu_out_q : reg_out) & ~1 : reg_next_pc; 
$fwrite(f,"%0d cycle :picorv32.v:2484\n"  , count_cycle); 
`debug($display("ST_RD:  %2d 0x%08x, BRANCH 0x%08x", latched_rd, reg_pc + (latched_compr ? 2 : 4), current_pc);) 
end 
latched_store && !latched_branch: begin 
`debug($display("ST_RD:  %2d 0x%08x", latched_rd, latched_stalu ? alu_out_q : reg_out);) 
end 
ENABLE_IRQ && irq_state[0]: begin 
current_pc = PROGADDR_IRQ; 
$fwrite(f,"%0d cycle :picorv32.v:2492\n"  , count_cycle); 
irq_active <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2494\n"  , count_cycle); 
mem_do_rinst <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2496\n"  , count_cycle); 
end 
ENABLE_IRQ && irq_state[1]: begin 
eoi <= irq_pending & ~irq_mask; 
$fwrite(f,"%0d cycle :picorv32.v:2500\n"  , count_cycle); 
next_irq_pending = next_irq_pending & irq_mask; 
$fwrite(f,"%0d cycle :picorv32.v:2502\n"  , count_cycle); 
end 
endcase 
 
$fwrite(f,"%0d cycle :picorv32.v:2508\n"  , count_cycle); 
if (ENABLE_TRACE && latched_trace) begin 
latched_trace <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2509\n"  , count_cycle); 
trace_valid <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2511\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:2514\n"  , count_cycle); 
if (latched_branch) begin 
trace_data <= (irq_active ? TRACE_IRQ : 0) | TRACE_BRANCH | (current_pc & 32'hfffffffe); 
$fwrite(f,"%0d cycle :picorv32.v:2515\n"  , count_cycle); 
end 
else 
trace_data <= (irq_active ? TRACE_IRQ : 0) | (latched_stalu ? alu_out_q : reg_out); 
$fwrite(f,"%0d cycle :picorv32.v:2519\n"  , count_cycle); 
end 
 
reg_pc <= current_pc; 
$fwrite(f,"%0d cycle :picorv32.v:2523\n"  , count_cycle); 
reg_next_pc <= current_pc; 
$fwrite(f,"%0d cycle :picorv32.v:2525\n"  , count_cycle); 
 
latched_store <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2528\n"  , count_cycle); 
latched_stalu <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2530\n"  , count_cycle); 
latched_branch <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2532\n"  , count_cycle); 
latched_is_lu <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2534\n"  , count_cycle); 
latched_is_lh <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2536\n"  , count_cycle); 
latched_is_lb <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2538\n"  , count_cycle); 
latched_rd <= decoded_rd; 
$fwrite(f,"%0d cycle :picorv32.v:2540\n"  , count_cycle); 
latched_compr <= compressed_instr; 
$fwrite(f,"%0d cycle :picorv32.v:2542\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :picorv32.v:2546\n"  , count_cycle); 
if (ENABLE_IRQ && ((decoder_trigger && !irq_active && !irq_delay && |(irq_pending & ~irq_mask)) || irq_state)) begin 
irq_state <=irq_state == 2'b00 ? 2'b01 :irq_state == 2'b01 ? 2'b10 : 2'b00; 
$fwrite(f,"%0d cycle :picorv32.v:2547\n"  , count_cycle); 
latched_compr <= latched_compr; 
$fwrite(f,"%0d cycle :picorv32.v:2549\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:2552\n"  , count_cycle); 
if (ENABLE_IRQ_QREGS) begin 
latched_rd <= irqregs_offset | irq_state[0]; 
$fwrite(f,"%0d cycle :picorv32.v:2553\n"  , count_cycle); 
end 
else 
latched_rd <= irq_state[0] ? 4 : 3; 
$fwrite(f,"%0d cycle :picorv32.v:2557\n"  , count_cycle); 
end else 
$fwrite(f,"%0d cycle :picorv32.v:2561\n"  , count_cycle); 
if (ENABLE_IRQ && (decoder_trigger || do_waitirq) && instr_waitirq) begin 
$fwrite(f,"%0d cycle :picorv32.v:2563\n"  , count_cycle); 
if (irq_pending) begin 
latched_store <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2564\n"  , count_cycle); 
reg_out <= irq_pending; 
$fwrite(f,"%0d cycle :picorv32.v:2566\n"  , count_cycle); 
reg_next_pc <= current_pc + (compressed_instr ? 2 : 4); 
$fwrite(f,"%0d cycle :picorv32.v:2568\n"  , count_cycle); 
mem_do_rinst <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2570\n"  , count_cycle); 
end else 
do_waitirq <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2573\n"  , count_cycle); 
end else 
$fwrite(f,"%0d cycle :picorv32.v:2577\n"  , count_cycle); 
if (decoder_trigger) begin 
`debug($display("-- %-0t", $time);) 
irq_delay <= irq_active; 
$fwrite(f,"%0d cycle :picorv32.v:2579\n"  , count_cycle); 
reg_next_pc <= current_pc + (compressed_instr ? 2 : 4); 
$fwrite(f,"%0d cycle :picorv32.v:2581\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:2584\n"  , count_cycle); 
if (ENABLE_TRACE) begin 
latched_trace <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2585\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:2589\n"  , count_cycle); 
if (ENABLE_COUNTERS) begin 
count_instr <= count_instr + 1; 
$fwrite(f,"%0d cycle :picorv32.v:2590\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:2593\n"  , count_cycle); 
if (!ENABLE_COUNTERS64) begin 
count_instr[63:32] <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2594\n"  , count_cycle); 
end 
end 
$fwrite(f,"%0d cycle :picorv32.v:2599\n"  , count_cycle); 
if (instr_jal) begin 
mem_do_rinst <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2600\n"  , count_cycle); 
reg_next_pc <= current_pc + decoded_imm_j; 
$fwrite(f,"%0d cycle :picorv32.v:2602\n"  , count_cycle); 
latched_branch <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2604\n"  , count_cycle); 
end else begin 
mem_do_rinst <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2607\n"  , count_cycle); 
mem_do_prefetch <= !instr_jalr && !instr_retirq; 
$fwrite(f,"%0d cycle :picorv32.v:2609\n"  , count_cycle); 
cpu_state <= cpu_state_ld_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:2611\n"  , count_cycle); 
end 
end 
end 
 
cpu_state_ld_rs1: begin 
reg_op1 <= 'bx; 
$fwrite(f,"%0d cycle :picorv32.v:2618\n"  , count_cycle); 
reg_op2 <= 'bx; 
$fwrite(f,"%0d cycle :picorv32.v:2620\n"  , count_cycle); 
 

(* parallel_case *) 

case (1'b1) 
(CATCH_ILLINSN || WITH_PCPI) && instr_trap: begin 
$fwrite(f,"%0d cycle :picorv32.v:2629\n"  , count_cycle); 
if (WITH_PCPI) begin 
`debug($display("LD_RS1: %2d 0x%08x", decoded_rs1, cpuregs_rs1);) 
reg_op1 <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:2631\n"  , count_cycle); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:2633\n"  , count_cycle); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2635\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:2638\n"  , count_cycle); 
if (ENABLE_REGS_DUALPORT) begin 
pcpi_valid <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2639\n"  , count_cycle); 
`debug($display("LD_RS2: %2d 0x%08x", decoded_rs2, cpuregs_rs2);) 
reg_sh <= cpuregs_rs2; 
$fwrite(f,"%0d cycle :picorv32.v:2642\n"  , count_cycle); 
reg_op2 <= cpuregs_rs2; 
$fwrite(f,"%0d cycle :picorv32.v:2644\n"  , count_cycle); 
dbg_rs2val <= cpuregs_rs2; 
$fwrite(f,"%0d cycle :picorv32.v:2646\n"  , count_cycle); 
dbg_rs2val_valid <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2648\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:2651\n"  , count_cycle); 
if (pcpi_int_ready) begin 
mem_do_rinst <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2652\n"  , count_cycle); 
pcpi_valid <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2654\n"  , count_cycle); 
reg_out <= pcpi_int_rd; 
$fwrite(f,"%0d cycle :picorv32.v:2656\n"  , count_cycle); 
latched_store <= pcpi_int_wr; 
$fwrite(f,"%0d cycle :picorv32.v:2658\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :picorv32.v:2660\n"  , count_cycle); 
end else 
$fwrite(f,"%0d cycle :picorv32.v:2664\n"  , count_cycle); 
if (CATCH_ILLINSN && (pcpi_timeout || instr_ecall_ebreak)) begin 
pcpi_valid <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2665\n"  , count_cycle); 
`debug($display("EBREAK OR UNSUPPORTED INSN AT 0x%08x", reg_pc);) 
$fwrite(f,"%0d cycle :picorv32.v:2669\n"  , count_cycle); 
if (ENABLE_IRQ && !irq_mask[irq_ebreak] && !irq_active) begin 
next_irq_pending[irq_ebreak] = 1; 
$fwrite(f,"%0d cycle :picorv32.v:2670\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :picorv32.v:2672\n"  , count_cycle); 
end else 
cpu_state <= cpu_state_trap; 
$fwrite(f,"%0d cycle :picorv32.v:2675\n"  , count_cycle); 
end 
end else begin 
cpu_state <= cpu_state_ld_rs2; 
$fwrite(f,"%0d cycle :picorv32.v:2679\n"  , count_cycle); 
end 
end else begin 
`debug($display("EBREAK OR UNSUPPORTED INSN AT 0x%08x", reg_pc);) 
$fwrite(f,"%0d cycle :picorv32.v:2685\n"  , count_cycle); 
if (ENABLE_IRQ && !irq_mask[irq_ebreak] && !irq_active) begin 
next_irq_pending[irq_ebreak] = 1; 
$fwrite(f,"%0d cycle :picorv32.v:2686\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :picorv32.v:2688\n"  , count_cycle); 
end else 
cpu_state <= cpu_state_trap; 
$fwrite(f,"%0d cycle :picorv32.v:2691\n"  , count_cycle); 
end 
end 
ENABLE_COUNTERS && is_rdcycle_rdcycleh_rdinstr_rdinstrh: begin 

(* parallel_case, full_case *) 

case (1'b1) 
instr_rdcycle: begin 
reg_out <= count_cycle[31:0]; 
$fwrite(f,"%0d cycle :picorv32.v:2701\n"  , count_cycle); 
end 
instr_rdcycleh && ENABLE_COUNTERS64: begin 
reg_out <= count_cycle[63:32]; 
$fwrite(f,"%0d cycle :picorv32.v:2705\n"  , count_cycle); 
end 
instr_rdinstr: begin 
reg_out <= count_instr[31:0]; 
$fwrite(f,"%0d cycle :picorv32.v:2709\n"  , count_cycle); 
end 
instr_rdinstrh && ENABLE_COUNTERS64: begin 
reg_out <= count_instr[63:32]; 
$fwrite(f,"%0d cycle :picorv32.v:2713\n"  , count_cycle); 
end 
endcase 
latched_store <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2717\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :picorv32.v:2719\n"  , count_cycle); 
end 
is_lui_auipc_jal: begin 
reg_op1 <= instr_lui ? 0 : reg_pc; 
$fwrite(f,"%0d cycle :picorv32.v:2723\n"  , count_cycle); 
reg_op2 <= decoded_imm; 
$fwrite(f,"%0d cycle :picorv32.v:2725\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:2728\n"  , count_cycle); 
if (TWO_CYCLE_ALU) begin 
alu_wait <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2729\n"  , count_cycle); 
end 
else 
mem_do_rinst <= mem_do_prefetch; 
$fwrite(f,"%0d cycle :picorv32.v:2733\n"  , count_cycle); 
cpu_state <= cpu_state_exec; 
$fwrite(f,"%0d cycle :picorv32.v:2735\n"  , count_cycle); 
end 
ENABLE_IRQ && ENABLE_IRQ_QREGS && instr_getq: begin 
`debug($display("LD_RS1: %2d 0x%08x", decoded_rs1, cpuregs_rs1);) 
reg_out <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:2740\n"  , count_cycle); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:2742\n"  , count_cycle); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2744\n"  , count_cycle); 
latched_store <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2746\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :picorv32.v:2748\n"  , count_cycle); 
end 
ENABLE_IRQ && ENABLE_IRQ_QREGS && instr_setq: begin 
`debug($display("LD_RS1: %2d 0x%08x", decoded_rs1, cpuregs_rs1);) 
reg_out <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:2753\n"  , count_cycle); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:2755\n"  , count_cycle); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2757\n"  , count_cycle); 
latched_rd <= latched_rd | irqregs_offset; 
$fwrite(f,"%0d cycle :picorv32.v:2759\n"  , count_cycle); 
latched_store <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2761\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :picorv32.v:2763\n"  , count_cycle); 
end 
ENABLE_IRQ && instr_retirq: begin 
eoi <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2767\n"  , count_cycle); 
irq_active <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2769\n"  , count_cycle); 
latched_branch <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2771\n"  , count_cycle); 
latched_store <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2773\n"  , count_cycle); 
`debug($display("LD_RS1: %2d 0x%08x", decoded_rs1, cpuregs_rs1);) 
reg_out <= CATCH_MISALIGN ? (cpuregs_rs1 & 32'h fffffffe) : cpuregs_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:2776\n"  , count_cycle); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:2778\n"  , count_cycle); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2780\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :picorv32.v:2782\n"  , count_cycle); 
end 
ENABLE_IRQ && instr_maskirq: begin 
latched_store <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2786\n"  , count_cycle); 
reg_out <= irq_mask; 
$fwrite(f,"%0d cycle :picorv32.v:2788\n"  , count_cycle); 
`debug($display("LD_RS1: %2d 0x%08x", decoded_rs1, cpuregs_rs1);) 
irq_mask <= cpuregs_rs1 | MASKED_IRQ; 
$fwrite(f,"%0d cycle :picorv32.v:2791\n"  , count_cycle); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:2793\n"  , count_cycle); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2795\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :picorv32.v:2797\n"  , count_cycle); 
end 
ENABLE_IRQ && ENABLE_IRQ_TIMER && instr_timer: begin 
latched_store <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2801\n"  , count_cycle); 
reg_out <= timer; 
$fwrite(f,"%0d cycle :picorv32.v:2803\n"  , count_cycle); 
`debug($display("LD_RS1: %2d 0x%08x", decoded_rs1, cpuregs_rs1);) 
timer <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:2806\n"  , count_cycle); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:2808\n"  , count_cycle); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2810\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :picorv32.v:2812\n"  , count_cycle); 
end 
is_lb_lh_lw_lbu_lhu && !instr_trap: begin 
`debug($display("LD_RS1: %2d 0x%08x", decoded_rs1, cpuregs_rs1);) 
reg_op1 <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:2817\n"  , count_cycle); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:2819\n"  , count_cycle); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2821\n"  , count_cycle); 
cpu_state <= cpu_state_ldmem; 
$fwrite(f,"%0d cycle :picorv32.v:2823\n"  , count_cycle); 
mem_do_rinst <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2825\n"  , count_cycle); 
end 
is_slli_srli_srai && !BARREL_SHIFTER: begin 
`debug($display("LD_RS1: %2d 0x%08x", decoded_rs1, cpuregs_rs1);) 
reg_op1 <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:2830\n"  , count_cycle); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:2832\n"  , count_cycle); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2834\n"  , count_cycle); 
reg_sh <= decoded_rs2; 
$fwrite(f,"%0d cycle :picorv32.v:2836\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:2838\n"  , count_cycle); 
cpu_state <= cpu_state_shift; 
end 
is_jalr_addi_slti_sltiu_xori_ori_andi, is_slli_srli_srai && BARREL_SHIFTER: begin 
`debug($display("LD_RS1: %2d 0x%08x", decoded_rs1, cpuregs_rs1);) 
reg_op1 <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:2843\n"  , count_cycle); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:2845\n"  , count_cycle); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2847\n"  , count_cycle); 
reg_op2 <= is_slli_srli_srai && BARREL_SHIFTER ? decoded_rs2 : decoded_imm; 
$fwrite(f,"%0d cycle :picorv32.v:2849\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:2852\n"  , count_cycle); 
if (TWO_CYCLE_ALU) begin 
alu_wait <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2853\n"  , count_cycle); 
end 
else 
mem_do_rinst <= mem_do_prefetch; 
$fwrite(f,"%0d cycle :picorv32.v:2857\n"  , count_cycle); 
cpu_state <= cpu_state_exec; 
$fwrite(f,"%0d cycle :picorv32.v:2859\n"  , count_cycle); 
end 
default: begin 
`debug($display("LD_RS1: %2d 0x%08x", decoded_rs1, cpuregs_rs1);) 
reg_op1 <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:2864\n"  , count_cycle); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:2866\n"  , count_cycle); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2868\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:2871\n"  , count_cycle); 
if (ENABLE_REGS_DUALPORT) begin 
`debug($display("LD_RS2: %2d 0x%08x", decoded_rs2, cpuregs_rs2);) 
reg_sh <= cpuregs_rs2; 
$fwrite(f,"%0d cycle :picorv32.v:2873\n"  , count_cycle); 
reg_op2 <= cpuregs_rs2; 
$fwrite(f,"%0d cycle :picorv32.v:2875\n"  , count_cycle); 
dbg_rs2val <= cpuregs_rs2; 
$fwrite(f,"%0d cycle :picorv32.v:2877\n"  , count_cycle); 
dbg_rs2val_valid <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2879\n"  , count_cycle); 

(* parallel_case *) 

case (1'b1) 
is_sb_sh_sw: begin 
cpu_state <= cpu_state_stmem; 
$fwrite(f,"%0d cycle :picorv32.v:2886\n"  , count_cycle); 
mem_do_rinst <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2888\n"  , count_cycle); 
end 
is_sll_srl_sra && !BARREL_SHIFTER: begin 
$fwrite(f,"%0d cycle :picorv32.v:2892\n"  , count_cycle); 
cpu_state <= cpu_state_shift; 
end 
default: begin 
$fwrite(f,"%0d cycle :picorv32.v:2897\n"  , count_cycle); 
if (TWO_CYCLE_ALU || (TWO_CYCLE_COMPARE && is_beq_bne_blt_bge_bltu_bgeu)) begin 
alu_wait_2 <= TWO_CYCLE_ALU && (TWO_CYCLE_COMPARE && is_beq_bne_blt_bge_bltu_bgeu); 
$fwrite(f,"%0d cycle :picorv32.v:2898\n"  , count_cycle); 
alu_wait <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2900\n"  , count_cycle); 
end else 
mem_do_rinst <= mem_do_prefetch; 
$fwrite(f,"%0d cycle :picorv32.v:2903\n"  , count_cycle); 
cpu_state <= cpu_state_exec; 
$fwrite(f,"%0d cycle :picorv32.v:2905\n"  , count_cycle); 
end 
endcase 
end else 
cpu_state <= cpu_state_ld_rs2; 
$fwrite(f,"%0d cycle :picorv32.v:2910\n"  , count_cycle); 
end 
endcase 
end 
 
cpu_state_ld_rs2: begin 
`debug($display("LD_RS2: %2d 0x%08x", decoded_rs2, cpuregs_rs2);) 
reg_sh <= cpuregs_rs2; 
$fwrite(f,"%0d cycle :picorv32.v:2918\n"  , count_cycle); 
reg_op2 <= cpuregs_rs2; 
$fwrite(f,"%0d cycle :picorv32.v:2920\n"  , count_cycle); 
dbg_rs2val <= cpuregs_rs2; 
$fwrite(f,"%0d cycle :picorv32.v:2922\n"  , count_cycle); 
dbg_rs2val_valid <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2924\n"  , count_cycle); 
 

(* parallel_case *) 

case (1'b1) 
WITH_PCPI && instr_trap: begin 
pcpi_valid <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2932\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:2935\n"  , count_cycle); 
if (pcpi_int_ready) begin 
mem_do_rinst <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2936\n"  , count_cycle); 
pcpi_valid <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2938\n"  , count_cycle); 
reg_out <= pcpi_int_rd; 
$fwrite(f,"%0d cycle :picorv32.v:2940\n"  , count_cycle); 
latched_store <= pcpi_int_wr; 
$fwrite(f,"%0d cycle :picorv32.v:2942\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :picorv32.v:2944\n"  , count_cycle); 
end else 
$fwrite(f,"%0d cycle :picorv32.v:2948\n"  , count_cycle); 
if (CATCH_ILLINSN && (pcpi_timeout || instr_ecall_ebreak)) begin 
pcpi_valid <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:2949\n"  , count_cycle); 
`debug($display("EBREAK OR UNSUPPORTED INSN AT 0x%08x", reg_pc);) 
$fwrite(f,"%0d cycle :picorv32.v:2953\n"  , count_cycle); 
if (ENABLE_IRQ && !irq_mask[irq_ebreak] && !irq_active) begin 
next_irq_pending[irq_ebreak] = 1; 
$fwrite(f,"%0d cycle :picorv32.v:2954\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :picorv32.v:2956\n"  , count_cycle); 
end else 
cpu_state <= cpu_state_trap; 
$fwrite(f,"%0d cycle :picorv32.v:2959\n"  , count_cycle); 
end 
end 
is_sb_sh_sw: begin 
cpu_state <= cpu_state_stmem; 
$fwrite(f,"%0d cycle :picorv32.v:2964\n"  , count_cycle); 
mem_do_rinst <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2966\n"  , count_cycle); 
end 
is_sll_srl_sra && !BARREL_SHIFTER: begin 
$fwrite(f,"%0d cycle :picorv32.v:2970\n"  , count_cycle); 
cpu_state <= cpu_state_shift; 
end 
default: begin 
$fwrite(f,"%0d cycle :picorv32.v:2975\n"  , count_cycle); 
if (TWO_CYCLE_ALU || (TWO_CYCLE_COMPARE && is_beq_bne_blt_bge_bltu_bgeu)) begin 
alu_wait_2 <= TWO_CYCLE_ALU && (TWO_CYCLE_COMPARE && is_beq_bne_blt_bge_bltu_bgeu); 
$fwrite(f,"%0d cycle :picorv32.v:2976\n"  , count_cycle); 
alu_wait <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:2978\n"  , count_cycle); 
end else 
mem_do_rinst <= mem_do_prefetch; 
$fwrite(f,"%0d cycle :picorv32.v:2981\n"  , count_cycle); 
cpu_state <= cpu_state_exec; 
$fwrite(f,"%0d cycle :picorv32.v:2983\n"  , count_cycle); 
end 
endcase 
end 
 
cpu_state_exec: begin 
reg_out <= reg_pc + decoded_imm; 
$fwrite(f,"%0d cycle :picorv32.v:2990\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:2993\n"  , count_cycle); 
if ((TWO_CYCLE_ALU || TWO_CYCLE_COMPARE) && (alu_wait || alu_wait_2)) begin 
mem_do_rinst <= mem_do_prefetch && !alu_wait_2; 
$fwrite(f,"%0d cycle :picorv32.v:2994\n"  , count_cycle); 
alu_wait <= alu_wait_2; 
$fwrite(f,"%0d cycle :picorv32.v:2996\n"  , count_cycle); 
end else 
$fwrite(f,"%0d cycle :picorv32.v:3000\n"  , count_cycle); 
if (is_beq_bne_blt_bge_bltu_bgeu) begin 
latched_rd <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3001\n"  , count_cycle); 
latched_store <= TWO_CYCLE_COMPARE ? alu_out_0_q : alu_out_0; 
$fwrite(f,"%0d cycle :picorv32.v:3003\n"  , count_cycle); 
latched_branch <= TWO_CYCLE_COMPARE ? alu_out_0_q : alu_out_0; 
$fwrite(f,"%0d cycle :picorv32.v:3005\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:3008\n"  , count_cycle); 
if (mem_done) begin 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :picorv32.v:3009\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:3013\n"  , count_cycle); 
if (TWO_CYCLE_COMPARE ? alu_out_0_q : alu_out_0) begin 
decoder_trigger <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3014\n"  , count_cycle); 
set_mem_do_rinst = 1; 
$fwrite(f,"%0d cycle :picorv32.v:3016\n"  , count_cycle); 
end 
end else begin 
latched_branch <= instr_jalr; 
$fwrite(f,"%0d cycle :picorv32.v:3020\n"  , count_cycle); 
latched_store <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3022\n"  , count_cycle); 
latched_stalu <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3024\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :picorv32.v:3026\n"  , count_cycle); 
end 
end 
 
cpu_state_shift: begin 
latched_store <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3032\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:3034\n"  , count_cycle); 
if (reg_sh == 0) begin 
reg_out <= reg_op1; 
$fwrite(f,"%0d cycle :picorv32.v:3036\n"  , count_cycle); 
mem_do_rinst <= mem_do_prefetch; 
$fwrite(f,"%0d cycle :picorv32.v:3038\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :picorv32.v:3040\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:3042\n"  , count_cycle); 
end else if (TWO_STAGE_SHIFT && reg_sh >= 4) begin 

(* parallel_case, full_case *) 

case (1'b1) 
instr_slli || instr_sll: begin 
reg_op1 <= reg_op1 << 4; 
$fwrite(f,"%0d cycle :picorv32.v:3049\n"  , count_cycle); 
end 
instr_srli || instr_srl: begin 
reg_op1 <= reg_op1 >> 4; 
$fwrite(f,"%0d cycle :picorv32.v:3053\n"  , count_cycle); 
end 
instr_srai || instr_sra: begin 
reg_op1 <= $signed(reg_op1) >>> 4; 
$fwrite(f,"%0d cycle :picorv32.v:3057\n"  , count_cycle); 
end 
endcase 
reg_sh <= reg_sh - 4; 
$fwrite(f,"%0d cycle :picorv32.v:3061\n"  , count_cycle); 
end else begin 

(* parallel_case, full_case *) 

case (1'b1) 
instr_slli || instr_sll: begin 
reg_op1 <= reg_op1 << 1; 
$fwrite(f,"%0d cycle :picorv32.v:3069\n"  , count_cycle); 
end 
instr_srli || instr_srl: begin 
reg_op1 <= reg_op1 >> 1; 
$fwrite(f,"%0d cycle :picorv32.v:3073\n"  , count_cycle); 
end 
instr_srai || instr_sra: begin 
reg_op1 <= $signed(reg_op1) >>> 1; 
$fwrite(f,"%0d cycle :picorv32.v:3077\n"  , count_cycle); 
end 
endcase 
reg_sh <= reg_sh - 1; 
$fwrite(f,"%0d cycle :picorv32.v:3081\n"  , count_cycle); 
end 
end 
 
cpu_state_stmem: begin 
$fwrite(f,"%0d cycle :picorv32.v:3088\n"  , count_cycle); 
if (ENABLE_TRACE) begin 
reg_out <= reg_op2; 
$fwrite(f,"%0d cycle :picorv32.v:3089\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:3093\n"  , count_cycle); 
if (!mem_do_prefetch || mem_done) begin 
$fwrite(f,"%0d cycle :picorv32.v:3095\n"  , count_cycle); 
if (!mem_do_wdata) begin 

(* parallel_case, full_case *) 

case (1'b1) 
instr_sb: begin 
mem_wordsize <= 2; 
$fwrite(f,"%0d cycle :picorv32.v:3101\n"  , count_cycle); 
end 
instr_sh: begin 
mem_wordsize <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3105\n"  , count_cycle); 
end 
instr_sw: begin 
mem_wordsize <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3109\n"  , count_cycle); 
end 
endcase 
$fwrite(f,"%0d cycle :picorv32.v:3114\n"  , count_cycle); 
if (ENABLE_TRACE) begin 
trace_valid <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3115\n"  , count_cycle); 
trace_data <= (irq_active ? TRACE_IRQ : 0) | TRACE_ADDR | ((reg_op1 + decoded_imm) & 32'hffffffff); 
$fwrite(f,"%0d cycle :picorv32.v:3117\n"  , count_cycle); 
end 
reg_op1 <= reg_op1 + decoded_imm; 
$fwrite(f,"%0d cycle :picorv32.v:3120\n"  , count_cycle); 
set_mem_do_wdata = 1; 
$fwrite(f,"%0d cycle :picorv32.v:3122\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:3126\n"  , count_cycle); 
if (!mem_do_prefetch && mem_done) begin 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :picorv32.v:3127\n"  , count_cycle); 
decoder_trigger <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3129\n"  , count_cycle); 
decoder_pseudo_trigger <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3131\n"  , count_cycle); 
end 
end 
end 
 
cpu_state_ldmem: begin 
latched_store <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3138\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:3141\n"  , count_cycle); 
if (!mem_do_prefetch || mem_done) begin 
$fwrite(f,"%0d cycle :picorv32.v:3143\n"  , count_cycle); 
if (!mem_do_rdata) begin 

(* parallel_case, full_case *) 

case (1'b1) 
instr_lb || instr_lbu: begin 
mem_wordsize <= 2; 
$fwrite(f,"%0d cycle :picorv32.v:3149\n"  , count_cycle); 
end 
instr_lh || instr_lhu: begin 
mem_wordsize <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3153\n"  , count_cycle); 
end 
instr_lw: begin 
mem_wordsize <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3157\n"  , count_cycle); 
end 
endcase 
latched_is_lu <= is_lbu_lhu_lw; 
$fwrite(f,"%0d cycle :picorv32.v:3161\n"  , count_cycle); 
latched_is_lh <= instr_lh; 
$fwrite(f,"%0d cycle :picorv32.v:3163\n"  , count_cycle); 
latched_is_lb <= instr_lb; 
$fwrite(f,"%0d cycle :picorv32.v:3165\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:3168\n"  , count_cycle); 
if (ENABLE_TRACE) begin 
trace_valid <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3169\n"  , count_cycle); 
trace_data <= (irq_active ? TRACE_IRQ : 0) | TRACE_ADDR | ((reg_op1 + decoded_imm) & 32'hffffffff); 
$fwrite(f,"%0d cycle :picorv32.v:3171\n"  , count_cycle); 
end 
reg_op1 <= reg_op1 + decoded_imm; 
$fwrite(f,"%0d cycle :picorv32.v:3174\n"  , count_cycle); 
set_mem_do_rdata = 1; 
$fwrite(f,"%0d cycle :picorv32.v:3176\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:3180\n"  , count_cycle); 
if (!mem_do_prefetch && mem_done) begin 

(* parallel_case, full_case *) 

case (1'b1) 
latched_is_lu: begin 
reg_out <= mem_rdata_word; 
$fwrite(f,"%0d cycle :picorv32.v:3186\n"  , count_cycle); 
end 
latched_is_lh: reg_out <= $signed(mem_rdata_word[15:0]); 
// $fwrite(f,"%0d cycle :picorv32.v:3189\n"  , count_cycle); 
latched_is_lb: reg_out <= $signed(mem_rdata_word[7:0]); 
// $fwrite(f,"%0d cycle :picorv32.v:3191\n"  , count_cycle); 
endcase 
decoder_trigger <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3194\n"  , count_cycle); 
decoder_pseudo_trigger <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3196\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :picorv32.v:3198\n"  , count_cycle); 
end 
end 
end 
endcase 
 
$fwrite(f,"%0d cycle :picorv32.v:3206\n"  , count_cycle); 
if (CATCH_MISALIGN && resetn && (mem_do_rdata || mem_do_wdata)) begin 
$fwrite(f,"%0d cycle :picorv32.v:3207\n"  , count_cycle); 
if (mem_wordsize == 0 && reg_op1[1:0] != 0) begin 
`debug($display("MISALIGNED WORD: 0x%08x", reg_op1);) 
$fwrite(f,"%0d cycle :picorv32.v:3211\n"  , count_cycle); 
if (ENABLE_IRQ && !irq_mask[irq_buserror] && !irq_active) begin 
next_irq_pending[irq_buserror] = 1; 
$fwrite(f,"%0d cycle :picorv32.v:3212\n"  , count_cycle); 
end else 
cpu_state <= cpu_state_trap; 
$fwrite(f,"%0d cycle :picorv32.v:3215\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:3218\n"  , count_cycle); 
if (mem_wordsize == 1 && reg_op1[0] != 0) begin 
`debug($display("MISALIGNED HALFWORD: 0x%08x", reg_op1);) 
$fwrite(f,"%0d cycle :picorv32.v:3222\n"  , count_cycle); 
if (ENABLE_IRQ && !irq_mask[irq_buserror] && !irq_active) begin 
next_irq_pending[irq_buserror] = 1; 
$fwrite(f,"%0d cycle :picorv32.v:3223\n"  , count_cycle); 
end else 
cpu_state <= cpu_state_trap; 
$fwrite(f,"%0d cycle :picorv32.v:3226\n"  , count_cycle); 
end 
end 
$fwrite(f,"%0d cycle :picorv32.v:3231\n"  , count_cycle); 
if (CATCH_MISALIGN && resetn && mem_do_rinst && (COMPRESSED_ISA ? reg_pc[0] : |reg_pc[1:0])) begin 
`debug($display("MISALIGNED INSTRUCTION: 0x%08x", reg_pc);) 
$fwrite(f,"%0d cycle :picorv32.v:3234\n"  , count_cycle); 
if (ENABLE_IRQ && !irq_mask[irq_buserror] && !irq_active) begin 
next_irq_pending[irq_buserror] = 1; 
$fwrite(f,"%0d cycle :picorv32.v:3235\n"  , count_cycle); 
end else 
cpu_state <= cpu_state_trap; 
$fwrite(f,"%0d cycle :picorv32.v:3238\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:3242\n"  , count_cycle); 
if (!CATCH_ILLINSN && decoder_trigger_q && !decoder_pseudo_trigger_q && instr_ecall_ebreak) begin 
cpu_state <= cpu_state_trap; 
$fwrite(f,"%0d cycle :picorv32.v:3243\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :picorv32.v:3248\n"  , count_cycle); 
if (!resetn || mem_done) begin 
mem_do_prefetch <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3249\n"  , count_cycle); 
mem_do_rinst <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3251\n"  , count_cycle); 
mem_do_rdata <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3253\n"  , count_cycle); 
mem_do_wdata <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3255\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :picorv32.v:3260\n"  , count_cycle); 
if (set_mem_do_rinst) begin 
mem_do_rinst <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3261\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:3265\n"  , count_cycle); 
if (set_mem_do_rdata) begin 
mem_do_rdata <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3266\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:3270\n"  , count_cycle); 
if (set_mem_do_wdata) begin 
mem_do_wdata <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3271\n"  , count_cycle); 
end 
 
irq_pending <= next_irq_pending & ~MASKED_IRQ; 
$fwrite(f,"%0d cycle :picorv32.v:3275\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :picorv32.v:3279\n"  , count_cycle); 
if (!CATCH_MISALIGN) begin 
$fwrite(f,"%0d cycle :picorv32.v:3281\n"  , count_cycle); 
if (COMPRESSED_ISA) begin 
reg_pc[0] <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3282\n"  , count_cycle); 
reg_next_pc[0] <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3284\n"  , count_cycle); 
end else begin 
reg_pc[1:0] <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3287\n"  , count_cycle); 
reg_next_pc[1:0] <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3289\n"  , count_cycle); 
end 
end 
current_pc = 'bx; 
$fwrite(f,"%0d cycle :picorv32.v:3293\n"  , count_cycle); 
end 
 
`ifdef RISCV_FORMAL 
reg dbg_irq_call; 
reg dbg_irq_enter; 
reg [31:0] dbg_irq_ret; 
always @(posedge clk) begin 
rvfi_valid <= resetn && (launch_next_insn || trap) && dbg_valid_insn; 
$fwrite(f,"%0d cycle :picorv32.v:3302\n"  , count_cycle); 
rvfi_order <= resetn ? rvfi_order + rvfi_valid : 0; 
$fwrite(f,"%0d cycle :picorv32.v:3304\n"  , count_cycle); 
 
rvfi_insn <= dbg_insn_opcode; 
$fwrite(f,"%0d cycle :picorv32.v:3307\n"  , count_cycle); 
rvfi_rs1_addr <= dbg_rs1val_valid ? dbg_insn_rs1 : 0; 
$fwrite(f,"%0d cycle :picorv32.v:3309\n"  , count_cycle); 
rvfi_rs2_addr <= dbg_rs2val_valid ? dbg_insn_rs2 : 0; 
$fwrite(f,"%0d cycle :picorv32.v:3311\n"  , count_cycle); 
rvfi_pc_rdata <= dbg_insn_addr; 
$fwrite(f,"%0d cycle :picorv32.v:3313\n"  , count_cycle); 
rvfi_rs1_rdata <= dbg_rs1val_valid ? dbg_rs1val : 0; 
$fwrite(f,"%0d cycle :picorv32.v:3315\n"  , count_cycle); 
rvfi_rs2_rdata <= dbg_rs2val_valid ? dbg_rs2val : 0; 
$fwrite(f,"%0d cycle :picorv32.v:3317\n"  , count_cycle); 
rvfi_trap <= trap; 
$fwrite(f,"%0d cycle :picorv32.v:3319\n"  , count_cycle); 
rvfi_halt <= trap; 
$fwrite(f,"%0d cycle :picorv32.v:3321\n"  , count_cycle); 
rvfi_intr <= dbg_irq_enter; 
$fwrite(f,"%0d cycle :picorv32.v:3323\n"  , count_cycle); 
rvfi_mode <= 3; 
$fwrite(f,"%0d cycle :picorv32.v:3325\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :picorv32.v:3329\n"  , count_cycle); 
if (!resetn) begin 
dbg_irq_call <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3330\n"  , count_cycle); 
dbg_irq_enter <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3332\n"  , count_cycle); 
end else 
$fwrite(f,"%0d cycle :picorv32.v:3336\n"  , count_cycle); 
if (rvfi_valid) begin 
dbg_irq_call <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3337\n"  , count_cycle); 
dbg_irq_enter <= dbg_irq_call; 
$fwrite(f,"%0d cycle :picorv32.v:3339\n"  , count_cycle); 
end else 
$fwrite(f,"%0d cycle :picorv32.v:3342\n"  , count_cycle); 
if (irq_state == 1) begin 
dbg_irq_call <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3344\n"  , count_cycle); 
dbg_irq_ret <= next_pc; 
$fwrite(f,"%0d cycle :picorv32.v:3346\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :picorv32.v:3351\n"  , count_cycle); 
if (!resetn) begin 
rvfi_rd_addr <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3352\n"  , count_cycle); 
rvfi_rd_wdata <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3354\n"  , count_cycle); 
end else 
$fwrite(f,"%0d cycle :picorv32.v:3358\n"  , count_cycle); 
if (cpuregs_write && !irq_state) begin 
rvfi_rd_addr <= latched_rd; 
$fwrite(f,"%0d cycle :picorv32.v:3359\n"  , count_cycle); 
rvfi_rd_wdata <= latched_rd ? cpuregs_wrdata : 0; 
$fwrite(f,"%0d cycle :picorv32.v:3361\n"  , count_cycle); 
end else 
$fwrite(f,"%0d cycle :picorv32.v:3365\n"  , count_cycle); 
if (rvfi_valid) begin 
rvfi_rd_addr <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3366\n"  , count_cycle); 
rvfi_rd_wdata <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3368\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :picorv32.v:3373\n"  , count_cycle); 
casez (dbg_insn_opcode) 
32'b 0000000_?????_000??_???_?????_0001011: begin // getq 
rvfi_rs1_addr <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3375\n"  , count_cycle); 
rvfi_rs1_rdata <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3377\n"  , count_cycle); 
end 
32'b 0000001_?????_?????_???_000??_0001011: begin // setq 
rvfi_rd_addr <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3381\n"  , count_cycle); 
rvfi_rd_wdata <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3383\n"  , count_cycle); 
end 
32'b 0000010_?????_00000_???_00000_0001011: begin // retirq 
rvfi_rs1_addr <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3387\n"  , count_cycle); 
rvfi_rs1_rdata <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3389\n"  , count_cycle); 
end 
endcase 
 
$fwrite(f,"%0d cycle :picorv32.v:3395\n"  , count_cycle); 
if (!dbg_irq_call) begin 
$fwrite(f,"%0d cycle :picorv32.v:3397\n"  , count_cycle); 
if (dbg_mem_instr) begin 
rvfi_mem_addr <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3398\n"  , count_cycle); 
rvfi_mem_rmask <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3400\n"  , count_cycle); 
rvfi_mem_wmask <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3402\n"  , count_cycle); 
rvfi_mem_rdata <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3404\n"  , count_cycle); 
rvfi_mem_wdata <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3406\n"  , count_cycle); 
end else 
$fwrite(f,"%0d cycle :picorv32.v:3410\n"  , count_cycle); 
if (dbg_mem_valid && dbg_mem_ready) begin 
rvfi_mem_addr <= dbg_mem_addr; 
$fwrite(f,"%0d cycle :picorv32.v:3411\n"  , count_cycle); 
rvfi_mem_rmask <= dbg_mem_wstrb ? 0 : ~0; 
$fwrite(f,"%0d cycle :picorv32.v:3413\n"  , count_cycle); 
rvfi_mem_wmask <= dbg_mem_wstrb; 
$fwrite(f,"%0d cycle :picorv32.v:3415\n"  , count_cycle); 
rvfi_mem_rdata <= dbg_mem_rdata; 
$fwrite(f,"%0d cycle :picorv32.v:3417\n"  , count_cycle); 
rvfi_mem_wdata <= dbg_mem_wdata; 
$fwrite(f,"%0d cycle :picorv32.v:3419\n"  , count_cycle); 
end 
end 
end 
 
always @* begin 
rvfi_pc_wdata = dbg_irq_call ? dbg_irq_ret : dbg_insn_addr; 
$fwrite(f,"%0d cycle :picorv32.v:3426\n"  , count_cycle); 
end 
`endif 
 
// Formal Verification 
`ifdef FORMAL 
reg [3:0] last_mem_nowait; 
always @(posedge clk) begin 
last_mem_nowait <= {last_mem_nowait, mem_ready || !mem_valid}; 
$fwrite(f,"%0d cycle :picorv32.v:3435\n"  , count_cycle); 
end 
 
// stall the memory interface for max 4 cycles 
restrict property (|last_mem_nowait || mem_ready || !mem_valid); 
 
// resetn low in first cycle, after that resetn high 
restrict property (resetn != $initstate); 
$fwrite(f,"%0d cycle :picorv32.v:3443\n"  , count_cycle); 
 
// this just makes it much easier to read traces. uncomment as needed. 
// assume property (mem_valid || !mem_ready); 
 
reg ok; 
always @* begin 
$fwrite(f,"%0d cycle :picorv32.v:3452\n"  , count_cycle); 
if (resetn) begin 
// instruction fetches are read-only 
$fwrite(f,"%0d cycle :picorv32.v:3455\n"  , count_cycle); 
if (mem_valid && mem_instr) begin 
assert (mem_wstrb == 0); 
$fwrite(f,"%0d cycle :picorv32.v:3456\n"  , count_cycle); 
end 
 
// cpu_state must be valid 
ok = 0; 
$fwrite(f,"%0d cycle :picorv32.v:3461\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:3463\n"  , count_cycle); 
if (cpu_state == cpu_state_trap) begin 
ok = 1; 
$fwrite(f,"%0d cycle :picorv32.v:3465\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:3468\n"  , count_cycle); 
if (cpu_state == cpu_state_fetch) begin 
ok = 1; 
$fwrite(f,"%0d cycle :picorv32.v:3470\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:3473\n"  , count_cycle); 
if (cpu_state == cpu_state_ld_rs1) begin 
ok = 1; 
$fwrite(f,"%0d cycle :picorv32.v:3475\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:3478\n"  , count_cycle); 
if (cpu_state == cpu_state_ld_rs2) begin 
ok = !ENABLE_REGS_DUALPORT; 
$fwrite(f,"%0d cycle :picorv32.v:3480\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:3483\n"  , count_cycle); 
if (cpu_state == cpu_state_exec) begin 
ok = 1; 
$fwrite(f,"%0d cycle :picorv32.v:3485\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:3488\n"  , count_cycle); 
if (cpu_state == cpu_state_shift) begin 
ok = 1; 
$fwrite(f,"%0d cycle :picorv32.v:3490\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:3493\n"  , count_cycle); 
if (cpu_state == cpu_state_stmem) begin 
ok = 1; 
$fwrite(f,"%0d cycle :picorv32.v:3495\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:3498\n"  , count_cycle); 
if (cpu_state == cpu_state_ldmem) begin 
ok = 1; 
$fwrite(f,"%0d cycle :picorv32.v:3500\n"  , count_cycle); 
end 
assert (ok); 
end 
end 
 
reg last_mem_la_read = 0; 
$fwrite(f,"%0d cycle :picorv32.v:3507\n"  , count_cycle); 
reg last_mem_la_write = 0; 
$fwrite(f,"%0d cycle :picorv32.v:3509\n"  , count_cycle); 
reg [31:0] last_mem_la_addr; 
reg [31:0] last_mem_la_wdata; 
reg [3:0] last_mem_la_wstrb = 0; 
$fwrite(f,"%0d cycle :picorv32.v:3513\n"  , count_cycle); 
 
always @(posedge clk) begin 
last_mem_la_read <= mem_la_read; 
$fwrite(f,"%0d cycle :picorv32.v:3517\n"  , count_cycle); 
last_mem_la_write <= mem_la_write; 
$fwrite(f,"%0d cycle :picorv32.v:3519\n"  , count_cycle); 
last_mem_la_addr <= mem_la_addr; 
$fwrite(f,"%0d cycle :picorv32.v:3521\n"  , count_cycle); 
last_mem_la_wdata <= mem_la_wdata; 
$fwrite(f,"%0d cycle :picorv32.v:3523\n"  , count_cycle); 
last_mem_la_wstrb <= mem_la_wstrb; 
$fwrite(f,"%0d cycle :picorv32.v:3525\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :picorv32.v:3529\n"  , count_cycle); 
if (last_mem_la_read) begin 
assert(mem_valid); 
assert(mem_addr == last_mem_la_addr); 
$fwrite(f,"%0d cycle :picorv32.v:3531\n"  , count_cycle); 
assert(mem_wstrb == 0); 
$fwrite(f,"%0d cycle :picorv32.v:3533\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:3537\n"  , count_cycle); 
if (last_mem_la_write) begin 
assert(mem_valid); 
assert(mem_addr == last_mem_la_addr); 
$fwrite(f,"%0d cycle :picorv32.v:3539\n"  , count_cycle); 
assert(mem_wdata == last_mem_la_wdata); 
$fwrite(f,"%0d cycle :picorv32.v:3541\n"  , count_cycle); 
assert(mem_wstrb == last_mem_la_wstrb); 
$fwrite(f,"%0d cycle :picorv32.v:3543\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:3547\n"  , count_cycle); 
if (mem_la_read || mem_la_write) begin 
assert(!mem_valid || mem_ready); 
end 
end 
`endif 
endmodule 
 
// This is a simple example implementation of PICORV32_REGS. 
// Use the PICORV32_REGS mechanism if you want to use custom 
// memory resources to implement the processor register file. 
// Note that your implementation must match the requirements of 
// the PicoRV32 configuration. (e.g. QREGS, etc) 
module picorv32_regs ( 
input clk, wen, 
input [5:0] waddr, 
input [5:0] raddr1, 
input [5:0] raddr2, 
input [31:0] wdata, 
output [31:0] rdata1, 
output [31:0] rdata2 
); 
reg [31:0] regs [0:30]; 
 
always @(posedge clk) begin 
$fwrite(f,"%0d cycle :picorv32.v:3571\n"  , count_cycle); 
if (wen) regs[~waddr[4:0]] <= wdata; 
end 
 
assign rdata1 = regs[~raddr1[4:0]]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:3575\n"  , count_cycle); 
end 
assign rdata2 = regs[~raddr2[4:0]]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:3579\n"  , count_cycle); 
end 
endmodule 
 
 
/*************************************************************** 
* picorv32_pcpi_mul 
***************************************************************/ 
 
module picorv32_pcpi_mul #( 
parameter STEPS_AT_ONCE = 1, 
parameter CARRY_CHAIN = 4 
) ( 
input clk, resetn, 
 
input             pcpi_valid, 
input      [31:0] pcpi_insn, 
input      [31:0] pcpi_rs1, 
input      [31:0] pcpi_rs2, 
output reg        pcpi_wr, 
output reg [31:0] pcpi_rd, 
output reg        pcpi_wait, 
output reg        pcpi_ready 
); 
reg instr_mul, instr_mulh, instr_mulhsu, instr_mulhu; 
wire instr_any_mul = |{instr_mul, instr_mulh, instr_mulhsu, instr_mulhu}; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:3606\n"  , count_cycle); 
end 
wire instr_any_mulh = |{instr_mulh, instr_mulhsu, instr_mulhu}; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:3610\n"  , count_cycle); 
end 
wire instr_rs1_signed = |{instr_mulh, instr_mulhsu}; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:3614\n"  , count_cycle); 
end 
wire instr_rs2_signed = |{instr_mulh}; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:3618\n"  , count_cycle); 
end 
 
reg pcpi_wait_q; 
wire mul_start = pcpi_wait && !pcpi_wait_q; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:3624\n"  , count_cycle); 
end 
 
always @(posedge clk) begin 
instr_mul <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3630\n"  , count_cycle); 
instr_mulh <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3632\n"  , count_cycle); 
instr_mulhsu <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3634\n"  , count_cycle); 
instr_mulhu <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3636\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :picorv32.v:3639\n"  , count_cycle); 
if (resetn && pcpi_valid && pcpi_insn[6:0] == 7'b0110011 && pcpi_insn[31:25] == 7'b0000001) begin 
$fwrite(f,"%0d cycle :picorv32.v:3642\n"  , count_cycle); 
case (pcpi_insn[14:12]) 
3'b000: begin 
instr_mul <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3644\n"  , count_cycle); 
end 
3'b001: begin 
instr_mulh <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3648\n"  , count_cycle); 
end 
3'b010: begin 
instr_mulhsu <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3652\n"  , count_cycle); 
end 
3'b011: begin 
instr_mulhu <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3656\n"  , count_cycle); 
end 
endcase 
end 
 
pcpi_wait <= instr_any_mul; 
$fwrite(f,"%0d cycle :picorv32.v:3662\n"  , count_cycle); 
pcpi_wait_q <= pcpi_wait; 
$fwrite(f,"%0d cycle :picorv32.v:3664\n"  , count_cycle); 
end 
 
reg [63:0] rs1, rs2, rd, rdx; 
reg [63:0] next_rs1, next_rs2, this_rs2; 
reg [63:0] next_rd, next_rdx, next_rdt; 
reg [6:0] mul_counter; 
reg mul_waiting; 
reg mul_finish; 
integer i, j; 
 
// carry save accumulator 
always @* begin 
next_rd = rd; 
$fwrite(f,"%0d cycle :picorv32.v:3678\n"  , count_cycle); 
next_rdx = rdx; 
$fwrite(f,"%0d cycle :picorv32.v:3680\n"  , count_cycle); 
next_rs1 = rs1; 
$fwrite(f,"%0d cycle :picorv32.v:3682\n"  , count_cycle); 
next_rs2 = rs2; 
$fwrite(f,"%0d cycle :picorv32.v:3684\n"  , count_cycle); 
 
for (i = 0; i < STEPS_AT_ONCE; i=i+1) begin 
this_rs2 = next_rs1[0] ? next_rs2 : 0; 
$fwrite(f,"%0d cycle :picorv32.v:3688\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:3690\n"  , count_cycle); 
if (CARRY_CHAIN == 0) begin 
next_rdt = next_rd ^ next_rdx ^ this_rs2; 
$fwrite(f,"%0d cycle :picorv32.v:3692\n"  , count_cycle); 
next_rdx = ((next_rd & next_rdx) | (next_rd & this_rs2) | (next_rdx & this_rs2)) << 1; 
$fwrite(f,"%0d cycle :picorv32.v:3694\n"  , count_cycle); 
next_rd = next_rdt; 
$fwrite(f,"%0d cycle :picorv32.v:3696\n"  , count_cycle); 
end else begin 
next_rdt = 0; 
$fwrite(f,"%0d cycle :picorv32.v:3699\n"  , count_cycle); 
for (j = 0; j < 64; j = j + CARRY_CHAIN){next_rdt[j+CARRY_CHAIN-1], next_rd[j +: CARRY_CHAIN]} =next_rd[j +: CARRY_CHAIN] + next_rdx[j +: CARRY_CHAIN] + this_rs2[j +: CARRY_CHAIN]; 
next_rdx = next_rdt << 1; 
$fwrite(f,"%0d cycle :picorv32.v:3702\n"  , count_cycle); 
end 
next_rs1 = next_rs1 >> 1; 
$fwrite(f,"%0d cycle :picorv32.v:3705\n"  , count_cycle); 
next_rs2 = next_rs2 << 1; 
$fwrite(f,"%0d cycle :picorv32.v:3707\n"  , count_cycle); 
end 
end 
 
always @(posedge clk) begin 
mul_finish <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3713\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:3716\n"  , count_cycle); 
if (!resetn) begin 
mul_waiting <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3717\n"  , count_cycle); 
end else 
$fwrite(f,"%0d cycle :picorv32.v:3721\n"  , count_cycle); 
if (mul_waiting) begin 
$fwrite(f,"%0d cycle :picorv32.v:3723\n"  , count_cycle); 
if (instr_rs1_signed) begin 
rs1 <= $signed(pcpi_rs1); 
$fwrite(f,"%0d cycle :picorv32.v:3724\n"  , count_cycle); 
end 
else 
rs1 <= $unsigned(pcpi_rs1); 
$fwrite(f,"%0d cycle :picorv32.v:3728\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :picorv32.v:3732\n"  , count_cycle); 
if (instr_rs2_signed) begin 
rs2 <= $signed(pcpi_rs2); 
$fwrite(f,"%0d cycle :picorv32.v:3733\n"  , count_cycle); 
end 
else 
rs2 <= $unsigned(pcpi_rs2); 
$fwrite(f,"%0d cycle :picorv32.v:3737\n"  , count_cycle); 
 
rd <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3740\n"  , count_cycle); 
rdx <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3742\n"  , count_cycle); 
mul_counter <= (instr_any_mulh ? 63 - STEPS_AT_ONCE : 31 - STEPS_AT_ONCE); 
$fwrite(f,"%0d cycle :picorv32.v:3744\n"  , count_cycle); 
mul_waiting <= !mul_start; 
$fwrite(f,"%0d cycle :picorv32.v:3746\n"  , count_cycle); 
end else begin 
rd <= next_rd; 
$fwrite(f,"%0d cycle :picorv32.v:3749\n"  , count_cycle); 
rdx <= next_rdx; 
$fwrite(f,"%0d cycle :picorv32.v:3751\n"  , count_cycle); 
rs1 <= next_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:3753\n"  , count_cycle); 
rs2 <= next_rs2; 
$fwrite(f,"%0d cycle :picorv32.v:3755\n"  , count_cycle); 
 
mul_counter <= mul_counter - STEPS_AT_ONCE; 
$fwrite(f,"%0d cycle :picorv32.v:3758\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:3761\n"  , count_cycle); 
if (mul_counter[6]) begin 
mul_finish <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3762\n"  , count_cycle); 
mul_waiting <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3764\n"  , count_cycle); 
end 
end 
end 
 
always @(posedge clk) begin 
pcpi_wr <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3771\n"  , count_cycle); 
pcpi_ready <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3773\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:3776\n"  , count_cycle); 
if (mul_finish && resetn) begin 
pcpi_wr <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3777\n"  , count_cycle); 
pcpi_ready <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3779\n"  , count_cycle); 
pcpi_rd <= instr_any_mulh ? rd >> 32 : rd; 
$fwrite(f,"%0d cycle :picorv32.v:3781\n"  , count_cycle); 
end 
end 
endmodule 
 
module picorv32_pcpi_fast_mul #( 
parameter EXTRA_MUL_FFS = 0, 
parameter EXTRA_INSN_FFS = 0, 
parameter MUL_CLKGATE = 0 
) ( 
input clk, resetn, 
 
input             pcpi_valid, 
input      [31:0] pcpi_insn, 
input      [31:0] pcpi_rs1, 
input      [31:0] pcpi_rs2, 
output            pcpi_wr, 
output     [31:0] pcpi_rd, 
output            pcpi_wait, 
output            pcpi_ready 
); 
reg instr_mul, instr_mulh, instr_mulhsu, instr_mulhu; 
wire instr_any_mul = |{instr_mul, instr_mulh, instr_mulhsu, instr_mulhu}; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:3804\n"  , count_cycle); 
end 
wire instr_any_mulh = |{instr_mulh, instr_mulhsu, instr_mulhu}; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:3808\n"  , count_cycle); 
end 
wire instr_rs1_signed = |{instr_mulh, instr_mulhsu}; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:3812\n"  , count_cycle); 
end 
wire instr_rs2_signed = |{instr_mulh}; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:3816\n"  , count_cycle); 
end 
 
reg shift_out; 
reg [3:0] active; 
reg [32:0] rs1, rs2, rs1_q, rs2_q; 
reg [63:0] rd, rd_q; 
 
wire pcpi_insn_valid = pcpi_valid && pcpi_insn[6:0] == 7'b0110011 && pcpi_insn[31:25] == 7'b0000001; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:3826\n"  , count_cycle); 
end 
reg pcpi_insn_valid_q; 
 
always @* begin 
instr_mul = 0; 
$fwrite(f,"%0d cycle :picorv32.v:3833\n"  , count_cycle); 
instr_mulh = 0; 
$fwrite(f,"%0d cycle :picorv32.v:3835\n"  , count_cycle); 
instr_mulhsu = 0; 
$fwrite(f,"%0d cycle :picorv32.v:3837\n"  , count_cycle); 
instr_mulhu = 0; 
$fwrite(f,"%0d cycle :picorv32.v:3839\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :picorv32.v:3843\n"  , count_cycle); 
if (resetn && (EXTRA_INSN_FFS ? pcpi_insn_valid_q : pcpi_insn_valid)) begin 
$fwrite(f,"%0d cycle :picorv32.v:3845\n"  , count_cycle); 
case (pcpi_insn[14:12]) 
3'b000: begin 
instr_mul = 1; 
$fwrite(f,"%0d cycle :picorv32.v:3847\n"  , count_cycle); 
end 
3'b001: begin 
instr_mulh = 1; 
$fwrite(f,"%0d cycle :picorv32.v:3851\n"  , count_cycle); 
end 
3'b010: begin 
instr_mulhsu = 1; 
$fwrite(f,"%0d cycle :picorv32.v:3855\n"  , count_cycle); 
end 
3'b011: begin 
instr_mulhu = 1; 
$fwrite(f,"%0d cycle :picorv32.v:3859\n"  , count_cycle); 
end 
endcase 
end 
end 
 
always @(posedge clk) begin 
pcpi_insn_valid_q <= pcpi_insn_valid; 
$fwrite(f,"%0d cycle :picorv32.v:3867\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:3870\n"  , count_cycle); 
if (!MUL_CLKGATE || active[0]) begin 
rs1_q <= rs1; 
$fwrite(f,"%0d cycle :picorv32.v:3871\n"  , count_cycle); 
rs2_q <= rs2; 
$fwrite(f,"%0d cycle :picorv32.v:3873\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:3877\n"  , count_cycle); 
if (!MUL_CLKGATE || active[1]) begin 
rd <= $signed(EXTRA_MUL_FFS ? rs1_q : rs1) * $signed(EXTRA_MUL_FFS ? rs2_q : rs2); 
$fwrite(f,"%0d cycle :picorv32.v:3878\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:3882\n"  , count_cycle); 
if (!MUL_CLKGATE || active[2]) begin 
rd_q <= rd; 
$fwrite(f,"%0d cycle :picorv32.v:3883\n"  , count_cycle); 
end 
end 
 
always @(posedge clk) begin 
$fwrite(f,"%0d cycle :picorv32.v:3890\n"  , count_cycle); 
if (instr_any_mul && !(EXTRA_MUL_FFS ? active[3:0] : active[1:0])) begin 
$fwrite(f,"%0d cycle :picorv32.v:3892\n"  , count_cycle); 
if (instr_rs1_signed) begin 
rs1 <= $signed(pcpi_rs1); 
$fwrite(f,"%0d cycle :picorv32.v:3893\n"  , count_cycle); 
end 
else 
rs1 <= $unsigned(pcpi_rs1); 
$fwrite(f,"%0d cycle :picorv32.v:3897\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :picorv32.v:3901\n"  , count_cycle); 
if (instr_rs2_signed) begin 
rs2 <= $signed(pcpi_rs2); 
$fwrite(f,"%0d cycle :picorv32.v:3902\n"  , count_cycle); 
end 
else 
rs2 <= $unsigned(pcpi_rs2); 
$fwrite(f,"%0d cycle :picorv32.v:3906\n"  , count_cycle); 
active[0] <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3908\n"  , count_cycle); 
end else begin 
active[0] <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3911\n"  , count_cycle); 
end 
 
active[3:1] <= active; 
$fwrite(f,"%0d cycle :picorv32.v:3915\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:3917\n"  , count_cycle); 
shift_out <= instr_any_mulh; 
 
$fwrite(f,"%0d cycle :picorv32.v:3921\n"  , count_cycle); 
if (!resetn) begin 
active <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3922\n"  , count_cycle); 
end 
end 
 
assign pcpi_wr = active[EXTRA_MUL_FFS ? 3 : 1]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:3927\n"  , count_cycle); 
end 
assign pcpi_wait = 0; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:3931\n"  , count_cycle); 
end 
assign pcpi_ready = active[EXTRA_MUL_FFS ? 3 : 1]; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:3935\n"  , count_cycle); 
end 
`ifdef RISCV_FORMAL_ALTOPS 
assign pcpi_rd =instr_mul    ? (pcpi_rs1 + pcpi_rs2) ^ 32'h5876063e :instr_mulh   ? (pcpi_rs1 + pcpi_rs2) ^ 32'hf6583fb7 :instr_mulhsu ? (pcpi_rs1 - pcpi_rs2) ^ 32'hecfbe137 :instr_mulhu  ? (pcpi_rs1 + pcpi_rs2) ^ 32'h949ce5e8 : 1'bx; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:3940\n"  , count_cycle); 
end 
`else 
$fwrite(f,"%0d cycle :picorv32.v:3946\n"  , count_cycle); 
assign pcpi_rd = shift_out ? (EXTRA_MUL_FFS ? rd_q : rd) >> 32 : (EXTRA_MUL_FFS ? rd_q : rd); 
`endif 
endmodule 
 
 
/*************************************************************** 
* picorv32_pcpi_div 
***************************************************************/ 
 
module picorv32_pcpi_div ( 
input clk, resetn, 
 
input             pcpi_valid, 
input      [31:0] pcpi_insn, 
input      [31:0] pcpi_rs1, 
input      [31:0] pcpi_rs2, 
output reg        pcpi_wr, 
output reg [31:0] pcpi_rd, 
output reg        pcpi_wait, 
output reg        pcpi_ready 
); 
reg instr_div, instr_divu, instr_rem, instr_remu; 
wire instr_any_div_rem = |{instr_div, instr_divu, instr_rem, instr_remu}; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:3968\n"  , count_cycle); 
end 
 
reg pcpi_wait_q; 
wire start = pcpi_wait && !pcpi_wait_q; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:3974\n"  , count_cycle); 
end 
 
always @(posedge clk) begin 
instr_div <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3980\n"  , count_cycle); 
instr_divu <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3982\n"  , count_cycle); 
instr_rem <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3984\n"  , count_cycle); 
instr_remu <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:3986\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :picorv32.v:3989\n"  , count_cycle); 
if (resetn && pcpi_valid && !pcpi_ready && pcpi_insn[6:0] == 7'b0110011 && pcpi_insn[31:25] == 7'b0000001) begin 
$fwrite(f,"%0d cycle :picorv32.v:3992\n"  , count_cycle); 
case (pcpi_insn[14:12]) 
3'b100: begin 
instr_div <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3994\n"  , count_cycle); 
end 
3'b101: begin 
instr_divu <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:3998\n"  , count_cycle); 
end 
3'b110: begin 
instr_rem <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:4002\n"  , count_cycle); 
end 
3'b111: begin 
instr_remu <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:4006\n"  , count_cycle); 
end 
endcase 
end 
 
pcpi_wait <= instr_any_div_rem && resetn; 
$fwrite(f,"%0d cycle :picorv32.v:4012\n"  , count_cycle); 
pcpi_wait_q <= pcpi_wait && resetn; 
$fwrite(f,"%0d cycle :picorv32.v:4014\n"  , count_cycle); 
end 
 
reg [31:0] dividend; 
reg [62:0] divisor; 
reg [31:0] quotient; 
reg [31:0] quotient_msk; 
reg running; 
reg outsign; 
 
always @(posedge clk) begin 
pcpi_ready <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:4026\n"  , count_cycle); 
pcpi_wr <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:4028\n"  , count_cycle); 
pcpi_rd <= 'bx; 
$fwrite(f,"%0d cycle :picorv32.v:4030\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :picorv32.v:4034\n"  , count_cycle); 
if (!resetn) begin 
running <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:4035\n"  , count_cycle); 
end else 
$fwrite(f,"%0d cycle :picorv32.v:4039\n"  , count_cycle); 
if (start) begin 
running <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:4040\n"  , count_cycle); 
dividend <= (instr_div || instr_rem) && pcpi_rs1[31] ? -pcpi_rs1 : pcpi_rs1; 
$fwrite(f,"%0d cycle :picorv32.v:4042\n"  , count_cycle); 
divisor <= ((instr_div || instr_rem) && pcpi_rs2[31] ? -pcpi_rs2 : pcpi_rs2) << 31; 
$fwrite(f,"%0d cycle :picorv32.v:4044\n"  , count_cycle); 
outsign <= (instr_div && (pcpi_rs1[31] != pcpi_rs2[31]) && |pcpi_rs2) || (instr_rem && pcpi_rs1[31]); 
$fwrite(f,"%0d cycle :picorv32.v:4046\n"  , count_cycle); 
quotient <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:4048\n"  , count_cycle); 
quotient_msk <= 1 << 31; 
$fwrite(f,"%0d cycle :picorv32.v:4050\n"  , count_cycle); 
end else 
$fwrite(f,"%0d cycle :picorv32.v:4054\n"  , count_cycle); 
if (!quotient_msk && running) begin 
running <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:4055\n"  , count_cycle); 
pcpi_ready <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:4057\n"  , count_cycle); 
pcpi_wr <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:4059\n"  , count_cycle); 
`ifdef RISCV_FORMAL_ALTOPS 
$fwrite(f,"%0d cycle :picorv32.v:4063\n"  , count_cycle); 
case (1) 
instr_div: begin 
pcpi_rd <= (pcpi_rs1 - pcpi_rs2) ^ 32'h7f8529ec; 
$fwrite(f,"%0d cycle :picorv32.v:4065\n"  , count_cycle); 
end 
instr_divu: begin 
pcpi_rd <= (pcpi_rs1 - pcpi_rs2) ^ 32'h10e8fd70; 
$fwrite(f,"%0d cycle :picorv32.v:4069\n"  , count_cycle); 
end 
instr_rem: begin 
pcpi_rd <= (pcpi_rs1 - pcpi_rs2) ^ 32'h8da68fa5; 
$fwrite(f,"%0d cycle :picorv32.v:4073\n"  , count_cycle); 
end 
instr_remu: begin 
pcpi_rd <= (pcpi_rs1 - pcpi_rs2) ^ 32'h3138d0e1; 
$fwrite(f,"%0d cycle :picorv32.v:4077\n"  , count_cycle); 
end 
endcase 
`else 
$fwrite(f,"%0d cycle :picorv32.v:4083\n"  , count_cycle); 
if (instr_div || instr_divu) begin 
pcpi_rd <= outsign ? -quotient : quotient; 
$fwrite(f,"%0d cycle :picorv32.v:4084\n"  , count_cycle); 
end 
else 
pcpi_rd <= outsign ? -dividend : dividend; 
$fwrite(f,"%0d cycle :picorv32.v:4088\n"  , count_cycle); 
`endif 
end else begin 
$fwrite(f,"%0d cycle :picorv32.v:4092\n"  , count_cycle); 
if (divisor <= dividend) begin 
dividend <= dividend - divisor; 
$fwrite(f,"%0d cycle :picorv32.v:4094\n"  , count_cycle); 
quotient <= quotient | quotient_msk; 
$fwrite(f,"%0d cycle :picorv32.v:4096\n"  , count_cycle); 
end 
divisor <= divisor >> 1; 
$fwrite(f,"%0d cycle :picorv32.v:4099\n"  , count_cycle); 
`ifdef RISCV_FORMAL_ALTOPS 
quotient_msk <= quotient_msk >> 5; 
$fwrite(f,"%0d cycle :picorv32.v:4102\n"  , count_cycle); 
`else 
quotient_msk <= quotient_msk >> 1; 
$fwrite(f,"%0d cycle :picorv32.v:4105\n"  , count_cycle); 
`endif 
end 
end 
endmodule 
 
 
/*************************************************************** 
* picorv32_axi 
***************************************************************/ 
 
module picorv32_axi #( 
parameter [ 0:0] ENABLE_COUNTERS = 1, 
parameter [ 0:0] ENABLE_COUNTERS64 = 1, 
parameter [ 0:0] ENABLE_REGS_16_31 = 1, 
parameter [ 0:0] ENABLE_REGS_DUALPORT = 1, 
parameter [ 0:0] TWO_STAGE_SHIFT = 1, 
parameter [ 0:0] BARREL_SHIFTER = 0, 
parameter [ 0:0] TWO_CYCLE_COMPARE = 0, 
parameter [ 0:0] TWO_CYCLE_ALU = 0, 
parameter [ 0:0] COMPRESSED_ISA = 0, 
parameter [ 0:0] CATCH_MISALIGN = 1, 
parameter [ 0:0] CATCH_ILLINSN = 1, 
parameter [ 0:0] ENABLE_PCPI = 0, 
parameter [ 0:0] ENABLE_MUL = 0, 
parameter [ 0:0] ENABLE_FAST_MUL = 0, 
parameter [ 0:0] ENABLE_DIV = 0, 
parameter [ 0:0] ENABLE_IRQ = 0, 
parameter [ 0:0] ENABLE_IRQ_QREGS = 1, 
parameter [ 0:0] ENABLE_IRQ_TIMER = 1, 
parameter [ 0:0] ENABLE_TRACE = 0, 
parameter [ 0:0] REGS_INIT_ZERO = 0, 
parameter [31:0] MASKED_IRQ = 32'h 0000_0000, 
parameter [31:0] LATCHED_IRQ = 32'h ffff_ffff, 
parameter [31:0] PROGADDR_RESET = 32'h 0000_0000, 
parameter [31:0] PROGADDR_IRQ = 32'h 0000_0010, 
parameter [31:0] STACKADDR = 32'h ffff_ffff 
) ( 
input clk, resetn, 
output trap, 
 
// AXI4-lite master memory interface 
 
output        mem_axi_awvalid, 
input         mem_axi_awready, 
output [31:0] mem_axi_awaddr, 
output [ 2:0] mem_axi_awprot, 
 
output        mem_axi_wvalid, 
input         mem_axi_wready, 
output [31:0] mem_axi_wdata, 
output [ 3:0] mem_axi_wstrb, 
 
input         mem_axi_bvalid, 
output        mem_axi_bready, 
 
output        mem_axi_arvalid, 
input         mem_axi_arready, 
output [31:0] mem_axi_araddr, 
output [ 2:0] mem_axi_arprot, 
 
input         mem_axi_rvalid, 
output        mem_axi_rready, 
input  [31:0] mem_axi_rdata, 
 
// Pico Co-Processor Interface (PCPI) 
output        pcpi_valid, 
output [31:0] pcpi_insn, 
output [31:0] pcpi_rs1, 
output [31:0] pcpi_rs2, 
input         pcpi_wr, 
input  [31:0] pcpi_rd, 
input         pcpi_wait, 
input         pcpi_ready, 
 
// IRQ interface 
input  [31:0] irq, 
output [31:0] eoi, 
 
`ifdef RISCV_FORMAL 
output        rvfi_valid, 
output [63:0] rvfi_order, 
output [31:0] rvfi_insn, 
output        rvfi_trap, 
output        rvfi_halt, 
output        rvfi_intr, 
output [ 4:0] rvfi_rs1_addr, 
output [ 4:0] rvfi_rs2_addr, 
output [31:0] rvfi_rs1_rdata, 
output [31:0] rvfi_rs2_rdata, 
output [ 4:0] rvfi_rd_addr, 
output [31:0] rvfi_rd_wdata, 
output [31:0] rvfi_pc_rdata, 
output [31:0] rvfi_pc_wdata, 
output [31:0] rvfi_mem_addr, 
output [ 3:0] rvfi_mem_rmask, 
output [ 3:0] rvfi_mem_wmask, 
output [31:0] rvfi_mem_rdata, 
output [31:0] rvfi_mem_wdata, 
`endif 
 
// Trace Interface 
output        trace_valid, 
output [35:0] trace_data 
); 
wire        mem_valid; 
wire [31:0] mem_addr; 
wire [31:0] mem_wdata; 
wire [ 3:0] mem_wstrb; 
wire        mem_instr; 
wire        mem_ready; 
wire [31:0] mem_rdata; 
 
picorv32_axi_adapter axi_adapter ( 
.clk            (clk            ), 
.resetn         (resetn         ), 
.mem_axi_awvalid(mem_axi_awvalid), 
.mem_axi_awready(mem_axi_awready), 
.mem_axi_awaddr (mem_axi_awaddr ), 
.mem_axi_awprot (mem_axi_awprot ), 
.mem_axi_wvalid (mem_axi_wvalid ), 
.mem_axi_wready (mem_axi_wready ), 
.mem_axi_wdata  (mem_axi_wdata  ), 
.mem_axi_wstrb  (mem_axi_wstrb  ), 
.mem_axi_bvalid (mem_axi_bvalid ), 
.mem_axi_bready (mem_axi_bready ), 
.mem_axi_arvalid(mem_axi_arvalid), 
.mem_axi_arready(mem_axi_arready), 
.mem_axi_araddr (mem_axi_araddr ), 
.mem_axi_arprot (mem_axi_arprot ), 
.mem_axi_rvalid (mem_axi_rvalid ), 
.mem_axi_rready (mem_axi_rready ), 
.mem_axi_rdata  (mem_axi_rdata  ), 
.mem_valid      (mem_valid      ), 
.mem_instr      (mem_instr      ), 
.mem_ready      (mem_ready      ), 
.mem_addr       (mem_addr       ), 
.mem_wdata      (mem_wdata      ), 
.mem_wstrb      (mem_wstrb      ), 
.mem_rdata      (mem_rdata      ) 
); 
 
picorv32 #( 
.ENABLE_COUNTERS     (ENABLE_COUNTERS     ), 
.ENABLE_COUNTERS64   (ENABLE_COUNTERS64   ), 
.ENABLE_REGS_16_31   (ENABLE_REGS_16_31   ), 
.ENABLE_REGS_DUALPORT(ENABLE_REGS_DUALPORT), 
.TWO_STAGE_SHIFT     (TWO_STAGE_SHIFT     ), 
.BARREL_SHIFTER      (BARREL_SHIFTER      ), 
.TWO_CYCLE_COMPARE   (TWO_CYCLE_COMPARE   ), 
.TWO_CYCLE_ALU       (TWO_CYCLE_ALU       ), 
.COMPRESSED_ISA      (COMPRESSED_ISA      ), 
.CATCH_MISALIGN      (CATCH_MISALIGN      ), 
.CATCH_ILLINSN       (CATCH_ILLINSN       ), 
.ENABLE_PCPI         (ENABLE_PCPI         ), 
.ENABLE_MUL          (ENABLE_MUL          ), 
.ENABLE_FAST_MUL     (ENABLE_FAST_MUL     ), 
.ENABLE_DIV          (ENABLE_DIV          ), 
.ENABLE_IRQ          (ENABLE_IRQ          ), 
.ENABLE_IRQ_QREGS    (ENABLE_IRQ_QREGS    ), 
.ENABLE_IRQ_TIMER    (ENABLE_IRQ_TIMER    ), 
.ENABLE_TRACE        (ENABLE_TRACE        ), 
.REGS_INIT_ZERO      (REGS_INIT_ZERO      ), 
.MASKED_IRQ          (MASKED_IRQ          ), 
.LATCHED_IRQ         (LATCHED_IRQ         ), 
.PROGADDR_RESET      (PROGADDR_RESET      ), 
.PROGADDR_IRQ        (PROGADDR_IRQ        ), 
.STACKADDR           (STACKADDR           ) 
) picorv32_core ( 
.clk      (clk   ), 
.resetn   (resetn), 
.trap     (trap  ), 
 
.mem_valid(mem_valid), 
.mem_addr (mem_addr ), 
.mem_wdata(mem_wdata), 
.mem_wstrb(mem_wstrb), 
.mem_instr(mem_instr), 
.mem_ready(mem_ready), 
.mem_rdata(mem_rdata), 
 
.pcpi_valid(pcpi_valid), 
.pcpi_insn (pcpi_insn ), 
.pcpi_rs1  (pcpi_rs1  ), 
.pcpi_rs2  (pcpi_rs2  ), 
.pcpi_wr   (pcpi_wr   ), 
.pcpi_rd   (pcpi_rd   ), 
.pcpi_wait (pcpi_wait ), 
.pcpi_ready(pcpi_ready), 
 
.irq(irq), 
.eoi(eoi), 
 
`ifdef RISCV_FORMAL 
.rvfi_valid    (rvfi_valid    ), 
.rvfi_order    (rvfi_order    ), 
.rvfi_insn     (rvfi_insn     ), 
.rvfi_trap     (rvfi_trap     ), 
.rvfi_halt     (rvfi_halt     ), 
.rvfi_intr     (rvfi_intr     ), 
.rvfi_rs1_addr (rvfi_rs1_addr ), 
.rvfi_rs2_addr (rvfi_rs2_addr ), 
.rvfi_rs1_rdata(rvfi_rs1_rdata), 
.rvfi_rs2_rdata(rvfi_rs2_rdata), 
.rvfi_rd_addr  (rvfi_rd_addr  ), 
.rvfi_rd_wdata (rvfi_rd_wdata ), 
.rvfi_pc_rdata (rvfi_pc_rdata ), 
.rvfi_pc_wdata (rvfi_pc_wdata ), 
.rvfi_mem_addr (rvfi_mem_addr ), 
.rvfi_mem_rmask(rvfi_mem_rmask), 
.rvfi_mem_wmask(rvfi_mem_wmask), 
.rvfi_mem_rdata(rvfi_mem_rdata), 
.rvfi_mem_wdata(rvfi_mem_wdata), 
`endif 
 
.trace_valid(trace_valid), 
.trace_data (trace_data) 
); 
endmodule 
 
 
/*************************************************************** 
* picorv32_axi_adapter 
***************************************************************/ 
 
module picorv32_axi_adapter ( 
input clk, resetn, 
 
// AXI4-lite master memory interface 
 
output        mem_axi_awvalid, 
input         mem_axi_awready, 
output [31:0] mem_axi_awaddr, 
output [ 2:0] mem_axi_awprot, 
 
output        mem_axi_wvalid, 
input         mem_axi_wready, 
output [31:0] mem_axi_wdata, 
output [ 3:0] mem_axi_wstrb, 
 
input         mem_axi_bvalid, 
output        mem_axi_bready, 
 
output        mem_axi_arvalid, 
input         mem_axi_arready, 
output [31:0] mem_axi_araddr, 
output [ 2:0] mem_axi_arprot, 
 
input         mem_axi_rvalid, 
output        mem_axi_rready, 
input  [31:0] mem_axi_rdata, 
 
// Native PicoRV32 memory interface 
 
input         mem_valid, 
input         mem_instr, 
output        mem_ready, 
input  [31:0] mem_addr, 
input  [31:0] mem_wdata, 
input  [ 3:0] mem_wstrb, 
output [31:0] mem_rdata 
); 
reg ack_awvalid; 
reg ack_arvalid; 
reg ack_wvalid; 
reg xfer_done; 
 
assign mem_axi_awvalid = mem_valid && |mem_wstrb && !ack_awvalid; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:4373\n"  , count_cycle); 
end 
assign mem_axi_awaddr = mem_addr; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:4377\n"  , count_cycle); 
end 
assign mem_axi_awprot = 0; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:4381\n"  , count_cycle); 
end 
 
assign mem_axi_arvalid = mem_valid && !mem_wstrb && !ack_arvalid; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:4386\n"  , count_cycle); 
end 
assign mem_axi_araddr = mem_addr; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:4390\n"  , count_cycle); 
end 
assign mem_axi_arprot = mem_instr ? 3'b100 : 3'b000; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:4394\n"  , count_cycle); 
end 
 
assign mem_axi_wvalid = mem_valid && |mem_wstrb && !ack_wvalid; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:4399\n"  , count_cycle); 
end 
assign mem_axi_wdata = mem_wdata; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:4403\n"  , count_cycle); 
end 
assign mem_axi_wstrb = mem_wstrb; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:4407\n"  , count_cycle); 
end 
 
assign mem_ready = mem_axi_bvalid || mem_axi_rvalid; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:4412\n"  , count_cycle); 
end 
assign mem_axi_bready = mem_valid && |mem_wstrb; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:4416\n"  , count_cycle); 
end 
assign mem_axi_rready = mem_valid && !mem_wstrb; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:4420\n"  , count_cycle); 
end 
assign mem_rdata = mem_axi_rdata; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:4424\n"  , count_cycle); 
end 
 
always @(posedge clk) begin 
$fwrite(f,"%0d cycle :picorv32.v:4431\n"  , count_cycle); 
if (!resetn) begin 
ack_awvalid <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:4432\n"  , count_cycle); 
end else begin 
xfer_done <= mem_valid && mem_ready; 
$fwrite(f,"%0d cycle :picorv32.v:4435\n"  , count_cycle); 
$fwrite(f,"%0d cycle :picorv32.v:4438\n"  , count_cycle); 
if (mem_axi_awready && mem_axi_awvalid) begin 
ack_awvalid <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:4439\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:4443\n"  , count_cycle); 
if (mem_axi_arready && mem_axi_arvalid) begin 
ack_arvalid <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:4444\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:4448\n"  , count_cycle); 
if (mem_axi_wready && mem_axi_wvalid) begin 
ack_wvalid <= 1; 
$fwrite(f,"%0d cycle :picorv32.v:4449\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :picorv32.v:4453\n"  , count_cycle); 
if (xfer_done || !mem_valid) begin 
ack_awvalid <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:4454\n"  , count_cycle); 
ack_arvalid <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:4456\n"  , count_cycle); 
ack_wvalid <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:4458\n"  , count_cycle); 
end 
end 
end 
endmodule 
 
 
/*************************************************************** 
* picorv32_wb 
***************************************************************/ 
 
module picorv32_wb #( 
parameter [ 0:0] ENABLE_COUNTERS = 1, 
parameter [ 0:0] ENABLE_COUNTERS64 = 1, 
parameter [ 0:0] ENABLE_REGS_16_31 = 1, 
parameter [ 0:0] ENABLE_REGS_DUALPORT = 1, 
parameter [ 0:0] TWO_STAGE_SHIFT = 1, 
parameter [ 0:0] BARREL_SHIFTER = 0, 
parameter [ 0:0] TWO_CYCLE_COMPARE = 0, 
parameter [ 0:0] TWO_CYCLE_ALU = 0, 
parameter [ 0:0] COMPRESSED_ISA = 0, 
parameter [ 0:0] CATCH_MISALIGN = 1, 
parameter [ 0:0] CATCH_ILLINSN = 1, 
parameter [ 0:0] ENABLE_PCPI = 0, 
parameter [ 0:0] ENABLE_MUL = 0, 
parameter [ 0:0] ENABLE_FAST_MUL = 0, 
parameter [ 0:0] ENABLE_DIV = 0, 
parameter [ 0:0] ENABLE_IRQ = 0, 
parameter [ 0:0] ENABLE_IRQ_QREGS = 1, 
parameter [ 0:0] ENABLE_IRQ_TIMER = 1, 
parameter [ 0:0] ENABLE_TRACE = 0, 
parameter [ 0:0] REGS_INIT_ZERO = 0, 
parameter [31:0] MASKED_IRQ = 32'h 0000_0000, 
parameter [31:0] LATCHED_IRQ = 32'h ffff_ffff, 
parameter [31:0] PROGADDR_RESET = 32'h 0000_0000, 
parameter [31:0] PROGADDR_IRQ = 32'h 0000_0010, 
parameter [31:0] STACKADDR = 32'h ffff_ffff 
) ( 
output trap, 
 
// Wishbone interfaces 
input wb_rst_i, 
input wb_clk_i, 
 
output reg [31:0] wbm_adr_o, 
output reg [31:0] wbm_dat_o, 
input [31:0] wbm_dat_i, 
output reg wbm_we_o, 
output reg [3:0] wbm_sel_o, 
output reg wbm_stb_o, 
input wbm_ack_i, 
output reg wbm_cyc_o, 
 
// Pico Co-Processor Interface (PCPI) 
output        pcpi_valid, 
output [31:0] pcpi_insn, 
output [31:0] pcpi_rs1, 
output [31:0] pcpi_rs2, 
input         pcpi_wr, 
input  [31:0] pcpi_rd, 
input         pcpi_wait, 
input         pcpi_ready, 
 
// IRQ interface 
input  [31:0] irq, 
output [31:0] eoi, 
 
`ifdef RISCV_FORMAL 
output        rvfi_valid, 
output [63:0] rvfi_order, 
output [31:0] rvfi_insn, 
output        rvfi_trap, 
output        rvfi_halt, 
output        rvfi_intr, 
output [ 4:0] rvfi_rs1_addr, 
output [ 4:0] rvfi_rs2_addr, 
output [31:0] rvfi_rs1_rdata, 
output [31:0] rvfi_rs2_rdata, 
output [ 4:0] rvfi_rd_addr, 
output [31:0] rvfi_rd_wdata, 
output [31:0] rvfi_pc_rdata, 
output [31:0] rvfi_pc_wdata, 
output [31:0] rvfi_mem_addr, 
output [ 3:0] rvfi_mem_rmask, 
output [ 3:0] rvfi_mem_wmask, 
output [31:0] rvfi_mem_rdata, 
output [31:0] rvfi_mem_wdata, 
`endif 
 
// Trace Interface 
output        trace_valid, 
output [35:0] trace_data, 
 
output mem_instr 
); 
wire        mem_valid; 
wire [31:0] mem_addr; 
wire [31:0] mem_wdata; 
wire [ 3:0] mem_wstrb; 
reg         mem_ready; 
reg [31:0] mem_rdata; 
 
wire clk; 
wire resetn; 
 
assign clk = wb_clk_i; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:4564\n"  , count_cycle); 
end 
assign resetn = ~wb_rst_i; 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:4568\n"  , count_cycle); 
end 
 
picorv32 #( 
.ENABLE_COUNTERS     (ENABLE_COUNTERS     ), 
.ENABLE_COUNTERS64   (ENABLE_COUNTERS64   ), 
.ENABLE_REGS_16_31   (ENABLE_REGS_16_31   ), 
.ENABLE_REGS_DUALPORT(ENABLE_REGS_DUALPORT), 
.TWO_STAGE_SHIFT     (TWO_STAGE_SHIFT     ), 
.BARREL_SHIFTER      (BARREL_SHIFTER      ), 
.TWO_CYCLE_COMPARE   (TWO_CYCLE_COMPARE   ), 
.TWO_CYCLE_ALU       (TWO_CYCLE_ALU       ), 
.COMPRESSED_ISA      (COMPRESSED_ISA      ), 
.CATCH_MISALIGN      (CATCH_MISALIGN      ), 
.CATCH_ILLINSN       (CATCH_ILLINSN       ), 
.ENABLE_PCPI         (ENABLE_PCPI         ), 
.ENABLE_MUL          (ENABLE_MUL          ), 
.ENABLE_FAST_MUL     (ENABLE_FAST_MUL     ), 
.ENABLE_DIV          (ENABLE_DIV          ), 
.ENABLE_IRQ          (ENABLE_IRQ          ), 
.ENABLE_IRQ_QREGS    (ENABLE_IRQ_QREGS    ), 
.ENABLE_IRQ_TIMER    (ENABLE_IRQ_TIMER    ), 
.ENABLE_TRACE        (ENABLE_TRACE        ), 
.REGS_INIT_ZERO      (REGS_INIT_ZERO      ), 
.MASKED_IRQ          (MASKED_IRQ          ), 
.LATCHED_IRQ         (LATCHED_IRQ         ), 
.PROGADDR_RESET      (PROGADDR_RESET      ), 
.PROGADDR_IRQ        (PROGADDR_IRQ        ), 
.STACKADDR           (STACKADDR           ) 
) picorv32_core ( 
.clk      (clk   ), 
.resetn   (resetn), 
.trap     (trap  ), 
 
.mem_valid(mem_valid), 
.mem_addr (mem_addr ), 
.mem_wdata(mem_wdata), 
.mem_wstrb(mem_wstrb), 
.mem_instr(mem_instr), 
.mem_ready(mem_ready), 
.mem_rdata(mem_rdata), 
 
.pcpi_valid(pcpi_valid), 
.pcpi_insn (pcpi_insn ), 
.pcpi_rs1  (pcpi_rs1  ), 
.pcpi_rs2  (pcpi_rs2  ), 
.pcpi_wr   (pcpi_wr   ), 
.pcpi_rd   (pcpi_rd   ), 
.pcpi_wait (pcpi_wait ), 
.pcpi_ready(pcpi_ready), 
 
.irq(irq), 
.eoi(eoi), 
 
`ifdef RISCV_FORMAL 
.rvfi_valid    (rvfi_valid    ), 
.rvfi_order    (rvfi_order    ), 
.rvfi_insn     (rvfi_insn     ), 
.rvfi_trap     (rvfi_trap     ), 
.rvfi_halt     (rvfi_halt     ), 
.rvfi_intr     (rvfi_intr     ), 
.rvfi_rs1_addr (rvfi_rs1_addr ), 
.rvfi_rs2_addr (rvfi_rs2_addr ), 
.rvfi_rs1_rdata(rvfi_rs1_rdata), 
.rvfi_rs2_rdata(rvfi_rs2_rdata), 
.rvfi_rd_addr  (rvfi_rd_addr  ), 
.rvfi_rd_wdata (rvfi_rd_wdata ), 
.rvfi_pc_rdata (rvfi_pc_rdata ), 
.rvfi_pc_wdata (rvfi_pc_wdata ), 
.rvfi_mem_addr (rvfi_mem_addr ), 
.rvfi_mem_rmask(rvfi_mem_rmask), 
.rvfi_mem_wmask(rvfi_mem_wmask), 
.rvfi_mem_rdata(rvfi_mem_rdata), 
.rvfi_mem_wdata(rvfi_mem_wdata), 
`endif 
 
.trace_valid(trace_valid), 
.trace_data (trace_data) 
); 
 
localparam IDLE = 2'b00; 
localparam WBSTART = 2'b01; 
localparam WBEND = 2'b10; 
 
reg [1:0] state; 
 
wire we; 
assign we = (mem_wstrb[0] | mem_wstrb[1] | mem_wstrb[2] | mem_wstrb[3]); 
always@* begin 
$fwrite(f,"%0d cycle :picorv32.v:4657\n"  , count_cycle); 
end 
 
always @(posedge wb_clk_i) begin 
$fwrite(f,"%0d cycle :picorv32.v:4664\n"  , count_cycle); 
if (wb_rst_i) begin 
wbm_adr_o <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:4665\n"  , count_cycle); 
wbm_dat_o <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:4667\n"  , count_cycle); 
wbm_we_o <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:4669\n"  , count_cycle); 
wbm_sel_o <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:4671\n"  , count_cycle); 
wbm_stb_o <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:4673\n"  , count_cycle); 
wbm_cyc_o <= 0; 
$fwrite(f,"%0d cycle :picorv32.v:4675\n"  , count_cycle); 
state <= IDLE; 
$fwrite(f,"%0d cycle :picorv32.v:4677\n"  , count_cycle); 
end else begin 
$fwrite(f,"%0d cycle :picorv32.v:4681\n"  , count_cycle); 
case (state) 
IDLE: begin 
$fwrite(f,"%0d cycle :picorv32.v:4684\n"  , count_cycle); 
if (mem_valid) begin 
wbm_adr_o <= mem_addr; 
$fwrite(f,"%0d cycle :picorv32.v:4685\n"  , count_cycle); 
wbm_dat_o <= mem_wdata; 
$fwrite(f,"%0d cycle :picorv32.v:4687\n"  , count_cycle); 
wbm_we_o <= we; 
$fwrite(f,"%0d cycle :picorv32.v:4689\n"  , count_cycle); 
wbm_sel_o <= mem_wstrb; 
$fwrite(f,"%0d cycle :picorv32.v:4691\n"  , count_cycle); 
 
wbm_stb_o <= 1'b1; 
$fwrite(f,"%0d cycle :picorv32.v:4694\n"  , count_cycle); 
wbm_cyc_o <= 1'b1; 
$fwrite(f,"%0d cycle :picorv32.v:4696\n"  , count_cycle); 
state <= WBSTART; 
$fwrite(f,"%0d cycle :picorv32.v:4698\n"  , count_cycle); 
end else begin 
mem_ready <= 1'b0; 
$fwrite(f,"%0d cycle :picorv32.v:4701\n"  , count_cycle); 
 
wbm_stb_o <= 1'b0; 
$fwrite(f,"%0d cycle :picorv32.v:4704\n"  , count_cycle); 
wbm_cyc_o <= 1'b0; 
$fwrite(f,"%0d cycle :picorv32.v:4706\n"  , count_cycle); 
wbm_we_o <= 1'b0; 
$fwrite(f,"%0d cycle :picorv32.v:4708\n"  , count_cycle); 
end 
end 
WBSTART:begin 
$fwrite(f,"%0d cycle :picorv32.v:4714\n"  , count_cycle); 
if (wbm_ack_i) begin 
mem_rdata <= wbm_dat_i; 
$fwrite(f,"%0d cycle :picorv32.v:4715\n"  , count_cycle); 
mem_ready <= 1'b1; 
$fwrite(f,"%0d cycle :picorv32.v:4717\n"  , count_cycle); 
 
state <= WBEND; 
$fwrite(f,"%0d cycle :picorv32.v:4720\n"  , count_cycle); 
 
wbm_stb_o <= 1'b0; 
$fwrite(f,"%0d cycle :picorv32.v:4723\n"  , count_cycle); 
wbm_cyc_o <= 1'b0; 
$fwrite(f,"%0d cycle :picorv32.v:4725\n"  , count_cycle); 
wbm_we_o <= 1'b0; 
$fwrite(f,"%0d cycle :picorv32.v:4727\n"  , count_cycle); 
end 
end 
WBEND: begin 
mem_ready <= 1'b0; 
$fwrite(f,"%0d cycle :picorv32.v:4732\n"  , count_cycle); 
 
state <= IDLE; 
$fwrite(f,"%0d cycle :picorv32.v:4735\n"  , count_cycle); 
end 
default: begin 
state <= IDLE; 
$fwrite(f,"%0d cycle :picorv32.v:4739\n"  , count_cycle); 
end 
endcase 
end 
end 
endmodule 
