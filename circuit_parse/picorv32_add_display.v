`timescale 1 ns / 1 ps 
`define PICORV32_V 
/* verilator lint_off WIDTH */ 
/* verilator lint_off CASEINCOMPLETE */ 
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
integer f; 
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
wire dbg_mem_instr = mem_instr; 
wire dbg_mem_ready = mem_ready; 
wire [31:0] dbg_mem_addr  = mem_addr; 
wire [31:0] dbg_mem_wdata = mem_wdata; 
wire [ 3:0] dbg_mem_wstrb = mem_wstrb; 
wire [31:0] dbg_mem_rdata = mem_rdata; 
 
assign pcpi_rs1 = reg_op1; 
always@* begin 
$fwrite(f,"%0d cycle :assign pcpi_rs1 = reg_op1;\n"  , count_cycle); 
end 
assign pcpi_rs2 = reg_op2; 
always@* begin 
$fwrite(f,"%0d cycle :assign pcpi_rs2 = reg_op2;\n"  , count_cycle); 
end 
 
wire [31:0] next_pc; 
 
reg irq_delay; 
reg irq_active; 
reg [31:0] irq_mask; 
reg [31:0] irq_pending; 
reg [31:0] timer; 
 
reg [31:0] cpuregs [0:regfile_size-1]; 
 
 
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
/* verilator lint_off MULTITOP */ 
 
 
 
 
 
`ifndef PICORV32_REGS 
 
integer i; 
 
initial begin 
f = $fopen("cpu_rw_1.txt", "w"); 
$fwrite(f,"%0d cycle :f = $fopen(\"cpu_rw_1.txt\", \"w\");\n"  , count_cycle); 
$fwrite(f,"%0d cycle :if (REGS_INIT_ZERO) begin\n"  , count_cycle); 
if (REGS_INIT_ZERO) begin 
for (i = 0; i < regfile_size; i = i+1) begin 
cpuregs[i] = 0; 
$fwrite(f,"%0d cycle :cpuregs[i] = 0;\n"  , count_cycle); 
end 
end 
end 
`endif 
always @* begin 
pcpi_int_wr = 0; 
$fwrite(f,"%0d cycle :pcpi_int_wr = 0;\n"  , count_cycle); 
pcpi_int_rd = 32'bx; 
$fwrite(f,"%0d cycle :pcpi_int_rd = 32\'bx;\n"  , count_cycle); 
pcpi_int_wait  = |{ENABLE_PCPI && pcpi_wait,  (ENABLE_MUL || ENABLE_FAST_MUL) && pcpi_mul_wait,  ENABLE_DIV && pcpi_div_wait}; 
$fwrite(f,"%0d cycle :pcpi_int_wait  = |{ENABLE_PCPI && pcpi_wait,  (ENABLE_MUL || ENABLE_FAST_MUL) && pcpi_mul_wait,  ENABLE_DIV && pcpi_div_wait};\n"  , count_cycle); 
pcpi_int_ready = |{ENABLE_PCPI && pcpi_ready, (ENABLE_MUL || ENABLE_FAST_MUL) && pcpi_mul_ready, ENABLE_DIV && pcpi_div_ready}; 
$fwrite(f,"%0d cycle :pcpi_int_ready = |{ENABLE_PCPI && pcpi_ready, (ENABLE_MUL || ENABLE_FAST_MUL) && pcpi_mul_ready, ENABLE_DIV && pcpi_div_ready};\n"  , count_cycle); 
 
(* parallel_case *) 
case (1'b1) 
ENABLE_PCPI && pcpi_ready: begin 
pcpi_int_wr = ENABLE_PCPI ? pcpi_wr : 0;
$fwrite(f,"%0d cycle :if = ENABLE_PCPI; \n"  , count_cycle);
if (ENABLE_PCPI) begin
$fwrite(f,"%0d cycle :pcpi_int_wr = pcpi_wr; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :pcpi_int_wr = 0; \n"  , count_cycle);
end
pcpi_int_rd = ENABLE_PCPI ? pcpi_rd : 0; 
$fwrite(f,"%0d cycle :if = ENABLE_PCPI; \n"  , count_cycle);
if (ENABLE_PCPI) begin
$fwrite(f,"%0d cycle :pcpi_int_rd = pcpi_rd; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :pcpi_int_rd = 0; \n"  , count_cycle);
end
end 
(ENABLE_MUL || ENABLE_FAST_MUL) && pcpi_mul_ready: begin 
pcpi_int_wr = pcpi_mul_wr; 
$fwrite(f,"%0d cycle :pcpi_int_wr = pcpi_mul_wr;\n"  , count_cycle); 
pcpi_int_rd = pcpi_mul_rd; 
$fwrite(f,"%0d cycle :pcpi_int_rd = pcpi_mul_rd;\n"  , count_cycle); 
end 
ENABLE_DIV && pcpi_div_ready: begin 
pcpi_int_wr = pcpi_div_wr; 
$fwrite(f,"%0d cycle :pcpi_int_wr = pcpi_div_wr;\n"  , count_cycle); 
pcpi_int_rd = pcpi_div_rd; 
$fwrite(f,"%0d cycle :pcpi_int_rd = pcpi_div_rd;\n"  , count_cycle); 
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
wire mem_la_firstword_xfer = COMPRESSED_ISA && mem_xfer && (!last_mem_valid ? mem_la_firstword : mem_la_firstword_reg); 
 
reg prefetched_high_word; 
reg clear_prefetched_high_word; 
reg [15:0] mem_16bit_buffer; 
 
wire [31:0] mem_rdata_latched_noshuffle; 
wire [31:0] mem_rdata_latched; 
 
wire mem_la_use_prefetched_high_word = COMPRESSED_ISA && mem_la_firstword && prefetched_high_word && !clear_prefetched_high_word; 
assign mem_xfer = (mem_valid && mem_ready) || (mem_la_use_prefetched_high_word && mem_do_rinst); 
always@* begin 
$fwrite(f,"%0d cycle :assign mem_xfer = (mem_valid && mem_ready) || (mem_la_use_prefetched_high_word && mem_do_rinst);\n"  , count_cycle); 
end 
 
wire mem_busy = |{mem_do_prefetch, mem_do_rinst, mem_do_rdata, mem_do_wdata}; 
wire mem_done = resetn && ((mem_xfer && |mem_state && (mem_do_rinst || mem_do_rdata || mem_do_wdata)) || (&mem_state && mem_do_rinst)) &&(!mem_la_firstword || (~&mem_rdata_latched[1:0] && mem_xfer)); 
 
assign mem_la_write = resetn && !mem_state && mem_do_wdata; 
always@* begin 
$fwrite(f,"%0d cycle :assign mem_la_write = resetn && !mem_state && mem_do_wdata;\n"  , count_cycle); 
end 
assign mem_la_read = resetn && ((!mem_la_use_prefetched_high_word && !mem_state && (mem_do_rinst || mem_do_prefetch || mem_do_rdata)) ||(COMPRESSED_ISA && mem_xfer && (!last_mem_valid ? mem_la_firstword : mem_la_firstword_reg) && !mem_la_secondword && &mem_rdata_latched[1:0])); 
always@* begin 
$fwrite(f,"%0d cycle :assign mem_la_read = resetn && ((!mem_la_use_prefetched_high_word && !mem_state && (mem_do_rinst || mem_do_prefetch || mem_do_rdata)) ||(COMPRESSED_ISA && mem_xfer && (!last_mem_valid ? mem_la_firstword : mem_la_firstword_reg) && !mem_la_secondword && &mem_rdata_latched[1:0]));\n"  , count_cycle); 
end 
assign mem_la_addr = (mem_do_prefetch || mem_do_rinst) ? {next_pc[31:2] + mem_la_firstword_xfer, 2'b00} : {reg_op1[31:2], 2'b00}; 
always@* begin 
$fwrite(f,"%0d cycle :if = mem_do_prefetch || mem_do_rinst; \n"  , count_cycle);
if (mem_do_prefetch || mem_do_rinst) begin
$fwrite(f,"%0d cycle :mem_la_addr = {next_pc[31:2] + mem_la_firstword_xfer, 2'b00}; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :mem_la_addr = {reg_op1[31:2], 2'b00}; \n"  , count_cycle);
end
end 
 
assign mem_rdata_latched_noshuffle = (mem_xfer || LATCHED_MEM_RDATA) ? mem_rdata : mem_rdata_q; 
always@* begin 
$fwrite(f,"%0d cycle :if = mem_xfer || LATCHED_MEM_RDATA; \n"  , count_cycle);
if (mem_xfer || LATCHED_MEM_RDATA) begin
$fwrite(f,"%0d cycle :mem_rdata_latched_noshuffle = mem_rdata; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :mem_rdata_latched_noshuffle = mem_rdata_q; \n"  , count_cycle);
end
end 
 
assign mem_rdata_latched = COMPRESSED_ISA && mem_la_use_prefetched_high_word ? {16'bx, mem_16bit_buffer} :COMPRESSED_ISA && mem_la_secondword ? {mem_rdata_latched_noshuffle[15:0], mem_16bit_buffer} :COMPRESSED_ISA && mem_la_firstword ? {16'bx, mem_rdata_latched_noshuffle[31:16]} : mem_rdata_latched_noshuffle; 
always@* begin 
$fwrite(f,"%0d cycle :if = COMPRESSED_ISA && mem_la_use_prefetched_high_word; \n"  , count_cycle);
if (COMPRESSED_ISA && mem_la_use_prefetched_high_word) begin
$fwrite(f,"%0d cycle :mem_rdata_latched =  {16'bx, mem_16bit_buffer}; \n"  , count_cycle);
end
else begin
    $fwrite(f,"%0d cycle :if = COMPRESSED_ISA && mem_la_secondword; \n"  , count_cycle);

    if (COMPRESSED_ISA && mem_la_secondword) begin
    $fwrite(f,"%0d cycle :mem_rdata_latched = {mem_rdata_latched_noshuffle[15:0], mem_16bit_buffer}; \n"  , count_cycle);
    end
    else begin
        $fwrite(f,"%0d cycle :if =COMPRESSED_ISA && mem_la_firstword; \n"  , count_cycle);
        if(COMPRESSED_ISA && mem_la_firstword ) begin
            $fwrite(f,"%0d cycle :mem_rdata_latched = {16'bx, mem_rdata_latched_noshuffle[31:16]}; \n"  , count_cycle);
        end
        else begin
            $fwrite(f,"%0d cycle :mem_rdata_latched = mem_rdata_latched_noshuffle; \n"  , count_cycle);
        end
    end
end
end 
 
always @(posedge clk) begin 
$fwrite(f,"%0d cycle :if (!resetn) begin\n"  , count_cycle); 
if (!resetn) begin 
mem_la_firstword_reg <= 0; 
$fwrite(f,"%0d cycle :mem_la_firstword_reg <= 0;\n"  , count_cycle); 
last_mem_valid <= 0; 
$fwrite(f,"%0d cycle :last_mem_valid <= 0;\n"  , count_cycle); 
end else begin 
$fwrite(f,"%0d cycle :if (!last_mem_valid) begin\n"  , count_cycle); 
if (!last_mem_valid) begin 
mem_la_firstword_reg <= mem_la_firstword; 
$fwrite(f,"%0d cycle :mem_la_firstword_reg <= mem_la_firstword;\n"  , count_cycle); 
end 
last_mem_valid <= mem_valid && !mem_ready; 
$fwrite(f,"%0d cycle :last_mem_valid <= mem_valid && !mem_ready;\n"  , count_cycle); 
end 
end 
 
always @* begin 
(* full_case *) 
case (mem_wordsize) 
0: begin 
mem_la_wdata = reg_op2; 
$fwrite(f,"%0d cycle :mem_la_wdata = reg_op2;\n"  , count_cycle); 
mem_la_wstrb = 4'b1111; 
$fwrite(f,"%0d cycle :mem_la_wstrb = 4\'b1111;\n"  , count_cycle); 
mem_rdata_word = mem_rdata; 
$fwrite(f,"%0d cycle :mem_rdata_word = mem_rdata;\n"  , count_cycle); 
end 
1: begin 
mem_la_wdata = {2{reg_op2[15:0]}}; 
$fwrite(f,"%0d cycle :mem_la_wdata = {2{reg_op2[15:0]}};\n"  , count_cycle); 
mem_la_wstrb = reg_op1[1] ? 4'b1100 : 4'b0011; 
$fwrite(f,"%0d cycle :if = reg_op1[1] \n"  , count_cycle);
if (reg_op1[1]) begin
$fwrite(f,"%0d cycle :mem_la_wstrb = 4'b1100; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :mem_la_wstrb = 4'b0011; \n"  , count_cycle);
end
$fwrite(f,"%0d cycle :case (reg_op1[1])\n"  , count_cycle); 
case (reg_op1[1]) 
1'b0: begin 
mem_rdata_word = {16'b0, mem_rdata[15: 0]}; 
$fwrite(f,"%0d cycle :mem_rdata_word = {16\'b0, mem_rdata[15: 0]};\n"  , count_cycle); 
end 
1'b1: begin 
mem_rdata_word = {16'b0, mem_rdata[31:16]}; 
$fwrite(f,"%0d cycle :mem_rdata_word = {16\'b0, mem_rdata[31:16]};\n"  , count_cycle); 
end 
endcase 
end 
2: begin 
mem_la_wdata = {4{reg_op2[7:0]}}; 
$fwrite(f,"%0d cycle :mem_la_wdata = {4{reg_op2[7:0]}};\n"  , count_cycle); 
mem_la_wstrb = 4'b0001 << reg_op1[1:0]; 
$fwrite(f,"%0d cycle :mem_la_wstrb = 4\'b0001 << reg_op1[1:0];\n"  , count_cycle); 
$fwrite(f,"%0d cycle :case (reg_op1[1:0])\n"  , count_cycle); 
case (reg_op1[1:0]) 
2'b00: begin 
mem_rdata_word = {24'b0, mem_rdata[ 7: 0]}; 
$fwrite(f,"%0d cycle :mem_rdata_word = {24\'b0, mem_rdata[ 7: 0]};\n"  , count_cycle); 
end 
2'b01: begin 
mem_rdata_word = {24'b0, mem_rdata[15: 8]}; 
$fwrite(f,"%0d cycle :mem_rdata_word = {24\'b0, mem_rdata[15: 8]};\n"  , count_cycle); 
end 
2'b10: begin 
mem_rdata_word = {24'b0, mem_rdata[23:16]}; 
$fwrite(f,"%0d cycle :mem_rdata_word = {24\'b0, mem_rdata[23:16]};\n"  , count_cycle); 
end 
2'b11: begin 
mem_rdata_word = {24'b0, mem_rdata[31:24]}; 
$fwrite(f,"%0d cycle :mem_rdata_word = {24\'b0, mem_rdata[31:24]};\n"  , count_cycle); 
end 
endcase 
end 
endcase 
end 
 
always @(posedge clk) begin 
$fwrite(f,"%0d cycle :if (mem_xfer) begin\n"  , count_cycle); 
if (mem_xfer) begin 
mem_rdata_q <= COMPRESSED_ISA ? mem_rdata_latched : mem_rdata; 
$fwrite(f,"%0d cycle :if = COMPRESSED_ISA \n"  , count_cycle);
if (COMPRESSED_ISA) begin
$fwrite(f,"%0d cycle :mem_rdata_q = mem_rdata_latched; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :mem_rdata_q = mem_rdata; \n"  , count_cycle);
end
next_insn_opcode <= COMPRESSED_ISA ? mem_rdata_latched : mem_rdata; 
$fwrite(f,"%0d cycle :if = COMPRESSED_ISA \n"  , count_cycle);
if (COMPRESSED_ISA) begin
$fwrite(f,"%0d cycle :next_insn_opcode = mem_rdata_latched; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :next_insn_opcode = mem_rdata; \n"  , count_cycle);
end
end 
 
$fwrite(f,"%0d cycle :if (COMPRESSED_ISA && mem_done && (mem_do_prefetch || mem_do_rinst)) begin\n"  , count_cycle); 
if (COMPRESSED_ISA && mem_done && (mem_do_prefetch || mem_do_rinst)) begin 
$fwrite(f,"%0d cycle :case (mem_rdata_latched[1:0])\n"  , count_cycle); 
case (mem_rdata_latched[1:0]) 
2'b00: begin // Quadrant 0 
$fwrite(f,"%0d cycle :case (mem_rdata_latched[15:13])\n"  , count_cycle); 
case (mem_rdata_latched[15:13]) 
3'b000: begin // C.ADDI4SPN 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0d cycle :mem_rdata_q[14:12] <= 3\'b000;\n"  , count_cycle); 
mem_rdata_q[31:20] <= {2'b0, mem_rdata_latched[10:7], mem_rdata_latched[12:11], mem_rdata_latched[5], mem_rdata_latched[6], 2'b00}; 
$fwrite(f,"%0d cycle :mem_rdata_q[31:20] <= {2\'b0, mem_rdata_latched[10:7], mem_rdata_latched[12:11], mem_rdata_latched[5], mem_rdata_latched[6], 2\'b00};\n"  , count_cycle); 
end 
3'b010: begin // C.LW 
mem_rdata_q[31:20] <= {5'b0, mem_rdata_latched[5], mem_rdata_latched[12:10], mem_rdata_latched[6], 2'b00}; 
$fwrite(f,"%0d cycle :mem_rdata_q[31:20] <= {5\'b0, mem_rdata_latched[5], mem_rdata_latched[12:10], mem_rdata_latched[6], 2\'b00};\n"  , count_cycle); 
mem_rdata_q[14:12] <= 3'b 010; 
$fwrite(f,"%0d cycle :mem_rdata_q[14:12] <= 3\'b 010;\n"  , count_cycle); 
end 
3'b 110: begin // C.SW 
{mem_rdata_q[31:25], mem_rdata_q[11:7]} <= {5'b0, mem_rdata_latched[5], mem_rdata_latched[12:10], mem_rdata_latched[6], 2'b00}; 
$fwrite(f,"%0d cycle :{mem_rdata_q[31:25], mem_rdata_q[11:7]} <= {5\'b0, mem_rdata_latched[5], mem_rdata_latched[12:10], mem_rdata_latched[6], 2\'b00};\n"  , count_cycle); 
mem_rdata_q[14:12] <= 3'b 010; 
$fwrite(f,"%0d cycle :mem_rdata_q[14:12] <= 3\'b 010;\n"  , count_cycle); 
end 
endcase 
end 
2'b01: begin // Quadrant 1 
$fwrite(f,"%0d cycle :case (mem_rdata_latched[15:13])\n"  , count_cycle); 
case (mem_rdata_latched[15:13]) 
3'b 000: begin // C.ADDI 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0d cycle :mem_rdata_q[14:12] <= 3\'b000;\n"  , count_cycle); 
mem_rdata_q[31:20] <= $signed({mem_rdata_latched[12], mem_rdata_latched[6:2]}); 
$fwrite(f,"%0d cycle :mem_rdata_q[31:20] <= $signed({mem_rdata_latched[12], mem_rdata_latched[6:2]});\n"  , count_cycle); 
end 
3'b 010: begin // C.LI 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0d cycle :mem_rdata_q[14:12] <= 3\'b000;\n"  , count_cycle); 
mem_rdata_q[31:20] <= $signed({mem_rdata_latched[12], mem_rdata_latched[6:2]}); 
$fwrite(f,"%0d cycle :mem_rdata_q[31:20] <= $signed({mem_rdata_latched[12], mem_rdata_latched[6:2]});\n"  , count_cycle); 
end 
3'b 011: begin 
$fwrite(f,"%0d cycle :if (mem_rdata_latched[11:7] == 2) begin // C.ADDI16SP\n"  , count_cycle); 
if (mem_rdata_latched[11:7] == 2) begin // C.ADDI16SP 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0d cycle :mem_rdata_q[14:12] <= 3\'b000;\n"  , count_cycle); 
mem_rdata_q[31:20] <= $signed({mem_rdata_latched[12], mem_rdata_latched[4:3],mem_rdata_latched[5], mem_rdata_latched[2], mem_rdata_latched[6], 4'b 0000}); 
$fwrite(f,"%0d cycle :mem_rdata_q[31:20] <= $signed({mem_rdata_latched[12], mem_rdata_latched[4:3],mem_rdata_latched[5], mem_rdata_latched[2], mem_rdata_latched[6], 4\'b 0000});\n"  , count_cycle); 
end else begin // C.LUI 
mem_rdata_q[31:12] <= $signed({mem_rdata_latched[12], mem_rdata_latched[6:2]}); 
$fwrite(f,"%0d cycle :mem_rdata_q[31:12] <= $signed({mem_rdata_latched[12], mem_rdata_latched[6:2]});\n"  , count_cycle); 
end 
end 
3'b100: begin 
$fwrite(f,"%0d cycle :if (mem_rdata_latched[11:10] == 2\'b00) begin // C.SRLI\n"  , count_cycle); 
if (mem_rdata_latched[11:10] == 2'b00) begin // C.SRLI 
mem_rdata_q[31:25] <= 7'b0000000; 
$fwrite(f,"%0d cycle :mem_rdata_q[31:25] <= 7\'b0000000;\n"  , count_cycle); 
mem_rdata_q[14:12] <= 3'b 101; 
$fwrite(f,"%0d cycle :mem_rdata_q[14:12] <= 3\'b 101;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (mem_rdata_latched[11:10] == 2\'b01) begin // C.SRAI\n"  , count_cycle); 
if (mem_rdata_latched[11:10] == 2'b01) begin // C.SRAI 
mem_rdata_q[31:25] <= 7'b0100000; 
$fwrite(f,"%0d cycle :mem_rdata_q[31:25] <= 7\'b0100000;\n"  , count_cycle); 
mem_rdata_q[14:12] <= 3'b 101; 
$fwrite(f,"%0d cycle :mem_rdata_q[14:12] <= 3\'b 101;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (mem_rdata_latched[11:10] == 2\'b10) begin // C.ANDI\n"  , count_cycle); 
if (mem_rdata_latched[11:10] == 2'b10) begin // C.ANDI 
mem_rdata_q[14:12] <= 3'b111; 
$fwrite(f,"%0d cycle :mem_rdata_q[14:12] <= 3\'b111;\n"  , count_cycle); 
mem_rdata_q[31:20] <= $signed({mem_rdata_latched[12], mem_rdata_latched[6:2]}); 
$fwrite(f,"%0d cycle :mem_rdata_q[31:20] <= $signed({mem_rdata_latched[12], mem_rdata_latched[6:2]});\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (mem_rdata_latched[12:10] == 3\'b011) begin // C.SUB, C.XOR, C.OR, C.AND\n"  , count_cycle); 
if (mem_rdata_latched[12:10] == 3'b011) begin // C.SUB, C.XOR, C.OR, C.AND 
$fwrite(f,"%0d cycle :if (mem_rdata_latched[6:5] == 2\'b00) begin\n"  , count_cycle); 
if (mem_rdata_latched[6:5] == 2'b00) begin 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0d cycle :mem_rdata_q[14:12] <= 3\'b000;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (mem_rdata_latched[6:5] == 2\'b01) begin\n"  , count_cycle); 
if (mem_rdata_latched[6:5] == 2'b01) begin 
mem_rdata_q[14:12] <= 3'b100; 
$fwrite(f,"%0d cycle :mem_rdata_q[14:12] <= 3\'b100;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (mem_rdata_latched[6:5] == 2\'b10) begin\n"  , count_cycle); 
if (mem_rdata_latched[6:5] == 2'b10) begin 
mem_rdata_q[14:12] <= 3'b110; 
$fwrite(f,"%0d cycle :mem_rdata_q[14:12] <= 3\'b110;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (mem_rdata_latched[6:5] == 2\'b11) begin\n"  , count_cycle); 
if (mem_rdata_latched[6:5] == 2'b11) begin 
mem_rdata_q[14:12] <= 3'b111; 
$fwrite(f,"%0d cycle :mem_rdata_q[14:12] <= 3\'b111;\n"  , count_cycle); 
end 
mem_rdata_q[31:25] <= mem_rdata_latched[6:5] == 2'b00 ? 7'b0100000 : 7'b0000000; 
$fwrite(f,"%0d cycle :if =  mem_rdata_latched[6:5] == 2'b00 \n"  , count_cycle);
if ( mem_rdata_latched[6:5] == 2'b00) begin
$fwrite(f,"%0d cycle :mem_rdata_q[31:25] = 7'b0100000 ; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :mem_rdata_q[31:25] = 7'b0000000; \n"  , count_cycle);
end
end 
end 
3'b 110: begin // C.BEQZ 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0d cycle :mem_rdata_q[14:12] <= 3\'b000;\n"  , count_cycle); 
{ mem_rdata_q[31], mem_rdata_q[7], mem_rdata_q[30:25], mem_rdata_q[11:8] } <=$signed({mem_rdata_latched[12], mem_rdata_latched[6:5], mem_rdata_latched[2],mem_rdata_latched[11:10], mem_rdata_latched[4:3]}); 
$fwrite(f,"%0d cycle :{ mem_rdata_q[31], mem_rdata_q[7], mem_rdata_q[30:25], mem_rdata_q[11:8] } <=$signed({mem_rdata_latched[12], mem_rdata_latched[6:5], mem_rdata_latched[2],mem_rdata_latched[11:10], mem_rdata_latched[4:3]});\n"  , count_cycle); 
end 
3'b 111: begin // C.BNEZ 
mem_rdata_q[14:12] <= 3'b001; 
$fwrite(f,"%0d cycle :mem_rdata_q[14:12] <= 3\'b001;\n"  , count_cycle); 
{ mem_rdata_q[31], mem_rdata_q[7], mem_rdata_q[30:25], mem_rdata_q[11:8] } <=$signed({mem_rdata_latched[12], mem_rdata_latched[6:5], mem_rdata_latched[2],mem_rdata_latched[11:10], mem_rdata_latched[4:3]}); 
$fwrite(f,"%0d cycle :{ mem_rdata_q[31], mem_rdata_q[7], mem_rdata_q[30:25], mem_rdata_q[11:8] } <=$signed({mem_rdata_latched[12], mem_rdata_latched[6:5], mem_rdata_latched[2],mem_rdata_latched[11:10], mem_rdata_latched[4:3]});\n"  , count_cycle); 
end 
endcase 
end 
2'b10: begin // Quadrant 2 
$fwrite(f,"%0d cycle :case (mem_rdata_latched[15:13])\n"  , count_cycle); 
case (mem_rdata_latched[15:13]) 
3'b000: begin // C.SLLI 
mem_rdata_q[31:25] <= 7'b0000000; 
$fwrite(f,"%0d cycle :mem_rdata_q[31:25] <= 7\'b0000000;\n"  , count_cycle); 
mem_rdata_q[14:12] <= 3'b 001; 
$fwrite(f,"%0d cycle :mem_rdata_q[14:12] <= 3\'b 001;\n"  , count_cycle); 
end 
3'b010: begin // C.LWSP 
mem_rdata_q[31:20] <= {4'b0, mem_rdata_latched[3:2], mem_rdata_latched[12], mem_rdata_latched[6:4], 2'b00}; 
$fwrite(f,"%0d cycle :mem_rdata_q[31:20] <= {4\'b0, mem_rdata_latched[3:2], mem_rdata_latched[12], mem_rdata_latched[6:4], 2\'b00};\n"  , count_cycle); 
mem_rdata_q[14:12] <= 3'b 010; 
$fwrite(f,"%0d cycle :mem_rdata_q[14:12] <= 3\'b 010;\n"  , count_cycle); 
end 
3'b100: begin 
$fwrite(f,"%0d cycle :if (mem_rdata_latched[12] == 0 && mem_rdata_latched[6:2] == 0) begin // C.JR\n"  , count_cycle); 
if (mem_rdata_latched[12] == 0 && mem_rdata_latched[6:2] == 0) begin // C.JR 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0d cycle :mem_rdata_q[14:12] <= 3\'b000;\n"  , count_cycle); 
mem_rdata_q[31:20] <= 12'b0; 
$fwrite(f,"%0d cycle :mem_rdata_q[31:20] <= 12\'b0;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (mem_rdata_latched[12] == 0 && mem_rdata_latched[6:2] != 0) begin // C.MV\n"  , count_cycle); 
if (mem_rdata_latched[12] == 0 && mem_rdata_latched[6:2] != 0) begin // C.MV 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0d cycle :mem_rdata_q[14:12] <= 3\'b000;\n"  , count_cycle); 
mem_rdata_q[31:25] <= 7'b0000000; 
$fwrite(f,"%0d cycle :mem_rdata_q[31:25] <= 7\'b0000000;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (mem_rdata_latched[12] != 0 && mem_rdata_latched[11:7] != 0 && mem_rdata_latched[6:2] == 0) begin // C.JALR\n"  , count_cycle); 
if (mem_rdata_latched[12] != 0 && mem_rdata_latched[11:7] != 0 && mem_rdata_latched[6:2] == 0) begin // C.JALR 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0d cycle :mem_rdata_q[14:12] <= 3\'b000;\n"  , count_cycle); 
mem_rdata_q[31:20] <= 12'b0; 
$fwrite(f,"%0d cycle :mem_rdata_q[31:20] <= 12\'b0;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (mem_rdata_latched[12] != 0 && mem_rdata_latched[6:2] != 0) begin // C.ADD\n"  , count_cycle); 
if (mem_rdata_latched[12] != 0 && mem_rdata_latched[6:2] != 0) begin // C.ADD 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0d cycle :mem_rdata_q[14:12] <= 3\'b000;\n"  , count_cycle); 
mem_rdata_q[31:25] <= 7'b0000000; 
$fwrite(f,"%0d cycle :mem_rdata_q[31:25] <= 7\'b0000000;\n"  , count_cycle); 
end 
end 
3'b110: begin // C.SWSP 
{mem_rdata_q[31:25], mem_rdata_q[11:7]} <= {4'b0, mem_rdata_latched[8:7], mem_rdata_latched[12:9], 2'b00}; 
$fwrite(f,"%0d cycle :{mem_rdata_q[31:25], mem_rdata_q[11:7]} <= {4\'b0, mem_rdata_latched[8:7], mem_rdata_latched[12:9], 2\'b00};\n"  , count_cycle); 
mem_rdata_q[14:12] <= 3'b 010; 
$fwrite(f,"%0d cycle :mem_rdata_q[14:12] <= 3\'b 010;\n"  , count_cycle); 
end 
endcase 
end 
endcase 
end 
end 
 
always @(posedge clk) begin 
$fwrite(f,"%0d cycle :if (!resetn || trap) begin\n"  , count_cycle); 
if (!resetn || trap) begin 
$fwrite(f,"%0d cycle :if (!resetn) begin\n"  , count_cycle); 
if (!resetn) begin 
mem_state <= 0; 
$fwrite(f,"%0d cycle :mem_state <= 0;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (!resetn || mem_ready) begin\n"  , count_cycle); 
if (!resetn || mem_ready) begin 
mem_valid <= 0; 
$fwrite(f,"%0d cycle :mem_valid <= 0;\n"  , count_cycle); 
end 
mem_la_secondword <= 0; 
$fwrite(f,"%0d cycle :mem_la_secondword <= 0;\n"  , count_cycle); 
prefetched_high_word <= 0; 
$fwrite(f,"%0d cycle :prefetched_high_word <= 0;\n"  , count_cycle); 
end else begin 
$fwrite(f,"%0d cycle :if (mem_la_read || mem_la_write) begin\n"  , count_cycle); 
if (mem_la_read || mem_la_write) begin 
mem_addr <= mem_la_addr; 
$fwrite(f,"%0d cycle :mem_addr <= mem_la_addr;\n"  , count_cycle); 
mem_wstrb <= mem_la_wstrb & {4{mem_la_write}}; 
$fwrite(f,"%0d cycle :mem_wstrb <= mem_la_wstrb & {4{mem_la_write}};\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (mem_la_write) begin\n"  , count_cycle); 
if (mem_la_write) begin 
mem_wdata <= mem_la_wdata; 
$fwrite(f,"%0d cycle :mem_wdata <= mem_la_wdata;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :case (mem_state)\n"  , count_cycle); 
case (mem_state) 
0: begin 
$fwrite(f,"%0d cycle :if (mem_do_prefetch || mem_do_rinst || mem_do_rdata) begin\n"  , count_cycle); 
if (mem_do_prefetch || mem_do_rinst || mem_do_rdata) begin 
mem_valid <= !mem_la_use_prefetched_high_word; 
$fwrite(f,"%0d cycle :mem_valid <= !mem_la_use_prefetched_high_word;\n"  , count_cycle); 
mem_instr <= mem_do_prefetch || mem_do_rinst; 
$fwrite(f,"%0d cycle :mem_instr <= mem_do_prefetch || mem_do_rinst;\n"  , count_cycle); 
mem_wstrb <= 0; 
$fwrite(f,"%0d cycle :mem_wstrb <= 0;\n"  , count_cycle); 
mem_state <= 1; 
$fwrite(f,"%0d cycle :mem_state <= 1;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (mem_do_wdata) begin\n"  , count_cycle); 
if (mem_do_wdata) begin 
mem_valid <= 1; 
$fwrite(f,"%0d cycle :mem_valid <= 1;\n"  , count_cycle); 
mem_instr <= 0; 
$fwrite(f,"%0d cycle :mem_instr <= 0;\n"  , count_cycle); 
mem_state <= 2; 
$fwrite(f,"%0d cycle :mem_state <= 2;\n"  , count_cycle); 
end 
end 
1: begin 
$fwrite(f,"%0d cycle :if (mem_xfer) begin\n"  , count_cycle); 
if (mem_xfer) begin 
$fwrite(f,"%0d cycle :if (COMPRESSED_ISA && mem_la_read) begin\n"  , count_cycle); 
if (COMPRESSED_ISA && mem_la_read) begin 
mem_valid <= 1; 
$fwrite(f,"%0d cycle :mem_valid <= 1;\n"  , count_cycle); 
mem_la_secondword <= 1; 
$fwrite(f,"%0d cycle :mem_la_secondword <= 1;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :if (!mem_la_use_prefetched_high_word) begin\n"  , count_cycle); 
if (!mem_la_use_prefetched_high_word) begin 
mem_16bit_buffer <= mem_rdata[31:16]; 
$fwrite(f,"%0d cycle :mem_16bit_buffer <= mem_rdata[31:16];\n"  , count_cycle); 
end 
end else begin 
mem_valid <= 0; 
$fwrite(f,"%0d cycle :mem_valid <= 0;\n"  , count_cycle); 
mem_la_secondword <= 0; 
$fwrite(f,"%0d cycle :mem_la_secondword <= 0;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :if (COMPRESSED_ISA && !mem_do_rdata) begin\n"  , count_cycle); 
if (COMPRESSED_ISA && !mem_do_rdata) begin 
$fwrite(f,"%0d cycle :if (~&mem_rdata[1:0] || mem_la_secondword) begin\n"  , count_cycle); 
if (~&mem_rdata[1:0] || mem_la_secondword) begin 
mem_16bit_buffer <= mem_rdata[31:16]; 
$fwrite(f,"%0d cycle :mem_16bit_buffer <= mem_rdata[31:16];\n"  , count_cycle); 
prefetched_high_word <= 1; 
$fwrite(f,"%0d cycle :prefetched_high_word <= 1;\n"  , count_cycle); 
end else begin 
prefetched_high_word <= 0; 
$fwrite(f,"%0d cycle :prefetched_high_word <= 0;\n"  , count_cycle); 
end 
end 
mem_state <= mem_do_rinst || mem_do_rdata ? 0 : 3; 
$fwrite(f,"%0d cycle :if =  mem_do_rinst || mem_do_rdata \n"  , count_cycle);
if ( mem_do_rinst || mem_do_rdata) begin
$fwrite(f,"%0d cycle :mem_state= 0 ; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :mem_state = 3; \n"  , count_cycle);
end
end 
end 
end 
2: begin 
 
$fwrite(f,"%0d cycle :if (mem_xfer) begin\n"  , count_cycle); 
if (mem_xfer) begin 
mem_valid <= 0; 
$fwrite(f,"%0d cycle :mem_valid <= 0;\n"  , count_cycle); 
mem_state <= 0; 
$fwrite(f,"%0d cycle :mem_state <= 0;\n"  , count_cycle); 
end 
end 
3: begin 
 
$fwrite(f,"%0d cycle :if (mem_do_rinst) begin\n"  , count_cycle); 
if (mem_do_rinst) begin 
mem_state <= 0; 
$fwrite(f,"%0d cycle :mem_state <= 0;\n"  , count_cycle); 
end 
end 
endcase 
end 
 
$fwrite(f,"%0d cycle :if (clear_prefetched_high_word) begin\n"  , count_cycle); 
if (clear_prefetched_high_word) begin 
prefetched_high_word <= 0; 
$fwrite(f,"%0d cycle :prefetched_high_word <= 0;\n"  , count_cycle); 
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
$fwrite(f,"%0d cycle :assign instr_trap = (CATCH_ILLINSN || WITH_PCPI) && !{instr_lui, instr_auipc, instr_jal, instr_jalr,instr_beq, instr_bne, instr_blt, instr_bge, instr_bltu, instr_bgeu,instr_lb, instr_lh, instr_lw, instr_lbu, instr_lhu, instr_sb, instr_sh, instr_sw,instr_addi, instr_slti, instr_sltiu, instr_xori, instr_ori, instr_andi, instr_slli, instr_srli, instr_srai,instr_add, instr_sub, instr_sll, instr_slt, instr_sltu, instr_xor, instr_srl, instr_sra, instr_or, instr_and,instr_rdcycle, instr_rdcycleh, instr_rdinstr, instr_rdinstrh,instr_getq, instr_setq, instr_retirq, instr_maskirq, instr_waitirq, instr_timer};\n"  , count_cycle); 
end 
 
wire is_rdcycle_rdcycleh_rdinstr_rdinstrh; 
assign is_rdcycle_rdcycleh_rdinstr_rdinstrh = |{instr_rdcycle, instr_rdcycleh, instr_rdinstr, instr_rdinstrh}; 
always@* begin 
$fwrite(f,"%0d cycle :assign is_rdcycle_rdcycleh_rdinstr_rdinstrh = |{instr_rdcycle, instr_rdcycleh, instr_rdinstr, instr_rdinstrh};\n"  , count_cycle); 
end 
 
reg [63:0] new_ascii_instr; 
reg [63:0] dbg_ascii_instr; 
reg [31:0] dbg_insn_imm; 
reg [4:0] dbg_insn_rs1; 
reg [4:0] dbg_insn_rs2; 
reg [4:0] dbg_insn_rd; 
reg [31:0] dbg_rs1val; 
reg [31:0] dbg_rs2val; 
reg dbg_rs1val_valid; 
reg dbg_rs2val_valid; 
 
always @* begin 
new_ascii_instr = ""; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"\";\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :if (instr_lui) begin\n"  , count_cycle); 
if (instr_lui) begin 
new_ascii_instr = "lui"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"lui\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_auipc) begin\n"  , count_cycle); 
if (instr_auipc) begin 
new_ascii_instr = "auipc"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"auipc\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_jal) begin\n"  , count_cycle); 
if (instr_jal) begin 
new_ascii_instr = "jal"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"jal\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_jalr) begin\n"  , count_cycle); 
if (instr_jalr) begin 
new_ascii_instr = "jalr"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"jalr\";\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :if (instr_beq) begin\n"  , count_cycle); 
if (instr_beq) begin 
new_ascii_instr = "beq"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"beq\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_bne) begin\n"  , count_cycle); 
if (instr_bne) begin 
new_ascii_instr = "bne"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"bne\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_blt) begin\n"  , count_cycle); 
if (instr_blt) begin 
new_ascii_instr = "blt"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"blt\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_bge) begin\n"  , count_cycle); 
if (instr_bge) begin 
new_ascii_instr = "bge"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"bge\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_bltu) begin\n"  , count_cycle); 
if (instr_bltu) begin 
new_ascii_instr = "bltu"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"bltu\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_bgeu) begin\n"  , count_cycle); 
if (instr_bgeu) begin 
new_ascii_instr = "bgeu"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"bgeu\";\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :if (instr_lb) begin\n"  , count_cycle); 
if (instr_lb) begin 
new_ascii_instr = "lb"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"lb\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_lh) begin\n"  , count_cycle); 
if (instr_lh) begin 
new_ascii_instr = "lh"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"lh\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_lw) begin\n"  , count_cycle); 
if (instr_lw) begin 
new_ascii_instr = "lw"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"lw\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_lbu) begin\n"  , count_cycle); 
if (instr_lbu) begin 
new_ascii_instr = "lbu"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"lbu\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_lhu) begin\n"  , count_cycle); 
if (instr_lhu) begin 
new_ascii_instr = "lhu"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"lhu\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_sb) begin\n"  , count_cycle); 
if (instr_sb) begin 
new_ascii_instr = "sb"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"sb\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_sh) begin\n"  , count_cycle); 
if (instr_sh) begin 
new_ascii_instr = "sh"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"sh\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_sw) begin\n"  , count_cycle); 
if (instr_sw) begin 
new_ascii_instr = "sw"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"sw\";\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :if (instr_addi) begin\n"  , count_cycle); 
if (instr_addi) begin 
new_ascii_instr = "addi"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"addi\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_slti) begin\n"  , count_cycle); 
if (instr_slti) begin 
new_ascii_instr = "slti"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"slti\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_sltiu) begin\n"  , count_cycle); 
if (instr_sltiu) begin 
new_ascii_instr = "sltiu"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"sltiu\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_xori) begin\n"  , count_cycle); 
if (instr_xori) begin 
new_ascii_instr = "xori"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"xori\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_ori) begin\n"  , count_cycle); 
if (instr_ori) begin 
new_ascii_instr = "ori"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"ori\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_andi) begin\n"  , count_cycle); 
if (instr_andi) begin 
new_ascii_instr = "andi"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"andi\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_slli) begin\n"  , count_cycle); 
if (instr_slli) begin 
new_ascii_instr = "slli"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"slli\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_srli) begin\n"  , count_cycle); 
if (instr_srli) begin 
new_ascii_instr = "srli"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"srli\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_srai) begin\n"  , count_cycle); 
if (instr_srai) begin 
new_ascii_instr = "srai"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"srai\";\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :if (instr_add) begin\n"  , count_cycle); 
if (instr_add) begin 
new_ascii_instr = "add"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"add\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_sub) begin\n"  , count_cycle); 
if (instr_sub) begin 
new_ascii_instr = "sub"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"sub\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_sll) begin\n"  , count_cycle); 
if (instr_sll) begin 
new_ascii_instr = "sll"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"sll\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_slt) begin\n"  , count_cycle); 
if (instr_slt) begin 
new_ascii_instr = "slt"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"slt\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_sltu) begin\n"  , count_cycle); 
if (instr_sltu) begin 
new_ascii_instr = "sltu"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"sltu\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_xor) begin\n"  , count_cycle); 
if (instr_xor) begin 
new_ascii_instr = "xor"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"xor\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_srl) begin\n"  , count_cycle); 
if (instr_srl) begin 
new_ascii_instr = "srl"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"srl\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_sra) begin\n"  , count_cycle); 
if (instr_sra) begin 
new_ascii_instr = "sra"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"sra\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_or) begin\n"  , count_cycle); 
if (instr_or) begin 
new_ascii_instr = "or"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"or\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_and) begin\n"  , count_cycle); 
if (instr_and) begin 
new_ascii_instr = "and"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"and\";\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :if (instr_rdcycle) begin\n"  , count_cycle); 
if (instr_rdcycle) begin 
new_ascii_instr = "rdcycle"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"rdcycle\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_rdcycleh) begin\n"  , count_cycle); 
if (instr_rdcycleh) begin 
new_ascii_instr = "rdcycleh"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"rdcycleh\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_rdinstr) begin\n"  , count_cycle); 
if (instr_rdinstr) begin 
new_ascii_instr = "rdinstr"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"rdinstr\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_rdinstrh) begin\n"  , count_cycle); 
if (instr_rdinstrh) begin 
new_ascii_instr = "rdinstrh"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"rdinstrh\";\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :if (instr_getq) begin\n"  , count_cycle); 
if (instr_getq) begin 
new_ascii_instr = "getq"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"getq\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_setq) begin\n"  , count_cycle); 
if (instr_setq) begin 
new_ascii_instr = "setq"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"setq\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_retirq) begin\n"  , count_cycle); 
if (instr_retirq) begin 
new_ascii_instr = "retirq"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"retirq\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_maskirq) begin\n"  , count_cycle); 
if (instr_maskirq) begin 
new_ascii_instr = "maskirq"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"maskirq\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_waitirq) begin\n"  , count_cycle); 
if (instr_waitirq) begin 
new_ascii_instr = "waitirq"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"waitirq\";\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (instr_timer) begin\n"  , count_cycle); 
if (instr_timer) begin 
new_ascii_instr = "timer"; 
$fwrite(f,"%0d cycle :new_ascii_instr = \"timer\";\n"  , count_cycle); 
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
$fwrite(f,"%0d cycle :q_ascii_instr <= dbg_ascii_instr;\n"  , count_cycle); 
q_insn_imm <= dbg_insn_imm; 
$fwrite(f,"%0d cycle :q_insn_imm <= dbg_insn_imm;\n"  , count_cycle); 
q_insn_opcode <= dbg_insn_opcode; 
$fwrite(f,"%0d cycle :q_insn_opcode <= dbg_insn_opcode;\n"  , count_cycle); 
q_insn_rs1 <= dbg_insn_rs1; 
$fwrite(f,"%0d cycle :q_insn_rs1 <= dbg_insn_rs1;\n"  , count_cycle); 
q_insn_rs2 <= dbg_insn_rs2; 
$fwrite(f,"%0d cycle :q_insn_rs2 <= dbg_insn_rs2;\n"  , count_cycle); 
q_insn_rd <= dbg_insn_rd; 
$fwrite(f,"%0d cycle :q_insn_rd <= dbg_insn_rd;\n"  , count_cycle); 
dbg_next <= launch_next_insn; 
$fwrite(f,"%0d cycle :dbg_next <= launch_next_insn;\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :if (!resetn || trap) begin\n"  , count_cycle); 
$fwrite(f,"%0d cycle :else if (launch_next_insn) begin\n"  , count_cycle); 

if (!resetn || trap) begin 
dbg_valid_insn <= 0; 
$fwrite(f,"%0d cycle :dbg_valid_insn <= 0;\n"  , count_cycle); 
end 
else if (launch_next_insn) begin 
dbg_valid_insn <= 1; 
$fwrite(f,"%0d cycle :dbg_valid_insn <= 1;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (decoder_trigger_q) begin\n"  , count_cycle); 
if (decoder_trigger_q) begin 
cached_ascii_instr <= new_ascii_instr; 
$fwrite(f,"%0d cycle :cached_ascii_instr <= new_ascii_instr;\n"  , count_cycle); 
cached_insn_imm <= decoded_imm; 
$fwrite(f,"%0d cycle :cached_insn_imm <= decoded_imm;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :if (&next_insn_opcode[1:0]) begin\n"  , count_cycle); 
if (&next_insn_opcode[1:0]) begin 
cached_insn_opcode <= next_insn_opcode; 
$fwrite(f,"%0d cycle :cached_insn_opcode <= next_insn_opcode;\n"  , count_cycle); 
end 
else 
cached_insn_opcode <= {16'b0, next_insn_opcode[15:0]}; 
$fwrite(f,"%0d cycle :cached_insn_opcode <= {16\'b0, next_insn_opcode[15:0]};\n"  , count_cycle); 
cached_insn_rs1 <= decoded_rs1; 
$fwrite(f,"%0d cycle :cached_insn_rs1 <= decoded_rs1;\n"  , count_cycle); 
cached_insn_rs2 <= decoded_rs2; 
$fwrite(f,"%0d cycle :cached_insn_rs2 <= decoded_rs2;\n"  , count_cycle); 
cached_insn_rd <= decoded_rd; 
$fwrite(f,"%0d cycle :cached_insn_rd <= decoded_rd;\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :if (launch_next_insn) begin\n"  , count_cycle); 
if (launch_next_insn) begin 
dbg_insn_addr <= next_pc; 
$fwrite(f,"%0d cycle :dbg_insn_addr <= next_pc;\n"  , count_cycle); 
end 
end 
 
always @* begin 
dbg_ascii_instr = q_ascii_instr; 
$fwrite(f,"%0d cycle :dbg_ascii_instr = q_ascii_instr;\n"  , count_cycle); 
dbg_insn_imm = q_insn_imm; 
$fwrite(f,"%0d cycle :dbg_insn_imm = q_insn_imm;\n"  , count_cycle); 
dbg_insn_opcode = q_insn_opcode; 
$fwrite(f,"%0d cycle :dbg_insn_opcode = q_insn_opcode;\n"  , count_cycle); 
dbg_insn_rs1 = q_insn_rs1; 
$fwrite(f,"%0d cycle :dbg_insn_rs1 = q_insn_rs1;\n"  , count_cycle); 
dbg_insn_rs2 = q_insn_rs2; 
$fwrite(f,"%0d cycle :dbg_insn_rs2 = q_insn_rs2;\n"  , count_cycle); 
dbg_insn_rd = q_insn_rd; 
$fwrite(f,"%0d cycle :dbg_insn_rd = q_insn_rd;\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :if (dbg_next) begin\n"  , count_cycle); 
if (dbg_next) begin 
$fwrite(f,"%0d cycle :if (decoder_pseudo_trigger_q) begin\n"  , count_cycle); 
if (decoder_pseudo_trigger_q) begin 
dbg_ascii_instr = cached_ascii_instr; 
$fwrite(f,"%0d cycle :dbg_ascii_instr = cached_ascii_instr;\n"  , count_cycle); 
dbg_insn_imm = cached_insn_imm; 
$fwrite(f,"%0d cycle :dbg_insn_imm = cached_insn_imm;\n"  , count_cycle); 
dbg_insn_opcode = cached_insn_opcode; 
$fwrite(f,"%0d cycle :dbg_insn_opcode = cached_insn_opcode;\n"  , count_cycle); 
dbg_insn_rs1 = cached_insn_rs1; 
$fwrite(f,"%0d cycle :dbg_insn_rs1 = cached_insn_rs1;\n"  , count_cycle); 
dbg_insn_rs2 = cached_insn_rs2; 
$fwrite(f,"%0d cycle :dbg_insn_rs2 = cached_insn_rs2;\n"  , count_cycle); 
dbg_insn_rd = cached_insn_rd; 
$fwrite(f,"%0d cycle :dbg_insn_rd = cached_insn_rd;\n"  , count_cycle); 
end else begin 
dbg_ascii_instr = new_ascii_instr; 
$fwrite(f,"%0d cycle :dbg_ascii_instr = new_ascii_instr;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :if (&next_insn_opcode[1:0]) begin\n"  , count_cycle); 
if (&next_insn_opcode[1:0]) begin 
dbg_insn_opcode = next_insn_opcode; 
$fwrite(f,"%0d cycle :dbg_insn_opcode = next_insn_opcode;\n"  , count_cycle); 
end 
else 
dbg_insn_opcode = {16'b0, next_insn_opcode[15:0]}; 
$fwrite(f,"%0d cycle :dbg_insn_opcode = {16\'b0, next_insn_opcode[15:0]};\n"  , count_cycle); 
dbg_insn_imm = decoded_imm; 
$fwrite(f,"%0d cycle :dbg_insn_imm = decoded_imm;\n"  , count_cycle); 
dbg_insn_rs1 = decoded_rs1; 
$fwrite(f,"%0d cycle :dbg_insn_rs1 = decoded_rs1;\n"  , count_cycle); 
dbg_insn_rs2 = decoded_rs2; 
$fwrite(f,"%0d cycle :dbg_insn_rs2 = decoded_rs2;\n"  , count_cycle); 
dbg_insn_rd = decoded_rd; 
$fwrite(f,"%0d cycle :dbg_insn_rd = decoded_rd;\n"  , count_cycle); 
end 
end 
end 
 
`ifdef DEBUGASM 
always @(posedge clk) begin 
$fwrite(f,"%0d cycle :if (dbg_next) begin\n"  , count_cycle); 
if (dbg_next) begin 
$display("debugasm %x %x %s", dbg_insn_addr, dbg_insn_opcode, dbg_ascii_instr ? dbg_ascii_instr : "*"); 
end 
end 
`endif 
 
`ifdef DEBUG 
always @(posedge clk) begin 
$fwrite(f,"%0d cycle :if (dbg_next) begin\n"  , count_cycle); 
if (dbg_next) begin 
$fwrite(f,"%0d cycle :if (&dbg_insn_opcode[1:0]) begin\n"  , count_cycle); 
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
$fwrite(f,"%0d cycle :is_lui_auipc_jal <= |{instr_lui, instr_auipc, instr_jal};\n"  , count_cycle); 
is_lui_auipc_jal_jalr_addi_add_sub <= |{instr_lui, instr_auipc, instr_jal, instr_jalr, instr_addi, instr_add, instr_sub}; 
$fwrite(f,"%0d cycle :is_lui_auipc_jal_jalr_addi_add_sub <= |{instr_lui, instr_auipc, instr_jal, instr_jalr, instr_addi, instr_add, instr_sub};\n"  , count_cycle); 
is_slti_blt_slt <= |{instr_slti, instr_blt, instr_slt}; 
$fwrite(f,"%0d cycle :is_slti_blt_slt <= |{instr_slti, instr_blt, instr_slt};\n"  , count_cycle); 
is_sltiu_bltu_sltu <= |{instr_sltiu, instr_bltu, instr_sltu}; 
$fwrite(f,"%0d cycle :is_sltiu_bltu_sltu <= |{instr_sltiu, instr_bltu, instr_sltu};\n"  , count_cycle); 
is_lbu_lhu_lw <= |{instr_lbu, instr_lhu, instr_lw}; 
$fwrite(f,"%0d cycle :is_lbu_lhu_lw <= |{instr_lbu, instr_lhu, instr_lw};\n"  , count_cycle); 
is_compare <= |{is_beq_bne_blt_bge_bltu_bgeu, instr_slti, instr_slt, instr_sltiu, instr_sltu}; 
$fwrite(f,"%0d cycle :is_compare <= |{is_beq_bne_blt_bge_bltu_bgeu, instr_slti, instr_slt, instr_sltiu, instr_sltu};\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :if (mem_do_rinst && mem_done) begin\n"  , count_cycle); 
if (mem_do_rinst && mem_done) begin 
instr_lui     <= mem_rdata_latched[6:0] == 7'b0110111; 
$fwrite(f,"%0d cycle :instr_lui     <= mem_rdata_latched[6:0] == 7\'b0110111;\n"  , count_cycle); 
instr_auipc   <= mem_rdata_latched[6:0] == 7'b0010111; 
$fwrite(f,"%0d cycle :instr_auipc   <= mem_rdata_latched[6:0] == 7\'b0010111;\n"  , count_cycle); 
instr_jal     <= mem_rdata_latched[6:0] == 7'b1101111; 
$fwrite(f,"%0d cycle :instr_jal     <= mem_rdata_latched[6:0] == 7\'b1101111;\n"  , count_cycle); 
instr_jalr    <= mem_rdata_latched[6:0] == 7'b1100111 && mem_rdata_latched[14:12] == 3'b000; 
$fwrite(f,"%0d cycle :instr_jalr    <= mem_rdata_latched[6:0] == 7\'b1100111 && mem_rdata_latched[14:12] == 3\'b000;\n"  , count_cycle); 
instr_retirq  <= mem_rdata_latched[6:0] == 7'b0001011 && mem_rdata_latched[31:25] == 7'b0000010 && ENABLE_IRQ; 
$fwrite(f,"%0d cycle :instr_retirq  <= mem_rdata_latched[6:0] == 7\'b0001011 && mem_rdata_latched[31:25] == 7\'b0000010 && ENABLE_IRQ;\n"  , count_cycle); 
instr_waitirq <= mem_rdata_latched[6:0] == 7'b0001011 && mem_rdata_latched[31:25] == 7'b0000100 && ENABLE_IRQ; 
$fwrite(f,"%0d cycle :instr_waitirq <= mem_rdata_latched[6:0] == 7\'b0001011 && mem_rdata_latched[31:25] == 7\'b0000100 && ENABLE_IRQ;\n"  , count_cycle); 
 
is_beq_bne_blt_bge_bltu_bgeu <= mem_rdata_latched[6:0] == 7'b1100011; 
$fwrite(f,"%0d cycle :is_beq_bne_blt_bge_bltu_bgeu <= mem_rdata_latched[6:0] == 7\'b1100011;\n"  , count_cycle); 
is_lb_lh_lw_lbu_lhu          <= mem_rdata_latched[6:0] == 7'b0000011; 
$fwrite(f,"%0d cycle :is_lb_lh_lw_lbu_lhu          <= mem_rdata_latched[6:0] == 7\'b0000011;\n"  , count_cycle); 
is_sb_sh_sw                  <= mem_rdata_latched[6:0] == 7'b0100011; 
$fwrite(f,"%0d cycle :is_sb_sh_sw                  <= mem_rdata_latched[6:0] == 7\'b0100011;\n"  , count_cycle); 
is_alu_reg_imm               <= mem_rdata_latched[6:0] == 7'b0010011; 
$fwrite(f,"%0d cycle :is_alu_reg_imm               <= mem_rdata_latched[6:0] == 7\'b0010011;\n"  , count_cycle); 
is_alu_reg_reg               <= mem_rdata_latched[6:0] == 7'b0110011; 
$fwrite(f,"%0d cycle :is_alu_reg_reg               <= mem_rdata_latched[6:0] == 7\'b0110011;\n"  , count_cycle); 
 
{ decoded_imm_j[31:20], decoded_imm_j[10:1], decoded_imm_j[11], decoded_imm_j[19:12], decoded_imm_j[0] } <= $signed({mem_rdata_latched[31:12], 1'b0}); 
$fwrite(f,"%0d cycle :{ decoded_imm_j[31:20], decoded_imm_j[10:1], decoded_imm_j[11], decoded_imm_j[19:12], decoded_imm_j[0] } <= $signed({mem_rdata_latched[31:12], 1\'b0});\n"  , count_cycle); 
 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :decoded_rd <= mem_rdata_latched[11:7];\n"  , count_cycle); 
decoded_rs1 <= mem_rdata_latched[19:15]; 
$fwrite(f,"%0d cycle :decoded_rs1 <= mem_rdata_latched[19:15];\n"  , count_cycle); 
decoded_rs2 <= mem_rdata_latched[24:20]; 
$fwrite(f,"%0d cycle :decoded_rs2 <= mem_rdata_latched[24:20];\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :if (mem_rdata_latched[6:0] == 7\'b0001011 && mem_rdata_latched[31:25] == 7\'b0000000 && ENABLE_IRQ && ENABLE_IRQ_QREGS) begin\n"  , count_cycle); 
if (mem_rdata_latched[6:0] == 7'b0001011 && mem_rdata_latched[31:25] == 7'b0000000 && ENABLE_IRQ && ENABLE_IRQ_QREGS) begin 
decoded_rs1[regindex_bits-1] <= 1; // instr_getq 
$fwrite(f,"%0d cycle :decoded_rs1[regindex_bits-1] <= 1; // instr_getq\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :if (mem_rdata_latched[6:0] == 7\'b0001011 && mem_rdata_latched[31:25] == 7\'b0000010 && ENABLE_IRQ) begin\n"  , count_cycle); 
if (mem_rdata_latched[6:0] == 7'b0001011 && mem_rdata_latched[31:25] == 7'b0000010 && ENABLE_IRQ) begin 
decoded_rs1 <= ENABLE_IRQ_QREGS ? irqregs_offset : 3; // instr_retirq 
$fwrite(f,"%0d cycle :if =  ENABLE_IRQ_QREGS \n"  , count_cycle);
if ( ENABLE_IRQ_QREGS) begin
$fwrite(f,"%0d cycle :decoded_rs1= irqregs_offset ; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :decoded_rs1 = 3; \n"  , count_cycle);
end
end 
 
compressed_instr <= 0; 
$fwrite(f,"%0d cycle :compressed_instr <= 0;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :if (COMPRESSED_ISA && mem_rdata_latched[1:0] != 2\'b11) begin\n"  , count_cycle); 
if (COMPRESSED_ISA && mem_rdata_latched[1:0] != 2'b11) begin 
compressed_instr <= 1; 
$fwrite(f,"%0d cycle :compressed_instr <= 1;\n"  , count_cycle); 
decoded_rd <= 0; 
$fwrite(f,"%0d cycle :decoded_rd <= 0;\n"  , count_cycle); 
decoded_rs1 <= 0; 
$fwrite(f,"%0d cycle :decoded_rs1 <= 0;\n"  , count_cycle); 
decoded_rs2 <= 0; 
$fwrite(f,"%0d cycle :decoded_rs2 <= 0;\n"  , count_cycle); 
 
{ decoded_imm_j[31:11], decoded_imm_j[4], decoded_imm_j[9:8], decoded_imm_j[10], decoded_imm_j[6], 
decoded_imm_j[7], decoded_imm_j[3:1], decoded_imm_j[5], decoded_imm_j[0] } <= $signed({mem_rdata_latched[12:2], 1'b0}); 
$fwrite(f,"%0d cycle :decoded_imm_j[7], decoded_imm_j[3:1], decoded_imm_j[5], decoded_imm_j[0] } <= $signed({mem_rdata_latched[12:2], 1\'b0});\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :case (mem_rdata_latched[1:0])\n"  , count_cycle); 
case (mem_rdata_latched[1:0]) 
2'b00: begin // Quadrant 0 
$fwrite(f,"%0d cycle :case (mem_rdata_latched[15:13])\n"  , count_cycle); 
case (mem_rdata_latched[15:13]) 
3'b000: begin // C.ADDI4SPN 
is_alu_reg_imm <= |mem_rdata_latched[12:5]; 
$fwrite(f,"%0d cycle :is_alu_reg_imm <= |mem_rdata_latched[12:5];\n"  , count_cycle); 
decoded_rs1 <= 2; 
$fwrite(f,"%0d cycle :decoded_rs1 <= 2;\n"  , count_cycle); 
decoded_rd <= 8 + mem_rdata_latched[4:2]; 
$fwrite(f,"%0d cycle :decoded_rd <= 8 + mem_rdata_latched[4:2];\n"  , count_cycle); 
end 
3'b010: begin // C.LW 
is_lb_lh_lw_lbu_lhu <= 1; 
$fwrite(f,"%0d cycle :is_lb_lh_lw_lbu_lhu <= 1;\n"  , count_cycle); 
decoded_rs1 <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0d cycle :decoded_rs1 <= 8 + mem_rdata_latched[9:7];\n"  , count_cycle); 
decoded_rd <= 8 + mem_rdata_latched[4:2]; 
$fwrite(f,"%0d cycle :decoded_rd <= 8 + mem_rdata_latched[4:2];\n"  , count_cycle); 
end 
3'b110: begin // C.SW 
is_sb_sh_sw <= 1; 
$fwrite(f,"%0d cycle :is_sb_sh_sw <= 1;\n"  , count_cycle); 
decoded_rs1 <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0d cycle :decoded_rs1 <= 8 + mem_rdata_latched[9:7];\n"  , count_cycle); 
decoded_rs2 <= 8 + mem_rdata_latched[4:2]; 
$fwrite(f,"%0d cycle :decoded_rs2 <= 8 + mem_rdata_latched[4:2];\n"  , count_cycle); 
end 
endcase 
end 
2'b01: begin // Quadrant 1 
$fwrite(f,"%0d cycle :case (mem_rdata_latched[15:13])\n"  , count_cycle); 
case (mem_rdata_latched[15:13]) 
3'b000: begin // C.NOP / C.ADDI 
is_alu_reg_imm <= 1; 
$fwrite(f,"%0d cycle :is_alu_reg_imm <= 1;\n"  , count_cycle); 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :decoded_rd <= mem_rdata_latched[11:7];\n"  , count_cycle); 
decoded_rs1 <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :decoded_rs1 <= mem_rdata_latched[11:7];\n"  , count_cycle); 
end 
3'b001: begin // C.JAL 
instr_jal <= 1; 
$fwrite(f,"%0d cycle :instr_jal <= 1;\n"  , count_cycle); 
decoded_rd <= 1; 
$fwrite(f,"%0d cycle :decoded_rd <= 1;\n"  , count_cycle); 
end 
3'b 010: begin // C.LI 
is_alu_reg_imm <= 1; 
$fwrite(f,"%0d cycle :is_alu_reg_imm <= 1;\n"  , count_cycle); 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :decoded_rd <= mem_rdata_latched[11:7];\n"  , count_cycle); 
decoded_rs1 <= 0; 
$fwrite(f,"%0d cycle :decoded_rs1 <= 0;\n"  , count_cycle); 
end 
3'b 011: begin 
$fwrite(f,"%0d cycle :if (mem_rdata_latched[12] || mem_rdata_latched[6:2]) begin\n"  , count_cycle); 
if (mem_rdata_latched[12] || mem_rdata_latched[6:2]) begin 
$fwrite(f,"%0d cycle :if (mem_rdata_latched[11:7] == 2) begin // C.ADDI16SP\n"  , count_cycle); 
if (mem_rdata_latched[11:7] == 2) begin // C.ADDI16SP 
is_alu_reg_imm <= 1; 
$fwrite(f,"%0d cycle :is_alu_reg_imm <= 1;\n"  , count_cycle); 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :decoded_rd <= mem_rdata_latched[11:7];\n"  , count_cycle); 
decoded_rs1 <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :decoded_rs1 <= mem_rdata_latched[11:7];\n"  , count_cycle); 
end else begin // C.LUI 
instr_lui <= 1; 
$fwrite(f,"%0d cycle :instr_lui <= 1;\n"  , count_cycle); 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :decoded_rd <= mem_rdata_latched[11:7];\n"  , count_cycle); 
decoded_rs1 <= 0; 
$fwrite(f,"%0d cycle :decoded_rs1 <= 0;\n"  , count_cycle); 
end 
end 
end 
3'b100: begin 
$fwrite(f,"%0d cycle :if (!mem_rdata_latched[11] && !mem_rdata_latched[12]) begin // C.SRLI, C.SRAI\n"  , count_cycle); 
if (!mem_rdata_latched[11] && !mem_rdata_latched[12]) begin // C.SRLI, C.SRAI 
is_alu_reg_imm <= 1; 
$fwrite(f,"%0d cycle :is_alu_reg_imm <= 1;\n"  , count_cycle); 
decoded_rd <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0d cycle :decoded_rd <= 8 + mem_rdata_latched[9:7];\n"  , count_cycle); 
decoded_rs1 <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0d cycle :decoded_rs1 <= 8 + mem_rdata_latched[9:7];\n"  , count_cycle); 
decoded_rs2 <= {mem_rdata_latched[12], mem_rdata_latched[6:2]}; 
$fwrite(f,"%0d cycle :decoded_rs2 <= {mem_rdata_latched[12], mem_rdata_latched[6:2]};\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (mem_rdata_latched[11:10] == 2\'b10) begin // C.ANDI\n"  , count_cycle); 
if (mem_rdata_latched[11:10] == 2'b10) begin // C.ANDI 
is_alu_reg_imm <= 1; 
$fwrite(f,"%0d cycle :is_alu_reg_imm <= 1;\n"  , count_cycle); 
decoded_rd <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0d cycle :decoded_rd <= 8 + mem_rdata_latched[9:7];\n"  , count_cycle); 
decoded_rs1 <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0d cycle :decoded_rs1 <= 8 + mem_rdata_latched[9:7];\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (mem_rdata_latched[12:10] == 3\'b011) begin // C.SUB, C.XOR, C.OR, C.AND\n"  , count_cycle); 
if (mem_rdata_latched[12:10] == 3'b011) begin // C.SUB, C.XOR, C.OR, C.AND 
is_alu_reg_reg <= 1; 
$fwrite(f,"%0d cycle :is_alu_reg_reg <= 1;\n"  , count_cycle); 
decoded_rd <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0d cycle :decoded_rd <= 8 + mem_rdata_latched[9:7];\n"  , count_cycle); 
decoded_rs1 <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0d cycle :decoded_rs1 <= 8 + mem_rdata_latched[9:7];\n"  , count_cycle); 
decoded_rs2 <= 8 + mem_rdata_latched[4:2]; 
$fwrite(f,"%0d cycle :decoded_rs2 <= 8 + mem_rdata_latched[4:2];\n"  , count_cycle); 
end 
end 
3'b101: begin // C.J 
instr_jal <= 1; 
$fwrite(f,"%0d cycle :instr_jal <= 1;\n"  , count_cycle); 
end 
3'b110: begin // C.BEQZ 
is_beq_bne_blt_bge_bltu_bgeu <= 1; 
$fwrite(f,"%0d cycle :is_beq_bne_blt_bge_bltu_bgeu <= 1;\n"  , count_cycle); 
decoded_rs1 <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0d cycle :decoded_rs1 <= 8 + mem_rdata_latched[9:7];\n"  , count_cycle); 
decoded_rs2 <= 0; 
$fwrite(f,"%0d cycle :decoded_rs2 <= 0;\n"  , count_cycle); 
end 
3'b111: begin // C.BNEZ 
is_beq_bne_blt_bge_bltu_bgeu <= 1; 
$fwrite(f,"%0d cycle :is_beq_bne_blt_bge_bltu_bgeu <= 1;\n"  , count_cycle); 
decoded_rs1 <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0d cycle :decoded_rs1 <= 8 + mem_rdata_latched[9:7];\n"  , count_cycle); 
decoded_rs2 <= 0; 
$fwrite(f,"%0d cycle :decoded_rs2 <= 0;\n"  , count_cycle); 
end 
endcase 
end 
2'b10: begin // Quadrant 2 
$fwrite(f,"%0d cycle :case (mem_rdata_latched[15:13])\n"  , count_cycle); 
case (mem_rdata_latched[15:13]) 
3'b000: begin // C.SLLI 
$fwrite(f,"%0d cycle :if (!mem_rdata_latched[12]) begin\n"  , count_cycle); 
if (!mem_rdata_latched[12]) begin 
is_alu_reg_imm <= 1; 
$fwrite(f,"%0d cycle :is_alu_reg_imm <= 1;\n"  , count_cycle); 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :decoded_rd <= mem_rdata_latched[11:7];\n"  , count_cycle); 
decoded_rs1 <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :decoded_rs1 <= mem_rdata_latched[11:7];\n"  , count_cycle); 
decoded_rs2 <= {mem_rdata_latched[12], mem_rdata_latched[6:2]}; 
$fwrite(f,"%0d cycle :decoded_rs2 <= {mem_rdata_latched[12], mem_rdata_latched[6:2]};\n"  , count_cycle); 
end 
end 
3'b010: begin // C.LWSP 
$fwrite(f,"%0d cycle :if (mem_rdata_latched[11:7]) begin\n"  , count_cycle); 
if (mem_rdata_latched[11:7]) begin 
is_lb_lh_lw_lbu_lhu <= 1; 
$fwrite(f,"%0d cycle :is_lb_lh_lw_lbu_lhu <= 1;\n"  , count_cycle); 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :decoded_rd <= mem_rdata_latched[11:7];\n"  , count_cycle); 
decoded_rs1 <= 2; 
$fwrite(f,"%0d cycle :decoded_rs1 <= 2;\n"  , count_cycle); 
end 
end 
3'b100: begin 
$fwrite(f,"%0d cycle :if (mem_rdata_latched[12] == 0 && mem_rdata_latched[11:7] != 0 && mem_rdata_latched[6:2] == 0) begin // C.JR\n"  , count_cycle); 
if (mem_rdata_latched[12] == 0 && mem_rdata_latched[11:7] != 0 && mem_rdata_latched[6:2] == 0) begin // C.JR 
instr_jalr <= 1; 
$fwrite(f,"%0d cycle :instr_jalr <= 1;\n"  , count_cycle); 
decoded_rd <= 0; 
$fwrite(f,"%0d cycle :decoded_rd <= 0;\n"  , count_cycle); 
decoded_rs1 <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :decoded_rs1 <= mem_rdata_latched[11:7];\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (mem_rdata_latched[12] == 0 && mem_rdata_latched[6:2] != 0) begin // C.MV\n"  , count_cycle); 
if (mem_rdata_latched[12] == 0 && mem_rdata_latched[6:2] != 0) begin // C.MV 
is_alu_reg_reg <= 1; 
$fwrite(f,"%0d cycle :is_alu_reg_reg <= 1;\n"  , count_cycle); 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :decoded_rd <= mem_rdata_latched[11:7];\n"  , count_cycle); 
decoded_rs1 <= 0; 
$fwrite(f,"%0d cycle :decoded_rs1 <= 0;\n"  , count_cycle); 
decoded_rs2 <= mem_rdata_latched[6:2]; 
$fwrite(f,"%0d cycle :decoded_rs2 <= mem_rdata_latched[6:2];\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (mem_rdata_latched[12] != 0 && mem_rdata_latched[11:7] != 0 && mem_rdata_latched[6:2] == 0) begin // C.JALR\n"  , count_cycle); 
if (mem_rdata_latched[12] != 0 && mem_rdata_latched[11:7] != 0 && mem_rdata_latched[6:2] == 0) begin // C.JALR 
instr_jalr <= 1; 
$fwrite(f,"%0d cycle :instr_jalr <= 1;\n"  , count_cycle); 
decoded_rd <= 1; 
$fwrite(f,"%0d cycle :decoded_rd <= 1;\n"  , count_cycle); 
decoded_rs1 <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :decoded_rs1 <= mem_rdata_latched[11:7];\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (mem_rdata_latched[12] != 0 && mem_rdata_latched[6:2] != 0) begin // C.ADD\n"  , count_cycle); 
if (mem_rdata_latched[12] != 0 && mem_rdata_latched[6:2] != 0) begin // C.ADD 
is_alu_reg_reg <= 1; 
$fwrite(f,"%0d cycle :is_alu_reg_reg <= 1;\n"  , count_cycle); 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :decoded_rd <= mem_rdata_latched[11:7];\n"  , count_cycle); 
decoded_rs1 <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0d cycle :decoded_rs1 <= mem_rdata_latched[11:7];\n"  , count_cycle); 
decoded_rs2 <= mem_rdata_latched[6:2]; 
$fwrite(f,"%0d cycle :decoded_rs2 <= mem_rdata_latched[6:2];\n"  , count_cycle); 
end 
end 
3'b110: begin // C.SWSP 
is_sb_sh_sw <= 1; 
$fwrite(f,"%0d cycle :is_sb_sh_sw <= 1;\n"  , count_cycle); 
decoded_rs1 <= 2; 
$fwrite(f,"%0d cycle :decoded_rs1 <= 2;\n"  , count_cycle); 
decoded_rs2 <= mem_rdata_latched[6:2]; 
$fwrite(f,"%0d cycle :decoded_rs2 <= mem_rdata_latched[6:2];\n"  , count_cycle); 
end 
endcase 
end 
endcase 
end 
end 
 
$fwrite(f,"%0d cycle :if (decoder_trigger && !decoder_pseudo_trigger) begin\n"  , count_cycle); 
if (decoder_trigger && !decoder_pseudo_trigger) begin 
pcpi_insn <= WITH_PCPI ? mem_rdata_q : 'bx; 
$fwrite(f,"%0d cycle :if =  WITH_PCPI \n"  , count_cycle);
if ( WITH_PCPI) begin
$fwrite(f,"%0d cycle :pcpi_insn= mem_rdata_q ; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :pcpi_insn = 'bx; \n"  , count_cycle);
end 
instr_beq   <= is_beq_bne_blt_bge_bltu_bgeu && mem_rdata_q[14:12] == 3'b000; 
$fwrite(f,"%0d cycle :instr_beq   <= is_beq_bne_blt_bge_bltu_bgeu && mem_rdata_q[14:12] == 3\'b000;\n"  , count_cycle); 
instr_bne   <= is_beq_bne_blt_bge_bltu_bgeu && mem_rdata_q[14:12] == 3'b001; 
$fwrite(f,"%0d cycle :instr_bne   <= is_beq_bne_blt_bge_bltu_bgeu && mem_rdata_q[14:12] == 3\'b001;\n"  , count_cycle); 
instr_blt   <= is_beq_bne_blt_bge_bltu_bgeu && mem_rdata_q[14:12] == 3'b100; 
$fwrite(f,"%0d cycle :instr_blt   <= is_beq_bne_blt_bge_bltu_bgeu && mem_rdata_q[14:12] == 3\'b100;\n"  , count_cycle); 
instr_bge   <= is_beq_bne_blt_bge_bltu_bgeu && mem_rdata_q[14:12] == 3'b101; 
$fwrite(f,"%0d cycle :instr_bge   <= is_beq_bne_blt_bge_bltu_bgeu && mem_rdata_q[14:12] == 3\'b101;\n"  , count_cycle); 
instr_bltu  <= is_beq_bne_blt_bge_bltu_bgeu && mem_rdata_q[14:12] == 3'b110; 
$fwrite(f,"%0d cycle :instr_bltu  <= is_beq_bne_blt_bge_bltu_bgeu && mem_rdata_q[14:12] == 3\'b110;\n"  , count_cycle); 
instr_bgeu  <= is_beq_bne_blt_bge_bltu_bgeu && mem_rdata_q[14:12] == 3'b111; 
$fwrite(f,"%0d cycle :instr_bgeu  <= is_beq_bne_blt_bge_bltu_bgeu && mem_rdata_q[14:12] == 3\'b111;\n"  , count_cycle); 
 
instr_lb    <= is_lb_lh_lw_lbu_lhu && mem_rdata_q[14:12] == 3'b000; 
$fwrite(f,"%0d cycle :instr_lb    <= is_lb_lh_lw_lbu_lhu && mem_rdata_q[14:12] == 3\'b000;\n"  , count_cycle); 
instr_lh    <= is_lb_lh_lw_lbu_lhu && mem_rdata_q[14:12] == 3'b001; 
$fwrite(f,"%0d cycle :instr_lh    <= is_lb_lh_lw_lbu_lhu && mem_rdata_q[14:12] == 3\'b001;\n"  , count_cycle); 
instr_lw    <= is_lb_lh_lw_lbu_lhu && mem_rdata_q[14:12] == 3'b010; 
$fwrite(f,"%0d cycle :instr_lw    <= is_lb_lh_lw_lbu_lhu && mem_rdata_q[14:12] == 3\'b010;\n"  , count_cycle); 
instr_lbu   <= is_lb_lh_lw_lbu_lhu && mem_rdata_q[14:12] == 3'b100; 
$fwrite(f,"%0d cycle :instr_lbu   <= is_lb_lh_lw_lbu_lhu && mem_rdata_q[14:12] == 3\'b100;\n"  , count_cycle); 
instr_lhu   <= is_lb_lh_lw_lbu_lhu && mem_rdata_q[14:12] == 3'b101; 
$fwrite(f,"%0d cycle :instr_lhu   <= is_lb_lh_lw_lbu_lhu && mem_rdata_q[14:12] == 3\'b101;\n"  , count_cycle); 
 
instr_sb    <= is_sb_sh_sw && mem_rdata_q[14:12] == 3'b000; 
$fwrite(f,"%0d cycle :instr_sb    <= is_sb_sh_sw && mem_rdata_q[14:12] == 3\'b000;\n"  , count_cycle); 
instr_sh    <= is_sb_sh_sw && mem_rdata_q[14:12] == 3'b001; 
$fwrite(f,"%0d cycle :instr_sh    <= is_sb_sh_sw && mem_rdata_q[14:12] == 3\'b001;\n"  , count_cycle); 
instr_sw    <= is_sb_sh_sw && mem_rdata_q[14:12] == 3'b010; 
$fwrite(f,"%0d cycle :instr_sw    <= is_sb_sh_sw && mem_rdata_q[14:12] == 3\'b010;\n"  , count_cycle); 
 
instr_addi  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b000; 
$fwrite(f,"%0d cycle :instr_addi  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3\'b000;\n"  , count_cycle); 
instr_slti  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b010; 
$fwrite(f,"%0d cycle :instr_slti  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3\'b010;\n"  , count_cycle); 
instr_sltiu <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b011; 
$fwrite(f,"%0d cycle :instr_sltiu <= is_alu_reg_imm && mem_rdata_q[14:12] == 3\'b011;\n"  , count_cycle); 
instr_xori  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b100; 
$fwrite(f,"%0d cycle :instr_xori  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3\'b100;\n"  , count_cycle); 
instr_ori   <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b110; 
$fwrite(f,"%0d cycle :instr_ori   <= is_alu_reg_imm && mem_rdata_q[14:12] == 3\'b110;\n"  , count_cycle); 
instr_andi  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b111; 
$fwrite(f,"%0d cycle :instr_andi  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3\'b111;\n"  , count_cycle); 
 
instr_slli  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b001 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0d cycle :instr_slli  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3\'b001 && mem_rdata_q[31:25] == 7\'b0000000;\n"  , count_cycle); 
instr_srli  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b101 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0d cycle :instr_srli  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3\'b101 && mem_rdata_q[31:25] == 7\'b0000000;\n"  , count_cycle); 
instr_srai  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b101 && mem_rdata_q[31:25] == 7'b0100000; 
$fwrite(f,"%0d cycle :instr_srai  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3\'b101 && mem_rdata_q[31:25] == 7\'b0100000;\n"  , count_cycle); 
 
instr_add   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b000 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0d cycle :instr_add   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3\'b000 && mem_rdata_q[31:25] == 7\'b0000000;\n"  , count_cycle); 
instr_sub   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b000 && mem_rdata_q[31:25] == 7'b0100000; 
$fwrite(f,"%0d cycle :instr_sub   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3\'b000 && mem_rdata_q[31:25] == 7\'b0100000;\n"  , count_cycle); 
instr_sll   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b001 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0d cycle :instr_sll   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3\'b001 && mem_rdata_q[31:25] == 7\'b0000000;\n"  , count_cycle); 
instr_slt   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b010 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0d cycle :instr_slt   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3\'b010 && mem_rdata_q[31:25] == 7\'b0000000;\n"  , count_cycle); 
instr_sltu  <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b011 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0d cycle :instr_sltu  <= is_alu_reg_reg && mem_rdata_q[14:12] == 3\'b011 && mem_rdata_q[31:25] == 7\'b0000000;\n"  , count_cycle); 
instr_xor   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b100 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0d cycle :instr_xor   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3\'b100 && mem_rdata_q[31:25] == 7\'b0000000;\n"  , count_cycle); 
instr_srl   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b101 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0d cycle :instr_srl   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3\'b101 && mem_rdata_q[31:25] == 7\'b0000000;\n"  , count_cycle); 
instr_sra   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b101 && mem_rdata_q[31:25] == 7'b0100000; 
$fwrite(f,"%0d cycle :instr_sra   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3\'b101 && mem_rdata_q[31:25] == 7\'b0100000;\n"  , count_cycle); 
instr_or    <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b110 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0d cycle :instr_or    <= is_alu_reg_reg && mem_rdata_q[14:12] == 3\'b110 && mem_rdata_q[31:25] == 7\'b0000000;\n"  , count_cycle); 
instr_and   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b111 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0d cycle :instr_and   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3\'b111 && mem_rdata_q[31:25] == 7\'b0000000;\n"  , count_cycle); 
 
instr_rdcycle  <= ((mem_rdata_q[6:0] == 7'b1110011 && mem_rdata_q[31:12] == 'b11000000000000000010) ||(mem_rdata_q[6:0] == 7'b1110011 && mem_rdata_q[31:12] == 'b11000000000100000010)) && ENABLE_COUNTERS; 
$fwrite(f,"%0d cycle :instr_rdcycle  <= ((mem_rdata_q[6:0] == 7\'b1110011 && mem_rdata_q[31:12] == \'b11000000000000000010) ||(mem_rdata_q[6:0] == 7\'b1110011 && mem_rdata_q[31:12] == \'b11000000000100000010)) && ENABLE_COUNTERS;\n"  , count_cycle); 
instr_rdcycleh <= ((mem_rdata_q[6:0] == 7'b1110011 && mem_rdata_q[31:12] == 'b11001000000000000010) ||(mem_rdata_q[6:0] == 7'b1110011 && mem_rdata_q[31:12] == 'b11001000000100000010)) && ENABLE_COUNTERS && ENABLE_COUNTERS64; 
$fwrite(f,"%0d cycle :instr_rdcycleh <= ((mem_rdata_q[6:0] == 7\'b1110011 && mem_rdata_q[31:12] == \'b11001000000000000010) ||(mem_rdata_q[6:0] == 7\'b1110011 && mem_rdata_q[31:12] == \'b11001000000100000010)) && ENABLE_COUNTERS && ENABLE_COUNTERS64;\n"  , count_cycle); 
instr_rdinstr  <=  (mem_rdata_q[6:0] == 7'b1110011 && mem_rdata_q[31:12] == 'b11000000001000000010) && ENABLE_COUNTERS; 
$fwrite(f,"%0d cycle :instr_rdinstr  <=  (mem_rdata_q[6:0] == 7\'b1110011 && mem_rdata_q[31:12] == \'b11000000001000000010) && ENABLE_COUNTERS;\n"  , count_cycle); 
instr_rdinstrh <=  (mem_rdata_q[6:0] == 7'b1110011 && mem_rdata_q[31:12] == 'b11001000001000000010) && ENABLE_COUNTERS && ENABLE_COUNTERS64; 
$fwrite(f,"%0d cycle :instr_rdinstrh <=  (mem_rdata_q[6:0] == 7\'b1110011 && mem_rdata_q[31:12] == \'b11001000001000000010) && ENABLE_COUNTERS && ENABLE_COUNTERS64;\n"  , count_cycle); 
 
instr_ecall_ebreak <= ((mem_rdata_q[6:0] == 7'b1110011 && !mem_rdata_q[31:21] && !mem_rdata_q[19:7]) ||(COMPRESSED_ISA && mem_rdata_q[15:0] == 16'h9002)); 
$fwrite(f,"%0d cycle :instr_ecall_ebreak <= ((mem_rdata_q[6:0] == 7\'b1110011 && !mem_rdata_q[31:21] && !mem_rdata_q[19:7]) ||(COMPRESSED_ISA && mem_rdata_q[15:0] == 16\'h9002));\n"  , count_cycle); 
 
instr_getq    <= mem_rdata_q[6:0] == 7'b0001011 && mem_rdata_q[31:25] == 7'b0000000 && ENABLE_IRQ && ENABLE_IRQ_QREGS; 
$fwrite(f,"%0d cycle :instr_getq    <= mem_rdata_q[6:0] == 7\'b0001011 && mem_rdata_q[31:25] == 7\'b0000000 && ENABLE_IRQ && ENABLE_IRQ_QREGS;\n"  , count_cycle); 
instr_setq    <= mem_rdata_q[6:0] == 7'b0001011 && mem_rdata_q[31:25] == 7'b0000001 && ENABLE_IRQ && ENABLE_IRQ_QREGS; 
$fwrite(f,"%0d cycle :instr_setq    <= mem_rdata_q[6:0] == 7\'b0001011 && mem_rdata_q[31:25] == 7\'b0000001 && ENABLE_IRQ && ENABLE_IRQ_QREGS;\n"  , count_cycle); 
instr_maskirq <= mem_rdata_q[6:0] == 7'b0001011 && mem_rdata_q[31:25] == 7'b0000011 && ENABLE_IRQ; 
$fwrite(f,"%0d cycle :instr_maskirq <= mem_rdata_q[6:0] == 7\'b0001011 && mem_rdata_q[31:25] == 7\'b0000011 && ENABLE_IRQ;\n"  , count_cycle); 
instr_timer   <= mem_rdata_q[6:0] == 7'b0001011 && mem_rdata_q[31:25] == 7'b0000101 && ENABLE_IRQ && ENABLE_IRQ_TIMER; 
$fwrite(f,"%0d cycle :instr_timer   <= mem_rdata_q[6:0] == 7\'b0001011 && mem_rdata_q[31:25] == 7\'b0000101 && ENABLE_IRQ && ENABLE_IRQ_TIMER;\n"  , count_cycle); 
 
is_slli_srli_srai <= is_alu_reg_imm && |{mem_rdata_q[14:12] == 3'b001 && mem_rdata_q[31:25] == 7'b0000000,mem_rdata_q[14:12] == 3'b101 && mem_rdata_q[31:25] == 7'b0000000,mem_rdata_q[14:12] == 3'b101 && mem_rdata_q[31:25] == 7'b0100000}; 
$fwrite(f,"%0d cycle :is_slli_srli_srai <= is_alu_reg_imm && |{mem_rdata_q[14:12] == 3\'b001 && mem_rdata_q[31:25] == 7\'b0000000,mem_rdata_q[14:12] == 3\'b101 && mem_rdata_q[31:25] == 7\'b0000000,mem_rdata_q[14:12] == 3\'b101 && mem_rdata_q[31:25] == 7\'b0100000};\n"  , count_cycle); 
 
is_jalr_addi_slti_sltiu_xori_ori_andi <= instr_jalr || is_alu_reg_imm && |{mem_rdata_q[14:12] == 3'b000,mem_rdata_q[14:12] == 3'b010,mem_rdata_q[14:12] == 3'b011,mem_rdata_q[14:12] == 3'b100,mem_rdata_q[14:12] == 3'b110,mem_rdata_q[14:12] == 3'b111}; 
$fwrite(f,"%0d cycle :is_jalr_addi_slti_sltiu_xori_ori_andi <= instr_jalr || is_alu_reg_imm && |{mem_rdata_q[14:12] == 3\'b000,mem_rdata_q[14:12] == 3\'b010,mem_rdata_q[14:12] == 3\'b011,mem_rdata_q[14:12] == 3\'b100,mem_rdata_q[14:12] == 3\'b110,mem_rdata_q[14:12] == 3\'b111};\n"  , count_cycle); 
 
is_sll_srl_sra <= is_alu_reg_reg && |{mem_rdata_q[14:12] == 3'b001 && mem_rdata_q[31:25] == 7'b0000000,mem_rdata_q[14:12] == 3'b101 && mem_rdata_q[31:25] == 7'b0000000,mem_rdata_q[14:12] == 3'b101 && mem_rdata_q[31:25] == 7'b0100000}; 
$fwrite(f,"%0d cycle :is_sll_srl_sra <= is_alu_reg_reg && |{mem_rdata_q[14:12] == 3\'b001 && mem_rdata_q[31:25] == 7\'b0000000,mem_rdata_q[14:12] == 3\'b101 && mem_rdata_q[31:25] == 7\'b0000000,mem_rdata_q[14:12] == 3\'b101 && mem_rdata_q[31:25] == 7\'b0100000};\n"  , count_cycle); 
 
is_lui_auipc_jal_jalr_addi_add_sub <= 0; 
$fwrite(f,"%0d cycle :is_lui_auipc_jal_jalr_addi_add_sub <= 0;\n"  , count_cycle); 
is_compare <= 0; 
$fwrite(f,"%0d cycle :is_compare <= 0;\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :(* parallel_case *)\n"  , count_cycle); 
(* parallel_case *) 
$fwrite(f,"%0d cycle :case (1\'b1)\n"  , count_cycle); 
case (1'b1) 
instr_jal: begin 
decoded_imm <= decoded_imm_j; 
$fwrite(f,"%0d cycle :decoded_imm <= decoded_imm_j;\n"  , count_cycle); 
end 
|{instr_lui, instr_auipc}: begin 
decoded_imm <= mem_rdata_q[31:12] << 12; 
$fwrite(f,"%0d cycle :decoded_imm <= mem_rdata_q[31:12] << 12;\n"  , count_cycle); 
end 
|{instr_jalr, is_lb_lh_lw_lbu_lhu, is_alu_reg_imm}: begin 
decoded_imm <= $signed(mem_rdata_q[31:20]); 
$fwrite(f,"%0d cycle :decoded_imm <= $signed(mem_rdata_q[31:20]);\n"  , count_cycle); 
end 
is_beq_bne_blt_bge_bltu_bgeu: begin 
decoded_imm <= $signed({mem_rdata_q[31], mem_rdata_q[7], mem_rdata_q[30:25], mem_rdata_q[11:8], 1'b0}); 
$fwrite(f,"%0d cycle :decoded_imm <= $signed({mem_rdata_q[31], mem_rdata_q[7], mem_rdata_q[30:25], mem_rdata_q[11:8], 1\'b0});\n"  , count_cycle); 
end 
is_sb_sh_sw: begin 
decoded_imm <= $signed({mem_rdata_q[31:25], mem_rdata_q[11:7]}); 
$fwrite(f,"%0d cycle :decoded_imm <= $signed({mem_rdata_q[31:25], mem_rdata_q[11:7]});\n"  , count_cycle); 
end 
default: begin 
decoded_imm <= 1'bx; 
$fwrite(f,"%0d cycle :decoded_imm <= 1\'bx;\n"  , count_cycle); 
end 
endcase 
end 
 
$fwrite(f,"%0d cycle :if (!resetn) begin\n"  , count_cycle); 
if (!resetn) begin 
is_beq_bne_blt_bge_bltu_bgeu <= 0; 
$fwrite(f,"%0d cycle :is_beq_bne_blt_bge_bltu_bgeu <= 0;\n"  , count_cycle); 
is_compare <= 0; 
$fwrite(f,"%0d cycle :is_compare <= 0;\n"  , count_cycle); 
 
instr_beq   <= 0; 
$fwrite(f,"%0d cycle :instr_beq   <= 0;\n"  , count_cycle); 
instr_bne   <= 0; 
$fwrite(f,"%0d cycle :instr_bne   <= 0;\n"  , count_cycle); 
instr_blt   <= 0; 
$fwrite(f,"%0d cycle :instr_blt   <= 0;\n"  , count_cycle); 
instr_bge   <= 0; 
$fwrite(f,"%0d cycle :instr_bge   <= 0;\n"  , count_cycle); 
instr_bltu  <= 0; 
$fwrite(f,"%0d cycle :instr_bltu  <= 0;\n"  , count_cycle); 
instr_bgeu  <= 0; 
$fwrite(f,"%0d cycle :instr_bgeu  <= 0;\n"  , count_cycle); 
 
instr_addi  <= 0; 
$fwrite(f,"%0d cycle :instr_addi  <= 0;\n"  , count_cycle); 
instr_slti  <= 0; 
$fwrite(f,"%0d cycle :instr_slti  <= 0;\n"  , count_cycle); 
instr_sltiu <= 0; 
$fwrite(f,"%0d cycle :instr_sltiu <= 0;\n"  , count_cycle); 
instr_xori  <= 0; 
$fwrite(f,"%0d cycle :instr_xori  <= 0;\n"  , count_cycle); 
instr_ori   <= 0; 
$fwrite(f,"%0d cycle :instr_ori   <= 0;\n"  , count_cycle); 
instr_andi  <= 0; 
$fwrite(f,"%0d cycle :instr_andi  <= 0;\n"  , count_cycle); 
 
instr_add   <= 0; 
$fwrite(f,"%0d cycle :instr_add   <= 0;\n"  , count_cycle); 
instr_sub   <= 0; 
$fwrite(f,"%0d cycle :instr_sub   <= 0;\n"  , count_cycle); 
instr_sll   <= 0; 
$fwrite(f,"%0d cycle :instr_sll   <= 0;\n"  , count_cycle); 
instr_slt   <= 0; 
$fwrite(f,"%0d cycle :instr_slt   <= 0;\n"  , count_cycle); 
instr_sltu  <= 0; 
$fwrite(f,"%0d cycle :instr_sltu  <= 0;\n"  , count_cycle); 
instr_xor   <= 0; 
$fwrite(f,"%0d cycle :instr_xor   <= 0;\n"  , count_cycle); 
instr_srl   <= 0; 
$fwrite(f,"%0d cycle :instr_srl   <= 0;\n"  , count_cycle); 
instr_sra   <= 0; 
$fwrite(f,"%0d cycle :instr_sra   <= 0;\n"  , count_cycle); 
instr_or    <= 0; 
$fwrite(f,"%0d cycle :instr_or    <= 0;\n"  , count_cycle); 
instr_and   <= 0; 
$fwrite(f,"%0d cycle :instr_and   <= 0;\n"  , count_cycle); 
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
$fwrite(f,"%0d cycle :if =  latched_store && latched_branch \n"  , count_cycle);
if ( latched_store && latched_branch) begin
$fwrite(f,"%0d cycle :next_pc= reg_out & ~1  ; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :next_pc = reg_next_pc; \n"  , count_cycle);
end 
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
$fwrite(f,"%0d cycle :if =  instr_sub \n"  , count_cycle);
if ( instr_sub) begin
$fwrite(f,"%0d cycle :alu_add_sub= reg_op1 - reg_op2 ; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :alu_add_sub = reg_op1 + reg_op2; \n"  , count_cycle);
end 
alu_eq <= reg_op1 == reg_op2; 
$fwrite(f,"%0d cycle :alu_eq <= reg_op1 == reg_op2;\n"  , count_cycle); 
alu_lts <= $signed(reg_op1) < $signed(reg_op2); 
$fwrite(f,"%0d cycle :alu_lts <= $signed(reg_op1) < $signed(reg_op2);\n"  , count_cycle); 
alu_ltu <= reg_op1 < reg_op2; 
$fwrite(f,"%0d cycle :alu_ltu <= reg_op1 < reg_op2;\n"  , count_cycle); 
alu_shl <= reg_op1 << reg_op2[4:0]; 
$fwrite(f,"%0d cycle :alu_shl <= reg_op1 << reg_op2[4:0];\n"  , count_cycle); 
alu_shr <= $signed({instr_sra || instr_srai ? reg_op1[31] : 1'b0, reg_op1}) >>> reg_op2[4:0]; 
$fwrite(f,"%0d cycle :if =  instr_sra || instr_srai  \n"  , count_cycle);
if ( instr_sra || instr_srai ) begin
$fwrite(f,"%0d cycle :alu_shr= {reg_op1[31], reg_op1}>>> reg_op2[4:0]; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :alu_shr = {reg_op1[31], 1'b0}>>> reg_op2[4:0]; \n"  , count_cycle);
end 
end 
end else begin 
always @* begin 
alu_add_sub = instr_sub ? reg_op1 - reg_op2 : reg_op1 + reg_op2; 
$fwrite(f,"%0d cycle :if =  instr_sub  \n"  , count_cycle);
if ( instr_sub ) begin
$fwrite(f,"%0d cycle :alu_add_sub= reg_op1 - reg_op2; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :alu_add_sub = {reg_op1[31], 1'b0}>>> reg_op2[4:0]; \n"  , count_cycle);
end 
alu_eq = reg_op1 == reg_op2; 
$fwrite(f,"%0d cycle :alu_eq = reg_op1 == reg_op2;\n"  , count_cycle); 
alu_lts = $signed(reg_op1) < $signed(reg_op2); 
$fwrite(f,"%0d cycle :alu_lts = $signed(reg_op1) < $signed(reg_op2);\n"  , count_cycle); 
alu_ltu = reg_op1 < reg_op2; 
$fwrite(f,"%0d cycle :alu_ltu = reg_op1 < reg_op2;\n"  , count_cycle); 
alu_shl = reg_op1 << reg_op2[4:0]; 
$fwrite(f,"%0d cycle :alu_shl = reg_op1 << reg_op2[4:0];\n"  , count_cycle); 
alu_shr = $signed({instr_sra || instr_srai ? reg_op1[31] : 1'b0, reg_op1}) >>> reg_op2[4:0]; 
$fwrite(f,"%0d cycle :if =  instr_sra || instr_srai  \n"  , count_cycle);
if ( instr_sra || instr_srai ) begin
$fwrite(f,"%0d cycle :alu_shr = {reg_op1[31] , reg_op1}) >>> reg_op2[4:0]; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :alu_shr =  {reg_op1[31] , 1'b0}) >>> reg_op2[4:0]; \n"  , count_cycle);
end 
end 
end endgenerate 
 
always @* begin 
alu_out_0 = 'bx; 
$fwrite(f,"%0d cycle :alu_out_0 = \'bx;\n"  , count_cycle); 
(* parallel_case, full_case *) 
case (1'b1) 
instr_beq: begin 
alu_out_0 = alu_eq; 
$fwrite(f,"%0d cycle :alu_out_0 = alu_eq;\n"  , count_cycle); 
end 
instr_bne: begin 
alu_out_0 = !alu_eq; 
$fwrite(f,"%0d cycle :alu_out_0 = !alu_eq;\n"  , count_cycle); 
end 
instr_bge: begin 
alu_out_0 = !alu_lts; 
$fwrite(f,"%0d cycle :alu_out_0 = !alu_lts;\n"  , count_cycle); 
end 
instr_bgeu: begin 
alu_out_0 = !alu_ltu; 
$fwrite(f,"%0d cycle :alu_out_0 = !alu_ltu;\n"  , count_cycle); 
end 
is_slti_blt_slt && (!TWO_CYCLE_COMPARE || !{instr_beq,instr_bne,instr_bge,instr_bgeu}): begin 
alu_out_0 = alu_lts; 
$fwrite(f,"%0d cycle :alu_out_0 = alu_lts;\n"  , count_cycle); 
end 
is_sltiu_bltu_sltu && (!TWO_CYCLE_COMPARE || !{instr_beq,instr_bne,instr_bge,instr_bgeu}): begin 
alu_out_0 = alu_ltu; 
$fwrite(f,"%0d cycle :alu_out_0 = alu_ltu;\n"  , count_cycle); 
end 
endcase 
 
alu_out = 'bx; 
$fwrite(f,"%0d cycle :alu_out = \'bx;\n"  , count_cycle); 
(* parallel_case, full_case *) 
case (1'b1) 
is_lui_auipc_jal_jalr_addi_add_sub: begin 
alu_out = alu_add_sub; 
$fwrite(f,"%0d cycle :alu_out = alu_add_sub;\n"  , count_cycle); 
end 
is_compare: begin 
alu_out = alu_out_0; 
$fwrite(f,"%0d cycle :alu_out = alu_out_0;\n"  , count_cycle); 
end 
instr_xori || instr_xor: begin 
alu_out = reg_op1 ^ reg_op2; 
$fwrite(f,"%0d cycle :alu_out = reg_op1 ^ reg_op2;\n"  , count_cycle); 
end 
instr_ori || instr_or: begin 
alu_out = reg_op1 | reg_op2; 
$fwrite(f,"%0d cycle :alu_out = reg_op1 | reg_op2;\n"  , count_cycle); 
end 
instr_andi || instr_and: begin 
alu_out = reg_op1 & reg_op2; 
$fwrite(f,"%0d cycle :alu_out = reg_op1 & reg_op2;\n"  , count_cycle); 
end 
BARREL_SHIFTER && (instr_sll || instr_slli): begin 
alu_out = alu_shl; 
$fwrite(f,"%0d cycle :alu_out = alu_shl;\n"  , count_cycle); 
end 
BARREL_SHIFTER && (instr_srl || instr_srli || instr_sra || instr_srai): begin 
alu_out = alu_shr; 
$fwrite(f,"%0d cycle :alu_out = alu_shr;\n"  , count_cycle); 
end 
endcase 
 
`ifdef RISCV_FORMAL_BLACKBOX_ALU 
alu_out_0 = $anyseq; 
$fwrite(f,"%0d cycle :alu_out_0 = $anyseq;\n"  , count_cycle); 
alu_out = $anyseq; 
$fwrite(f,"%0d cycle :alu_out = $anyseq;\n"  , count_cycle); 
`endif 
end 
 
reg clear_prefetched_high_word_q; 
always @(posedge clk) begin 
clear_prefetched_high_word_q <= clear_prefetched_high_word; 
$fwrite(f,"%0d cycle :clear_prefetched_high_word_q <= clear_prefetched_high_word;\n"  , count_cycle); 
end 
 
always @* begin 
clear_prefetched_high_word = clear_prefetched_high_word_q; 
$fwrite(f,"%0d cycle :clear_prefetched_high_word = clear_prefetched_high_word_q;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :if (!prefetched_high_word) begin\n"  , count_cycle); 
if (!prefetched_high_word) begin 
clear_prefetched_high_word = 0; 
$fwrite(f,"%0d cycle :clear_prefetched_high_word = 0;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (latched_branch || irq_state || !resetn) begin\n"  , count_cycle); 
if (latched_branch || irq_state || !resetn) begin 
clear_prefetched_high_word = COMPRESSED_ISA; 
$fwrite(f,"%0d cycle :clear_prefetched_high_word = COMPRESSED_ISA;\n"  , count_cycle); 
end 
end 
 
reg cpuregs_write; 
reg [31:0] cpuregs_wrdata; 
reg [31:0] cpuregs_rs1; 
reg [31:0] cpuregs_rs2; 
reg [regindex_bits-1:0] decoded_rs; 
 
always @* begin 
cpuregs_write = 0; 
$fwrite(f,"%0d cycle :cpuregs_write = 0;\n"  , count_cycle); 
cpuregs_wrdata = 'bx; 
$fwrite(f,"%0d cycle :cpuregs_wrdata = \'bx;\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :if (cpu_state == cpu_state_fetch) begin\n"  , count_cycle); 
if (cpu_state == cpu_state_fetch) begin 
(* parallel_case *) 
case (1'b1) 
latched_branch: begin 
cpuregs_wrdata = reg_pc + (latched_compr ? 2 : 4); 
$fwrite(f,"%0d cycle :if =  latched_compr \n"  , count_cycle);
if ( latched_compr) begin
$fwrite(f,"%0d cycle :cpuregs_wrdata = reg_pc + 2; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :cpuregs_wrdata =  reg_pc + 4; \n"  , count_cycle);
end 
cpuregs_write = 1; 
$fwrite(f,"%0d cycle :cpuregs_write = 1;\n"  , count_cycle); 
end 
latched_store && !latched_branch: begin 
cpuregs_wrdata = latched_stalu ? alu_out_q : reg_out; 
$fwrite(f,"%0d cycle :if =  latched_stalu \n"  , count_cycle);
if ( latched_stalu) begin
$fwrite(f,"%0d cycle :cpuregs_wrdata = alu_out_q; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :cpuregs_wrdata =  reg_out; \n"  , count_cycle);
end 
cpuregs_write = 1; 
$fwrite(f,"%0d cycle :cpuregs_write = 1;\n"  , count_cycle); 
end 
ENABLE_IRQ && irq_state[0]: begin 
cpuregs_wrdata = reg_next_pc | latched_compr; 
$fwrite(f,"%0d cycle :cpuregs_wrdata = reg_next_pc | latched_compr;\n"  , count_cycle); 
cpuregs_write = 1; 
$fwrite(f,"%0d cycle :cpuregs_write = 1;\n"  , count_cycle); 
end 
ENABLE_IRQ && irq_state[1]: begin 
cpuregs_wrdata = irq_pending & ~irq_mask; 
$fwrite(f,"%0d cycle :cpuregs_wrdata = irq_pending & ~irq_mask;\n"  , count_cycle); 
cpuregs_write = 1; 
$fwrite(f,"%0d cycle :cpuregs_write = 1;\n"  , count_cycle); 
end 
endcase 
end 
end 
 
`ifndef PICORV32_REGS 
always @(posedge clk) begin 
$fwrite(f,"%0d cycle :if (resetn && cpuregs_write && latched_rd) begin\n"  , count_cycle); 
if (resetn && cpuregs_write && latched_rd) begin 
cpuregs[latched_rd] <= cpuregs_wrdata; 
$fwrite(f,"%0d cycle :cpuregs[latched_rd] <= cpuregs_wrdata;\n"  , count_cycle); 
end 
end 
 
always @* begin 
decoded_rs = 'bx; 
$fwrite(f,"%0d cycle :decoded_rs = \'bx;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :if (ENABLE_REGS_DUALPORT) begin\n"  , count_cycle); 
if (ENABLE_REGS_DUALPORT) begin 
`ifndef RISCV_FORMAL_BLACKBOX_REGS 
cpuregs_rs1 = decoded_rs1 ? cpuregs[decoded_rs1] : 0; 
$fwrite(f,"%0d cycle :if =  decoded_rs1 \n"  , count_cycle);
if ( decoded_rs1) begin
$fwrite(f,"%0d cycle :cpuregs_rs1 = cpuregs[%d]; \n"  , count_cycle,decoded_rs1);
end
else begin
$fwrite(f,"%0d cycle :cpuregs_rs1 =  0; \n"  , count_cycle);
end 
cpuregs_rs2 = decoded_rs2 ? cpuregs[decoded_rs2] : 0; 
$fwrite(f,"%0d cycle :if =  decoded_rs2 \n"  , count_cycle);
if ( decoded_rs2) begin
$fwrite(f,"%0d cycle :cpuregs_rs2 = cpuregs[%d]; \n"  , count_cycle,decoded_rs2);
end
else begin
$fwrite(f,"%0d cycle :cpuregs_rs2 =  0; \n"  , count_cycle);
end
`else 
cpuregs_rs1 = decoded_rs1 ? $anyseq : 0; 
$fwrite(f,"%0d cycle :if =  decoded_rs1 \n"  , count_cycle);
if ( decoded_rs1) begin
$fwrite(f,"%0d cycle :cpuregs_rs1 = $anyseq; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :cpuregs_rs1 =  0; \n"  , count_cycle);
end
cpuregs_rs2 = decoded_rs2 ? $anyseq : 0; 
$fwrite(f,"%0d cycle :if =  decoded_rs2 \n"  , count_cycle);
if ( decoded_rs2) begin
$fwrite(f,"%0d cycle :cpuregs_rs2 = $anyseq; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :cpuregs_rs2 =  0; \n"  , count_cycle);
end
`endif 
end else begin 
decoded_rs = (cpu_state == cpu_state_ld_rs2) ? decoded_rs2 : decoded_rs1; 
$fwrite(f,"%0d cycle :if =  (cpu_state == cpu_state_ld_rs2) \n"  , count_cycle);
if ( (cpu_state == cpu_state_ld_rs2)) begin
$fwrite(f,"%0d cycle :decoded_rs = decoded_rs2; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :decoded_rs =  decoded_rs1; \n"  , count_cycle);
end
`ifndef RISCV_FORMAL_BLACKBOX_REGS 
cpuregs_rs1 = decoded_rs ? cpuregs[decoded_rs] : 0; 
$fwrite(f,"%0d cycle :if =  decoded_rs \n"  , count_cycle);
if ( decoded_rs) begin
$fwrite(f,"%0d cycle :cpuregs_rs1 = cpuregs[%d]; \n"  , count_cycle,decoded_rs);
end
else begin
$fwrite(f,"%0d cycle :cpuregs_rs1 =  0; \n"  , count_cycle);
end
`else 
cpuregs_rs1 = decoded_rs ? $anyseq : 0; 
$fwrite(f,"%0d cycle :if =  decoded_rs \n"  , count_cycle);
if ( decoded_rs) begin
$fwrite(f,"%0d cycle :cpuregs_rs1 = $anyseq; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :cpuregs_rs1 =  0; \n"  , count_cycle);
end
`endif 
cpuregs_rs2 = cpuregs_rs1; 
$fwrite(f,"%0d cycle :cpuregs_rs2 = cpuregs_rs1;\n"  , count_cycle); 
end 
end 
`else 
wire[31:0] cpuregs_rdata1; 
wire[31:0] cpuregs_rdata2; 
 
wire [5:0] cpuregs_waddr = latched_rd; 
wire [5:0] cpuregs_raddr1 = ENABLE_REGS_DUALPORT ? decoded_rs1 : decoded_rs; 
wire [5:0] cpuregs_raddr2 = ENABLE_REGS_DUALPORT ? decoded_rs2 : 0; 
 
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
$fwrite(f,"%0d cycle :decoded_rs = \'bx;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :if (ENABLE_REGS_DUALPORT) begin\n"  , count_cycle); 
if (ENABLE_REGS_DUALPORT) begin 
cpuregs_rs1 = decoded_rs1 ? cpuregs_rdata1 : 0; 
$fwrite(f,"%0d cycle :if =  decoded_rs1 \n"  , count_cycle);
if ( decoded_rs1) begin
$fwrite(f,"%0d cycle :cpuregs_rs1 = cpuregs_rdata1; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :cpuregs_rs1 =  0; \n"  , count_cycle);
end
cpuregs_rs2 = decoded_rs2 ? cpuregs_rdata2 : 0; 
$fwrite(f,"%0d cycle :if =  decoded_rs2 \n"  , count_cycle);
if ( decoded_rs2) begin
$fwrite(f,"%0d cycle :cpuregs_rs2 = cpuregs_rdata2; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :cpuregs_rs2 =  0; \n"  , count_cycle);
end
end else begin 
decoded_rs = (cpu_state == cpu_state_ld_rs2) ? decoded_rs2 : decoded_rs1; 
$fwrite(f,"%0d cycle :if =  (cpu_state == cpu_state_ld_rs2) \n"  , count_cycle);
if ( (cpu_state == cpu_state_ld_rs2)) begin
$fwrite(f,"%0d cycle :decoded_rs = decoded_rs2; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :decoded_rs =  decoded_rs1; \n"  , count_cycle);
end
cpuregs_rs1 = decoded_rs ? cpuregs_rdata1 : 0; 
$fwrite(f,"%0d cycle :if =  decoded_rs \n"  , count_cycle);
if ( decoded_rs) begin
$fwrite(f,"%0d cycle :cpuregs_rs1 = cpuregs_rdata1; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :cpuregs_rs1 =  0; \n"  , count_cycle);
end
cpuregs_rs2 = cpuregs_rs1; 
$fwrite(f,"%0d cycle :cpuregs_rs2 = cpuregs_rs1;\n"  , count_cycle); 
end 
end 
`endif 
 
assign launch_next_insn = cpu_state == cpu_state_fetch && decoder_trigger && (!ENABLE_IRQ || irq_delay || irq_active || !(irq_pending & ~irq_mask)); 
always@* begin 
$fwrite(f,"%0d cycle :assign launch_next_insn = cpu_state == cpu_state_fetch && decoder_trigger && (!ENABLE_IRQ || irq_delay || irq_active || !(irq_pending & ~irq_mask));\n"  , count_cycle); 
end 
 
always @(posedge clk) begin 
trap <= 0; 
$fwrite(f,"%0d cycle :trap <= 0;\n"  , count_cycle); 
reg_sh <= 'bx; 
$fwrite(f,"%0d cycle :reg_sh <= \'bx;\n"  , count_cycle); 
reg_out <= 'bx; 
$fwrite(f,"%0d cycle :reg_out <= \'bx;\n"  , count_cycle); 
set_mem_do_rinst = 0; 
$fwrite(f,"%0d cycle :set_mem_do_rinst = 0;\n"  , count_cycle); 
set_mem_do_rdata = 0; 
$fwrite(f,"%0d cycle :set_mem_do_rdata = 0;\n"  , count_cycle); 
set_mem_do_wdata = 0; 
$fwrite(f,"%0d cycle :set_mem_do_wdata = 0;\n"  , count_cycle); 
 
alu_out_0_q <= alu_out_0; 
$fwrite(f,"%0d cycle :alu_out_0_q <= alu_out_0;\n"  , count_cycle); 
alu_out_q <= alu_out; 
$fwrite(f,"%0d cycle :alu_out_q <= alu_out;\n"  , count_cycle); 
 
alu_wait <= 0; 
$fwrite(f,"%0d cycle :alu_wait <= 0;\n"  , count_cycle); 
alu_wait_2 <= 0; 
$fwrite(f,"%0d cycle :alu_wait_2 <= 0;\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :if (launch_next_insn) begin\n"  , count_cycle); 
if (launch_next_insn) begin 
dbg_rs1val <= 'bx; 
$fwrite(f,"%0d cycle :dbg_rs1val <= \'bx;\n"  , count_cycle); 
dbg_rs2val <= 'bx; 
$fwrite(f,"%0d cycle :dbg_rs2val <= \'bx;\n"  , count_cycle); 
dbg_rs1val_valid <= 0; 
$fwrite(f,"%0d cycle :dbg_rs1val_valid <= 0;\n"  , count_cycle); 
dbg_rs2val_valid <= 0; 
$fwrite(f,"%0d cycle :dbg_rs2val_valid <= 0;\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :if (WITH_PCPI && CATCH_ILLINSN) begin\n"  , count_cycle); 
if (WITH_PCPI && CATCH_ILLINSN) begin 
$fwrite(f,"%0d cycle :if (resetn && pcpi_valid && !pcpi_int_wait) begin\n"  , count_cycle); 
if (resetn && pcpi_valid && !pcpi_int_wait) begin 
$fwrite(f,"%0d cycle :if (pcpi_timeout_counter) begin\n"  , count_cycle); 
if (pcpi_timeout_counter) begin 
pcpi_timeout_counter <= pcpi_timeout_counter - 1; 
$fwrite(f,"%0d cycle :pcpi_timeout_counter <= pcpi_timeout_counter - 1;\n"  , count_cycle); 
end 
end else 
pcpi_timeout_counter <= ~0; 
$fwrite(f,"%0d cycle :pcpi_timeout_counter <= ~0;\n"  , count_cycle); 
pcpi_timeout <= !pcpi_timeout_counter; 
$fwrite(f,"%0d cycle :pcpi_timeout <= !pcpi_timeout_counter;\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :if (ENABLE_COUNTERS) begin\n"  , count_cycle); 
if (ENABLE_COUNTERS) begin 
count_cycle <= resetn ? count_cycle + 1 : 0; 
$fwrite(f,"%0d cycle :if =  resetn \n"  , count_cycle);
if ( resetn) begin
$fwrite(f,"%0d cycle :count_cycle = count_cycle + 1; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :count_cycle =  0; \n"  , count_cycle);
end
$fwrite(f,"%0d cycle :if (!ENABLE_COUNTERS64) begin\n"  , count_cycle); 
if (!ENABLE_COUNTERS64) begin 
count_cycle[63:32] <= 0; 
$fwrite(f,"%0d cycle :count_cycle[63:32] <= 0;\n"  , count_cycle); 
end 
end else begin 
count_cycle <= 'bx; 
$fwrite(f,"%0d cycle :count_cycle <= \'bx;\n"  , count_cycle); 
count_instr <= 'bx; 
$fwrite(f,"%0d cycle :count_instr <= \'bx;\n"  , count_cycle); 
end 
 
next_irq_pending = ENABLE_IRQ ? irq_pending & LATCHED_IRQ : 'bx; 
$fwrite(f,"%0d cycle :if =  ENABLE_IRQ \n"  , count_cycle);
if ( ENABLE_IRQ) begin
$fwrite(f,"%0d cycle :next_irq_pending = irq_pending & LATCHED_IRQ; \n"  , count_cycle);
end
else begin
$fwrite(f,"%0d cycle :next_irq_pending =  'bx; \n"  , count_cycle);
end 
$fwrite(f,"%0d cycle :if (ENABLE_IRQ && ENABLE_IRQ_TIMER && timer) begin\n"  , count_cycle); 
if (ENABLE_IRQ && ENABLE_IRQ_TIMER && timer) begin 
$fwrite(f,"%0d cycle :if (timer - 1 == 0) begin\n"  , count_cycle); 
if (timer - 1 == 0) begin 
next_irq_pending[irq_timer] = 1; 
$fwrite(f,"%0d cycle :next_irq_pending[irq_timer] = 1;\n"  , count_cycle); 
end 
timer <= timer - 1; 
$fwrite(f,"%0d cycle :timer <= timer - 1;\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :if (ENABLE_IRQ) begin\n"  , count_cycle); 
if (ENABLE_IRQ) begin 
next_irq_pending = next_irq_pending | irq; 
$fwrite(f,"%0d cycle :next_irq_pending = next_irq_pending | irq;\n"  , count_cycle); 
end 
 
decoder_trigger <= mem_do_rinst && mem_done; 
$fwrite(f,"%0d cycle :decoder_trigger <= mem_do_rinst && mem_done;\n"  , count_cycle); 
decoder_trigger_q <= decoder_trigger; 
$fwrite(f,"%0d cycle :decoder_trigger_q <= decoder_trigger;\n"  , count_cycle); 
decoder_pseudo_trigger <= 0; 
$fwrite(f,"%0d cycle :decoder_pseudo_trigger <= 0;\n"  , count_cycle); 
decoder_pseudo_trigger_q <= decoder_pseudo_trigger; 
$fwrite(f,"%0d cycle :decoder_pseudo_trigger_q <= decoder_pseudo_trigger;\n"  , count_cycle); 
do_waitirq <= 0; 
$fwrite(f,"%0d cycle :do_waitirq <= 0;\n"  , count_cycle); 
 
trace_valid <= 0; 
$fwrite(f,"%0d cycle :trace_valid <= 0;\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :if (!ENABLE_TRACE) begin\n"  , count_cycle); 
if (!ENABLE_TRACE) begin 
trace_data <= 'bx; 
$fwrite(f,"%0d cycle :trace_data <= \'bx;\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :if (!resetn) begin\n"  , count_cycle); 
if (!resetn) begin 
reg_pc <= PROGADDR_RESET; 
$fwrite(f,"%0d cycle :reg_pc <= PROGADDR_RESET;\n"  , count_cycle); 
reg_next_pc <= PROGADDR_RESET; 
$fwrite(f,"%0d cycle :reg_next_pc <= PROGADDR_RESET;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :if (ENABLE_COUNTERS) begin\n"  , count_cycle); 
if (ENABLE_COUNTERS) begin 
count_instr <= 0; 
$fwrite(f,"%0d cycle :count_instr <= 0;\n"  , count_cycle); 
end 
latched_store <= 0; 
$fwrite(f,"%0d cycle :latched_store <= 0;\n"  , count_cycle); 
latched_stalu <= 0; 
$fwrite(f,"%0d cycle :latched_stalu <= 0;\n"  , count_cycle); 
latched_branch <= 0; 
$fwrite(f,"%0d cycle :latched_branch <= 0;\n"  , count_cycle); 
latched_trace <= 0; 
$fwrite(f,"%0d cycle :latched_trace <= 0;\n"  , count_cycle); 
latched_is_lu <= 0; 
$fwrite(f,"%0d cycle :latched_is_lu <= 0;\n"  , count_cycle); 
latched_is_lh <= 0; 
$fwrite(f,"%0d cycle :latched_is_lh <= 0;\n"  , count_cycle); 
latched_is_lb <= 0; 
$fwrite(f,"%0d cycle :latched_is_lb <= 0;\n"  , count_cycle); 
pcpi_valid <= 0; 
$fwrite(f,"%0d cycle :pcpi_valid <= 0;\n"  , count_cycle); 
pcpi_timeout <= 0; 
$fwrite(f,"%0d cycle :pcpi_timeout <= 0;\n"  , count_cycle); 
irq_active <= 0; 
$fwrite(f,"%0d cycle :irq_active <= 0;\n"  , count_cycle); 
irq_delay <= 0; 
$fwrite(f,"%0d cycle :irq_delay <= 0;\n"  , count_cycle); 
irq_mask <= ~0; 
$fwrite(f,"%0d cycle :irq_mask <= ~0;\n"  , count_cycle); 
next_irq_pending = 0; 
$fwrite(f,"%0d cycle :next_irq_pending = 0;\n"  , count_cycle); 
irq_state <= 0; 
$fwrite(f,"%0d cycle :irq_state <= 0;\n"  , count_cycle); 
eoi <= 0; 
$fwrite(f,"%0d cycle :eoi <= 0;\n"  , count_cycle); 
timer <= 0; 
$fwrite(f,"%0d cycle :timer <= 0;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :if (~STACKADDR) begin\n"  , count_cycle); 
if (~STACKADDR) begin 
latched_store <= 1; 
$fwrite(f,"%0d cycle :latched_store <= 1;\n"  , count_cycle); 
latched_rd <= 2; 
$fwrite(f,"%0d cycle :latched_rd <= 2;\n"  , count_cycle); 
reg_out <= STACKADDR; 
$fwrite(f,"%0d cycle :reg_out <= STACKADDR;\n"  , count_cycle); 
end 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_fetch;\n"  , count_cycle); 
end else 
(* parallel_case, full_case *) 
case (cpu_state) 
cpu_state_trap: begin 
trap <= 1; 
$fwrite(f,"%0d cycle :trap <= 1;\n"  , count_cycle); 
end 
 
cpu_state_fetch: begin 
mem_do_rinst <= !decoder_trigger && !do_waitirq; 
$fwrite(f,"%0d cycle :mem_do_rinst <= !decoder_trigger && !do_waitirq;\n"  , count_cycle); 
mem_wordsize <= 0; 
$fwrite(f,"%0d cycle :mem_wordsize <= 0;\n"  , count_cycle); 
 
current_pc = reg_next_pc; 
$fwrite(f,"%0d cycle :current_pc = reg_next_pc;\n"  , count_cycle); 
 
(* parallel_case *) 
case (1'b1) 
latched_branch: begin 
current_pc = latched_store ? (latched_stalu ? alu_out_q : reg_out) & ~1 : reg_next_pc; 
$fwrite(f,"%0d cycle :if =  latched_store \n"  , count_cycle);
if ( latched_store) begin
    $fwrite(f,"%0d cycle :if =  latched_stalu \n"  , count_cycle);
    if (latched_stalu) begin
        $fwrite(f,"%0d cycle :current_pc =  alu_out_q & ~1; \n"  , count_cycle);
    end
    else begin
        $fwrite(f,"%0d cycle :current_pc =  reg_out & ~1; \n"  , count_cycle);
    end

end
else begin
$fwrite(f,"%0d cycle :current_pc = reg_next_pc; \n"  , count_cycle);
end  
end 
latched_store && !latched_branch: begin 
 
end 
ENABLE_IRQ && irq_state[0]: begin 
current_pc = PROGADDR_IRQ; 
$fwrite(f,"%0d cycle :current_pc = PROGADDR_IRQ;\n"  , count_cycle); 
irq_active <= 1; 
$fwrite(f,"%0d cycle :irq_active <= 1;\n"  , count_cycle); 
mem_do_rinst <= 1; 
$fwrite(f,"%0d cycle :mem_do_rinst <= 1;\n"  , count_cycle); 
end 
ENABLE_IRQ && irq_state[1]: begin 
eoi <= irq_pending & ~irq_mask; 
$fwrite(f,"%0d cycle :eoi <= irq_pending & ~irq_mask;\n"  , count_cycle); 
next_irq_pending = next_irq_pending & irq_mask; 
$fwrite(f,"%0d cycle :next_irq_pending = next_irq_pending & irq_mask;\n"  , count_cycle); 
end 
endcase 
 
$fwrite(f,"%0d cycle :if (ENABLE_TRACE && latched_trace) begin\n"  , count_cycle); 
if (ENABLE_TRACE && latched_trace) begin 
latched_trace <= 0; 
$fwrite(f,"%0d cycle :latched_trace <= 0;\n"  , count_cycle); 
trace_valid <= 1; 
$fwrite(f,"%0d cycle :trace_valid <= 1;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :if (latched_branch) begin\n"  , count_cycle); 
if (latched_branch) begin 
trace_data <= (irq_active ? TRACE_IRQ : 0) | TRACE_BRANCH | (current_pc & 32'hfffffffe); 
    $fwrite(f,"%0d cycle :if =  irq_active \n"  , count_cycle);
    if (irq_active) begin
        $fwrite(f,"%0d cycle :trace_data =  TRACE_IRQ | TRACE_BRANCH | (current_pc & 32'hfffffffe); \n"  , count_cycle);
    end
    else begin
        $fwrite(f,"%0d cycle :trace_data =  0 | TRACE_BRANCH | (current_pc & 32'hfffffffe); \n"  , count_cycle);
    end
    end 
else 
trace_data <= (irq_active ? TRACE_IRQ : 0) | (latched_stalu ? alu_out_q : reg_out); 
    $fwrite(f,"%0d cycle :if =  irq_active \n"  , count_cycle);
    if (irq_active) begin
$fwrite(f,"%0d cycle :if =  latched_stalu \n"  , count_cycle);
    if (latched_stalu) begin
        $fwrite(f,"%0d cycle :trace_data =  TRACE_IRQ | alu_out_q ; \n"  , count_cycle);
    end
    else begin
        $fwrite(f,"%0d cycle :trace_data =  TRACE_IRQ | reg_out; \n"  , count_cycle);
    end
        end
    else begin
        $fwrite(f,"%0d cycle :if =  latched_stalu \n"  , count_cycle);
    if (latched_stalu) begin
        $fwrite(f,"%0d cycle :trace_data =  0 | alu_out_q; \n"  , count_cycle);
    end
    else begin
        $fwrite(f,"%0d cycle :trace_data =  0 | reg_out; \n"  , count_cycle);
    end
        end
    end 
 
reg_pc <= current_pc; 
$fwrite(f,"%0d cycle :reg_pc <= current_pc;\n"  , count_cycle); 
reg_next_pc <= current_pc; 
$fwrite(f,"%0d cycle :reg_next_pc <= current_pc;\n"  , count_cycle); 
 
latched_store <= 0; 
$fwrite(f,"%0d cycle :latched_store <= 0;\n"  , count_cycle); 
latched_stalu <= 0; 
$fwrite(f,"%0d cycle :latched_stalu <= 0;\n"  , count_cycle); 
latched_branch <= 0; 
$fwrite(f,"%0d cycle :latched_branch <= 0;\n"  , count_cycle); 
latched_is_lu <= 0; 
$fwrite(f,"%0d cycle :latched_is_lu <= 0;\n"  , count_cycle); 
latched_is_lh <= 0; 
$fwrite(f,"%0d cycle :latched_is_lh <= 0;\n"  , count_cycle); 
latched_is_lb <= 0; 
$fwrite(f,"%0d cycle :latched_is_lb <= 0;\n"  , count_cycle); 
latched_rd <= decoded_rd; 
$fwrite(f,"%0d cycle :latched_rd <= decoded_rd;\n"  , count_cycle); 
latched_compr <= compressed_instr; 
$fwrite(f,"%0d cycle :latched_compr <= compressed_instr;\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :if (ENABLE_IRQ && ((decoder_trigger && !irq_active && !irq_delay && |(irq_pending & ~irq_mask)) || irq_state)) begin\n"  , count_cycle); 
if (ENABLE_IRQ && ((decoder_trigger && !irq_active && !irq_delay && |(irq_pending & ~irq_mask)) || irq_state)) begin 
irq_state <=irq_state == 2'b00 ? 2'b01 :irq_state == 2'b01 ? 2'b10 : 2'b00; 
$fwrite(f,"%0d cycle :if =  irq_state == 2'b00 \n"  , count_cycle);
    if (irq_state == 2'b00) begin
        $fwrite(f,"%0d cycle :irq_state =  2'b01 | alu_out_q ; \n"  , count_cycle);
    end
    else begin
        $fwrite(f,"%0d cycle :if =  irq_state == 2'b01 \n"  , count_cycle);
        if (irq_state == 2'b01) begin
            $fwrite(f,"%0d cycle :irq_state =  2'b10  ; \n"  , count_cycle);
        end
        else begin
            $fwrite(f,"%0d cycle :irq_state =  2'b00 ; \n"  , count_cycle);
        end
        
    end
    latched_compr <= latched_compr; 
$fwrite(f,"%0d cycle :latched_compr <= latched_compr;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :if (ENABLE_IRQ_QREGS) begin\n"  , count_cycle); 
if (ENABLE_IRQ_QREGS) begin 
latched_rd <= irqregs_offset | irq_state[0]; 
$fwrite(f,"%0d cycle :latched_rd <= irqregs_offset | irq_state[0];\n"  , count_cycle); 
end 
else 
latched_rd <= irq_state[0] ? 4 : 3; 
$fwrite(f,"%0d cycle :if =   irq_state[0] \n"  , count_cycle);
        if ( irq_state[0]) begin
            $fwrite(f,"%0d cycle :latched_rd =  4  ; \n"  , count_cycle);
        end
        else begin
            $fwrite(f,"%0d cycle :latched_rd =  3 ; \n"  , count_cycle);
        end
        end else 
$fwrite(f,"%0d cycle :if (ENABLE_IRQ && (decoder_trigger || do_waitirq) && instr_waitirq) begin\n"  , count_cycle); 
if (ENABLE_IRQ && (decoder_trigger || do_waitirq) && instr_waitirq) begin 
$fwrite(f,"%0d cycle :if (irq_pending) begin\n"  , count_cycle); 
if (irq_pending) begin 
latched_store <= 1; 
$fwrite(f,"%0d cycle :latched_store <= 1;\n"  , count_cycle); 
reg_out <= irq_pending; 
$fwrite(f,"%0d cycle :reg_out <= irq_pending;\n"  , count_cycle); 
reg_next_pc <= compressed_instr + (compressed_instr ? 2 : 4); 
$fwrite(f,"%0d cycle :if =  compressed_instr \n"  , count_cycle);
        if ( compressed_instr) begin
            $fwrite(f,"%0d cycle :reg_next_pc = compressed_instr + 2   ; \n"  , count_cycle);
        end
        else begin
            $fwrite(f,"%0d cycle :reg_next_pc =  compressed_instr + 4 ; \n"  , count_cycle);
        end
        mem_do_rinst <= 1; 
$fwrite(f,"%0d cycle :mem_do_rinst <= 1;\n"  , count_cycle); 
end else 
do_waitirq <= 1; 
$fwrite(f,"%0d cycle :do_waitirq <= 1;\n"  , count_cycle); 
end else 
$fwrite(f,"%0d cycle :if (decoder_trigger) begin\n"  , count_cycle); 
if (decoder_trigger) begin 
 
irq_delay <= irq_active; 
$fwrite(f,"%0d cycle :irq_delay <= irq_active;\n"  , count_cycle); 
reg_next_pc <= current_pc + (compressed_instr ? 2 : 4); 
$fwrite(f,"%0d cycle :if =  compressed_instr \n"  , count_cycle);
        if ( compressed_instr) begin
            $fwrite(f,"%0d cycle :reg_next_pc = compressed_instr + 2   ; \n"  , count_cycle);
        end
        else begin
            $fwrite(f,"%0d cycle :reg_next_pc =  compressed_instr + 4 ; \n"  , count_cycle);
        end
        $fwrite(f,"%0d cycle :if (ENABLE_TRACE) begin\n"  , count_cycle); 
if (ENABLE_TRACE) begin 
latched_trace <= 1; 
$fwrite(f,"%0d cycle :latched_trace <= 1;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (ENABLE_COUNTERS) begin\n"  , count_cycle); 
if (ENABLE_COUNTERS) begin 
count_instr <= count_instr + 1; 
$fwrite(f,"%0d cycle :count_instr <= count_instr + 1;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :if (!ENABLE_COUNTERS64) begin\n"  , count_cycle); 
if (!ENABLE_COUNTERS64) begin 
count_instr[63:32] <= 0; 
$fwrite(f,"%0d cycle :count_instr[63:32] <= 0;\n"  , count_cycle); 
end 
end 
$fwrite(f,"%0d cycle :if (instr_jal) begin\n"  , count_cycle); 
if (instr_jal) begin 
mem_do_rinst <= 1; 
$fwrite(f,"%0d cycle :mem_do_rinst <= 1;\n"  , count_cycle); 
reg_next_pc <= current_pc + decoded_imm_j; 
$fwrite(f,"%0d cycle :reg_next_pc <= current_pc + decoded_imm_j;\n"  , count_cycle); 
latched_branch <= 1; 
$fwrite(f,"%0d cycle :latched_branch <= 1;\n"  , count_cycle); 
end else begin 
mem_do_rinst <= 0; 
$fwrite(f,"%0d cycle :mem_do_rinst <= 0;\n"  , count_cycle); 
mem_do_prefetch <= !instr_jalr && !instr_retirq; 
$fwrite(f,"%0d cycle :mem_do_prefetch <= !instr_jalr && !instr_retirq;\n"  , count_cycle); 
cpu_state <= cpu_state_ld_rs1; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_ld_rs1;\n"  , count_cycle); 
end 
end 
end 
 
cpu_state_ld_rs1: begin 
reg_op1 <= 'bx; 
$fwrite(f,"%0d cycle :reg_op1 <= \'bx;\n"  , count_cycle); 
reg_op2 <= 'bx; 
$fwrite(f,"%0d cycle :reg_op2 <= \'bx;\n"  , count_cycle); 
 
(* parallel_case *) 
case (1'b1) 
(CATCH_ILLINSN || WITH_PCPI) && instr_trap: begin 
$fwrite(f,"%0d cycle :if (WITH_PCPI) begin\n"  , count_cycle); 
if (WITH_PCPI) begin 
 
reg_op1 <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :reg_op1 <= cpuregs_rs1;\n"  , count_cycle); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :dbg_rs1val <= cpuregs_rs1;\n"  , count_cycle); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0d cycle :dbg_rs1val_valid <= 1;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :if (ENABLE_REGS_DUALPORT) begin\n"  , count_cycle); 
if (ENABLE_REGS_DUALPORT) begin 
pcpi_valid <= 1; 
$fwrite(f,"%0d cycle :pcpi_valid <= 1;\n"  , count_cycle); 
 
reg_sh <= cpuregs_rs2; 
$fwrite(f,"%0d cycle :reg_sh <= cpuregs_rs2;\n"  , count_cycle); 
reg_op2 <= cpuregs_rs2; 
$fwrite(f,"%0d cycle :reg_op2 <= cpuregs_rs2;\n"  , count_cycle); 
dbg_rs2val <= cpuregs_rs2; 
$fwrite(f,"%0d cycle :dbg_rs2val <= cpuregs_rs2;\n"  , count_cycle); 
dbg_rs2val_valid <= 1; 
$fwrite(f,"%0d cycle :dbg_rs2val_valid <= 1;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :if (pcpi_int_ready) begin\n"  , count_cycle); 
if (pcpi_int_ready) begin 
mem_do_rinst <= 1; 
$fwrite(f,"%0d cycle :mem_do_rinst <= 1;\n"  , count_cycle); 
pcpi_valid <= 0; 
$fwrite(f,"%0d cycle :pcpi_valid <= 0;\n"  , count_cycle); 
reg_out <= pcpi_int_rd; 
$fwrite(f,"%0d cycle :reg_out <= pcpi_int_rd;\n"  , count_cycle); 
latched_store <= pcpi_int_wr; 
$fwrite(f,"%0d cycle :latched_store <= pcpi_int_wr;\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_fetch;\n"  , count_cycle); 
end else 
$fwrite(f,"%0d cycle :if (CATCH_ILLINSN && (pcpi_timeout || instr_ecall_ebreak)) begin\n"  , count_cycle); 
if (CATCH_ILLINSN && (pcpi_timeout || instr_ecall_ebreak)) begin 
pcpi_valid <= 0; 
$fwrite(f,"%0d cycle :pcpi_valid <= 0;\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :if (ENABLE_IRQ && !irq_mask[irq_ebreak] && !irq_active) begin\n"  , count_cycle); 
if (ENABLE_IRQ && !irq_mask[irq_ebreak] && !irq_active) begin 
next_irq_pending[irq_ebreak] = 1; 
$fwrite(f,"%0d cycle :next_irq_pending[irq_ebreak] = 1;\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_fetch;\n"  , count_cycle); 
end else 
cpu_state <= cpu_state_trap; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_trap;\n"  , count_cycle); 
end 
end else begin 
cpu_state <= cpu_state_ld_rs2; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_ld_rs2;\n"  , count_cycle); 
end 
end else begin 
 
$fwrite(f,"%0d cycle :if (ENABLE_IRQ && !irq_mask[irq_ebreak] && !irq_active) begin\n"  , count_cycle); 
if (ENABLE_IRQ && !irq_mask[irq_ebreak] && !irq_active) begin 
next_irq_pending[irq_ebreak] = 1; 
$fwrite(f,"%0d cycle :next_irq_pending[irq_ebreak] = 1;\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_fetch;\n"  , count_cycle); 
end else 
cpu_state <= cpu_state_trap; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_trap;\n"  , count_cycle); 
end 
end 
ENABLE_COUNTERS && is_rdcycle_rdcycleh_rdinstr_rdinstrh: begin 
(* parallel_case, full_case *) 
case (1'b1) 
instr_rdcycle: begin 
reg_out <= count_cycle[31:0]; 
$fwrite(f,"%0d cycle :reg_out <= count_cycle[31:0];\n"  , count_cycle); 
end 
instr_rdcycleh && ENABLE_COUNTERS64: begin 
reg_out <= count_cycle[63:32]; 
$fwrite(f,"%0d cycle :reg_out <= count_cycle[63:32];\n"  , count_cycle); 
end 
instr_rdinstr: begin 
reg_out <= count_instr[31:0]; 
$fwrite(f,"%0d cycle :reg_out <= count_instr[31:0];\n"  , count_cycle); 
end 
instr_rdinstrh && ENABLE_COUNTERS64: begin 
reg_out <= count_instr[63:32]; 
$fwrite(f,"%0d cycle :reg_out <= count_instr[63:32];\n"  , count_cycle); 
end 
endcase 
latched_store <= 1; 
$fwrite(f,"%0d cycle :latched_store <= 1;\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_fetch;\n"  , count_cycle); 
end 
is_lui_auipc_jal: begin 
reg_op1 <= instr_lui ? 0 : reg_pc; 
$fwrite(f,"%0d cycle :if =  instr_lui \n"  , count_cycle);
        if ( instr_lui) begin
            $fwrite(f,"%0d cycle :reg_op1 = 0  ; \n"  , count_cycle);
        end
        else begin
            $fwrite(f,"%0d cycle :reg_op1 =  reg_pc ; \n"  , count_cycle);
        end
        reg_op2 <= decoded_imm; 
$fwrite(f,"%0d cycle :reg_op2 <= decoded_imm;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :if (TWO_CYCLE_ALU) begin\n"  , count_cycle); 
if (TWO_CYCLE_ALU) begin 
alu_wait <= 1; 
$fwrite(f,"%0d cycle :alu_wait <= 1;\n"  , count_cycle); 
end 
else 
mem_do_rinst <= mem_do_prefetch; 
$fwrite(f,"%0d cycle :mem_do_rinst <= mem_do_prefetch;\n"  , count_cycle); 
cpu_state <= cpu_state_exec; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_exec;\n"  , count_cycle); 
end 
ENABLE_IRQ && ENABLE_IRQ_QREGS && instr_getq: begin 
 
reg_out <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :reg_out <= cpuregs_rs1;\n"  , count_cycle); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :dbg_rs1val <= cpuregs_rs1;\n"  , count_cycle); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0d cycle :dbg_rs1val_valid <= 1;\n"  , count_cycle); 
latched_store <= 1; 
$fwrite(f,"%0d cycle :latched_store <= 1;\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_fetch;\n"  , count_cycle); 
end 
ENABLE_IRQ && ENABLE_IRQ_QREGS && instr_setq: begin 
 
reg_out <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :reg_out <= cpuregs_rs1;\n"  , count_cycle); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :dbg_rs1val <= cpuregs_rs1;\n"  , count_cycle); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0d cycle :dbg_rs1val_valid <= 1;\n"  , count_cycle); 
latched_rd <= latched_rd | irqregs_offset; 
$fwrite(f,"%0d cycle :latched_rd <= latched_rd | irqregs_offset;\n"  , count_cycle); 
latched_store <= 1; 
$fwrite(f,"%0d cycle :latched_store <= 1;\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_fetch;\n"  , count_cycle); 
end 
ENABLE_IRQ && instr_retirq: begin 
eoi <= 0; 
$fwrite(f,"%0d cycle :eoi <= 0;\n"  , count_cycle); 
irq_active <= 0; 
$fwrite(f,"%0d cycle :irq_active <= 0;\n"  , count_cycle); 
latched_branch <= 1; 
$fwrite(f,"%0d cycle :latched_branch <= 1;\n"  , count_cycle); 
latched_store <= 1; 
$fwrite(f,"%0d cycle :latched_store <= 1;\n"  , count_cycle); 
 
reg_out <= CATCH_MISALIGN ? (cpuregs_rs1 & 32'h fffffffe) : cpuregs_rs1; 
$fwrite(f,"%0d cycle :if =  CATCH_MISALIGN \n"  , count_cycle);
        if ( CATCH_MISALIGN) begin
            $fwrite(f,"%0d cycle :reg_out =(cpuregs_rs1 & 32'h fffffffe)  ; \n"  , count_cycle);
        end
        else begin
            $fwrite(f,"%0d cycle :reg_out =  cpuregs_rs1 ; \n"  , count_cycle);
        end
        dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :dbg_rs1val <= cpuregs_rs1;\n"  , count_cycle); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0d cycle :dbg_rs1val_valid <= 1;\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_fetch;\n"  , count_cycle); 
end 
ENABLE_IRQ && instr_maskirq: begin 
latched_store <= 1; 
$fwrite(f,"%0d cycle :latched_store <= 1;\n"  , count_cycle); 
reg_out <= irq_mask; 
$fwrite(f,"%0d cycle :reg_out <= irq_mask;\n"  , count_cycle); 
 
irq_mask <= cpuregs_rs1 | MASKED_IRQ; 
$fwrite(f,"%0d cycle :irq_mask <= cpuregs_rs1 | MASKED_IRQ;\n"  , count_cycle); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :dbg_rs1val <= cpuregs_rs1;\n"  , count_cycle); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0d cycle :dbg_rs1val_valid <= 1;\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_fetch;\n"  , count_cycle); 
end 
ENABLE_IRQ && ENABLE_IRQ_TIMER && instr_timer: begin 
latched_store <= 1; 
$fwrite(f,"%0d cycle :latched_store <= 1;\n"  , count_cycle); 
reg_out <= timer; 
$fwrite(f,"%0d cycle :reg_out <= timer;\n"  , count_cycle); 
 
timer <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :timer <= cpuregs_rs1;\n"  , count_cycle); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :dbg_rs1val <= cpuregs_rs1;\n"  , count_cycle); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0d cycle :dbg_rs1val_valid <= 1;\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_fetch;\n"  , count_cycle); 
end 
is_lb_lh_lw_lbu_lhu && !instr_trap: begin 
 
reg_op1 <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :reg_op1 <= cpuregs_rs1;\n"  , count_cycle); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :dbg_rs1val <= cpuregs_rs1;\n"  , count_cycle); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0d cycle :dbg_rs1val_valid <= 1;\n"  , count_cycle); 
cpu_state <= cpu_state_ldmem; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_ldmem;\n"  , count_cycle); 
mem_do_rinst <= 1; 
$fwrite(f,"%0d cycle :mem_do_rinst <= 1;\n"  , count_cycle); 
end 
is_slli_srli_srai && !BARREL_SHIFTER: begin 
 
reg_op1 <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :reg_op1 <= cpuregs_rs1;\n"  , count_cycle); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :dbg_rs1val <= cpuregs_rs1;\n"  , count_cycle); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0d cycle :dbg_rs1val_valid <= 1;\n"  , count_cycle); 
reg_sh <= decoded_rs2; 
$fwrite(f,"%0d cycle :reg_sh <= decoded_rs2;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_shift;\n"  , count_cycle); 
cpu_state <= cpu_state_shift; 
end 
is_jalr_addi_slti_sltiu_xori_ori_andi, is_slli_srli_srai && BARREL_SHIFTER: begin 
 
reg_op1 <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :reg_op1 <= cpuregs_rs1;\n"  , count_cycle); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :dbg_rs1val <= cpuregs_rs1;\n"  , count_cycle); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0d cycle :dbg_rs1val_valid <= 1;\n"  , count_cycle); 
reg_op2 <= is_slli_srli_srai && BARREL_SHIFTER ? decoded_rs2 : decoded_imm; 
$fwrite(f,"%0d cycle :if =  is_slli_srli_srai && BARREL_SHIFTER \n"  , count_cycle);
        if ( is_slli_srli_srai && BARREL_SHIFTER) begin
            $fwrite(f,"%0d cycle :reg_op2 =decoded_rs2  ; \n"  , count_cycle);
        end
        else begin
            $fwrite(f,"%0d cycle :reg_op2 =  decoded_imm ; \n"  , count_cycle);
        end
        $fwrite(f,"%0d cycle :if (TWO_CYCLE_ALU) begin\n"  , count_cycle); 
if (TWO_CYCLE_ALU) begin 
alu_wait <= 1; 
$fwrite(f,"%0d cycle :alu_wait <= 1;\n"  , count_cycle); 
end 
else 
mem_do_rinst <= mem_do_prefetch; 
$fwrite(f,"%0d cycle :mem_do_rinst <= mem_do_prefetch;\n"  , count_cycle); 
cpu_state <= cpu_state_exec; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_exec;\n"  , count_cycle); 
end 
default: begin 
 
reg_op1 <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :reg_op1 <= cpuregs_rs1;\n"  , count_cycle); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0d cycle :dbg_rs1val <= cpuregs_rs1;\n"  , count_cycle); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0d cycle :dbg_rs1val_valid <= 1;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :if (ENABLE_REGS_DUALPORT) begin\n"  , count_cycle); 
if (ENABLE_REGS_DUALPORT) begin 
 
reg_sh <= cpuregs_rs2; 
$fwrite(f,"%0d cycle :reg_sh <= cpuregs_rs2;\n"  , count_cycle); 
reg_op2 <= cpuregs_rs2; 
$fwrite(f,"%0d cycle :reg_op2 <= cpuregs_rs2;\n"  , count_cycle); 
dbg_rs2val <= cpuregs_rs2; 
$fwrite(f,"%0d cycle :dbg_rs2val <= cpuregs_rs2;\n"  , count_cycle); 
dbg_rs2val_valid <= 1; 
$fwrite(f,"%0d cycle :dbg_rs2val_valid <= 1;\n"  , count_cycle); 
(* parallel_case *) 
case (1'b1) 
is_sb_sh_sw: begin 
cpu_state <= cpu_state_stmem; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_stmem;\n"  , count_cycle); 
mem_do_rinst <= 1; 
$fwrite(f,"%0d cycle :mem_do_rinst <= 1;\n"  , count_cycle); 
end 
is_sll_srl_sra && !BARREL_SHIFTER: begin 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_shift;\n"  , count_cycle); 
cpu_state <= cpu_state_shift; 
end 
default: begin 
$fwrite(f,"%0d cycle :if (TWO_CYCLE_ALU || (TWO_CYCLE_COMPARE && is_beq_bne_blt_bge_bltu_bgeu)) begin\n"  , count_cycle); 
if (TWO_CYCLE_ALU || (TWO_CYCLE_COMPARE && is_beq_bne_blt_bge_bltu_bgeu)) begin 
alu_wait_2 <= TWO_CYCLE_ALU && (TWO_CYCLE_COMPARE && is_beq_bne_blt_bge_bltu_bgeu); 
$fwrite(f,"%0d cycle :alu_wait_2 <= TWO_CYCLE_ALU && (TWO_CYCLE_COMPARE && is_beq_bne_blt_bge_bltu_bgeu);\n"  , count_cycle); 
alu_wait <= 1; 
$fwrite(f,"%0d cycle :alu_wait <= 1;\n"  , count_cycle); 
end else 
mem_do_rinst <= mem_do_prefetch; 
$fwrite(f,"%0d cycle :mem_do_rinst <= mem_do_prefetch;\n"  , count_cycle); 
cpu_state <= cpu_state_exec; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_exec;\n"  , count_cycle); 
end 
endcase 
end else 
cpu_state <= cpu_state_ld_rs2; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_ld_rs2;\n"  , count_cycle); 
end 
endcase 
end 
 
cpu_state_ld_rs2: begin 
 
reg_sh <= cpuregs_rs2; 
$fwrite(f,"%0d cycle :reg_sh <= cpuregs_rs2;\n"  , count_cycle); 
reg_op2 <= cpuregs_rs2; 
$fwrite(f,"%0d cycle :reg_op2 <= cpuregs_rs2;\n"  , count_cycle); 
dbg_rs2val <= cpuregs_rs2; 
$fwrite(f,"%0d cycle :dbg_rs2val <= cpuregs_rs2;\n"  , count_cycle); 
dbg_rs2val_valid <= 1; 
$fwrite(f,"%0d cycle :dbg_rs2val_valid <= 1;\n"  , count_cycle); 
 
(* parallel_case *) 
case (1'b1) 
WITH_PCPI && instr_trap: begin 
pcpi_valid <= 1; 
$fwrite(f,"%0d cycle :pcpi_valid <= 1;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :if (pcpi_int_ready) begin\n"  , count_cycle); 
if (pcpi_int_ready) begin 
mem_do_rinst <= 1; 
$fwrite(f,"%0d cycle :mem_do_rinst <= 1;\n"  , count_cycle); 
pcpi_valid <= 0; 
$fwrite(f,"%0d cycle :pcpi_valid <= 0;\n"  , count_cycle); 
reg_out <= pcpi_int_rd; 
$fwrite(f,"%0d cycle :reg_out <= pcpi_int_rd;\n"  , count_cycle); 
latched_store <= pcpi_int_wr; 
$fwrite(f,"%0d cycle :latched_store <= pcpi_int_wr;\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_fetch;\n"  , count_cycle); 
end else 
$fwrite(f,"%0d cycle :if (CATCH_ILLINSN && (pcpi_timeout || instr_ecall_ebreak)) begin\n"  , count_cycle); 
if (CATCH_ILLINSN && (pcpi_timeout || instr_ecall_ebreak)) begin 
pcpi_valid <= 0; 
$fwrite(f,"%0d cycle :pcpi_valid <= 0;\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :if (ENABLE_IRQ && !irq_mask[irq_ebreak] && !irq_active) begin\n"  , count_cycle); 
if (ENABLE_IRQ && !irq_mask[irq_ebreak] && !irq_active) begin 
next_irq_pending[irq_ebreak] = 1; 
$fwrite(f,"%0d cycle :next_irq_pending[irq_ebreak] = 1;\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_fetch;\n"  , count_cycle); 
end else 
cpu_state <= cpu_state_trap; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_trap;\n"  , count_cycle); 
end 
end 
is_sb_sh_sw: begin 
cpu_state <= cpu_state_stmem; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_stmem;\n"  , count_cycle); 
mem_do_rinst <= 1; 
$fwrite(f,"%0d cycle :mem_do_rinst <= 1;\n"  , count_cycle); 
end 
is_sll_srl_sra && !BARREL_SHIFTER: begin 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_shift;\n"  , count_cycle); 
cpu_state <= cpu_state_shift; 
end 
default: begin 
$fwrite(f,"%0d cycle :if (TWO_CYCLE_ALU || (TWO_CYCLE_COMPARE && is_beq_bne_blt_bge_bltu_bgeu)) begin\n"  , count_cycle); 
if (TWO_CYCLE_ALU || (TWO_CYCLE_COMPARE && is_beq_bne_blt_bge_bltu_bgeu)) begin 
alu_wait_2 <= TWO_CYCLE_ALU && (TWO_CYCLE_COMPARE && is_beq_bne_blt_bge_bltu_bgeu); 
$fwrite(f,"%0d cycle :alu_wait_2 <= TWO_CYCLE_ALU && (TWO_CYCLE_COMPARE && is_beq_bne_blt_bge_bltu_bgeu);\n"  , count_cycle); 
alu_wait <= 1; 
$fwrite(f,"%0d cycle :alu_wait <= 1;\n"  , count_cycle); 
end else 
mem_do_rinst <= mem_do_prefetch; 
$fwrite(f,"%0d cycle :mem_do_rinst <= mem_do_prefetch;\n"  , count_cycle); 
cpu_state <= cpu_state_exec; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_exec;\n"  , count_cycle); 
end 
endcase 
end 
 
cpu_state_exec: begin 
reg_out <= reg_pc + decoded_imm; 
$fwrite(f,"%0d cycle :reg_out <= reg_pc + decoded_imm;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :if ((TWO_CYCLE_ALU || TWO_CYCLE_COMPARE) && (alu_wait || alu_wait_2)) begin\n"  , count_cycle); 
if ((TWO_CYCLE_ALU || TWO_CYCLE_COMPARE) && (alu_wait || alu_wait_2)) begin 
mem_do_rinst <= mem_do_prefetch && !alu_wait_2; 
$fwrite(f,"%0d cycle :mem_do_rinst <= mem_do_prefetch && !alu_wait_2;\n"  , count_cycle); 
alu_wait <= alu_wait_2; 
$fwrite(f,"%0d cycle :alu_wait <= alu_wait_2;\n"  , count_cycle); 
end else 
$fwrite(f,"%0d cycle :if (is_beq_bne_blt_bge_bltu_bgeu) begin\n"  , count_cycle); 
if (is_beq_bne_blt_bge_bltu_bgeu) begin 
latched_rd <= 0; 
$fwrite(f,"%0d cycle :latched_rd <= 0;\n"  , count_cycle); 
latched_store <= TWO_CYCLE_COMPARE ? alu_out_0_q : alu_out_0; 
$fwrite(f,"%0d cycle :if =  TWO_CYCLE_COMPARE \n"  , count_cycle);
        if ( TWO_CYCLE_COMPARE) begin
            $fwrite(f,"%0d cycle :latched_store =alu_out_0_q  ; \n"  , count_cycle);
        end
        else begin
            $fwrite(f,"%0d cycle :latched_store =  alu_out_0 ; \n"  , count_cycle);
        end
        latched_branch <= TWO_CYCLE_COMPARE ? alu_out_0_q : alu_out_0; 
$fwrite(f,"%0d cycle :if =  TWO_CYCLE_COMPARE \n"  , count_cycle);
        if ( TWO_CYCLE_COMPARE) begin
            $fwrite(f,"%0d cycle :latched_branch =alu_out_0_q  ; \n"  , count_cycle);
        end
        else begin
            $fwrite(f,"%0d cycle :latched_branch =  alu_out_0 ; \n"  , count_cycle);
        end
        $fwrite(f,"%0d cycle :if (mem_done) begin\n"  , count_cycle); 
if (mem_done) begin 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_fetch;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if =  TWO_CYCLE_COMPARE \n"  , count_cycle);
        if ( TWO_CYCLE_COMPARE) begin
            $fwrite(f,"%0d cycle :if =alu_out_0_q  ; \n"  , count_cycle);
        end
        else begin
            $fwrite(f,"%0d cycle :if =  alu_out_0 ; \n"  , count_cycle);
        end
        if (TWO_CYCLE_COMPARE ? alu_out_0_q : alu_out_0) begin 
decoder_trigger <= 0; 
$fwrite(f,"%0d cycle :decoder_trigger <= 0;\n"  , count_cycle); 
set_mem_do_rinst = 1; 
$fwrite(f,"%0d cycle :set_mem_do_rinst = 1;\n"  , count_cycle); 
end 
end else begin 
latched_branch <= instr_jalr; 
$fwrite(f,"%0d cycle :latched_branch <= instr_jalr;\n"  , count_cycle); 
latched_store <= 1; 
$fwrite(f,"%0d cycle :latched_store <= 1;\n"  , count_cycle); 
latched_stalu <= 1; 
$fwrite(f,"%0d cycle :latched_stalu <= 1;\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_fetch;\n"  , count_cycle); 
end 
end 
 
cpu_state_shift: begin 
latched_store <= 1; 
$fwrite(f,"%0d cycle :latched_store <= 1;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :if (reg_sh == 0) begin\n"  , count_cycle); 
if (reg_sh == 0) begin 
reg_out <= reg_op1; 
$fwrite(f,"%0d cycle :reg_out <= reg_op1;\n"  , count_cycle); 
mem_do_rinst <= mem_do_prefetch; 
$fwrite(f,"%0d cycle :mem_do_rinst <= mem_do_prefetch;\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_fetch;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :end else if (TWO_STAGE_SHIFT && reg_sh >= 4) begin\n"  , count_cycle); 
end else if (TWO_STAGE_SHIFT && reg_sh >= 4) begin 
(* parallel_case, full_case *) 
case (1'b1) 
instr_slli || instr_sll: begin 
reg_op1 <= reg_op1 << 4; 
$fwrite(f,"%0d cycle :reg_op1 <= reg_op1 << 4;\n"  , count_cycle); 
end 
instr_srli || instr_srl: begin 
reg_op1 <= reg_op1 >> 4; 
$fwrite(f,"%0d cycle :reg_op1 <= reg_op1 >> 4;\n"  , count_cycle); 
end 
instr_srai || instr_sra: begin 
reg_op1 <= $signed(reg_op1) >>> 4; 
$fwrite(f,"%0d cycle :reg_op1 <= $signed(reg_op1) >>> 4;\n"  , count_cycle); 
end 
endcase 
reg_sh <= reg_sh - 4; 
$fwrite(f,"%0d cycle :reg_sh <= reg_sh - 4;\n"  , count_cycle); 
end else begin 
(* parallel_case, full_case *) 
case (1'b1) 
instr_slli || instr_sll: begin 
reg_op1 <= reg_op1 << 1; 
$fwrite(f,"%0d cycle :reg_op1 <= reg_op1 << 1;\n"  , count_cycle); 
end 
instr_srli || instr_srl: begin 
reg_op1 <= reg_op1 >> 1; 
$fwrite(f,"%0d cycle :reg_op1 <= reg_op1 >> 1;\n"  , count_cycle); 
end 
instr_srai || instr_sra: begin 
reg_op1 <= $signed(reg_op1) >>> 1; 
$fwrite(f,"%0d cycle :reg_op1 <= $signed(reg_op1) >>> 1;\n"  , count_cycle); 
end 
endcase 
reg_sh <= reg_sh - 1; 
$fwrite(f,"%0d cycle :reg_sh <= reg_sh - 1;\n"  , count_cycle); 
end 
end 
 
cpu_state_stmem: begin 
$fwrite(f,"%0d cycle :if (ENABLE_TRACE) begin\n"  , count_cycle); 
if (ENABLE_TRACE) begin 
reg_out <= reg_op2; 
$fwrite(f,"%0d cycle :reg_out <= reg_op2;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (!mem_do_prefetch || mem_done) begin\n"  , count_cycle); 
if (!mem_do_prefetch || mem_done) begin 
$fwrite(f,"%0d cycle :if (!mem_do_wdata) begin\n"  , count_cycle); 
if (!mem_do_wdata) begin 
(* parallel_case, full_case *) 
case (1'b1) 
instr_sb: begin 
mem_wordsize <= 2; 
$fwrite(f,"%0d cycle :mem_wordsize <= 2;\n"  , count_cycle); 
end 
instr_sh: begin 
mem_wordsize <= 1; 
$fwrite(f,"%0d cycle :mem_wordsize <= 1;\n"  , count_cycle); 
end 
instr_sw: begin 
mem_wordsize <= 0; 
$fwrite(f,"%0d cycle :mem_wordsize <= 0;\n"  , count_cycle); 
end 
endcase 
$fwrite(f,"%0d cycle :if (ENABLE_TRACE) begin\n"  , count_cycle); 
if (ENABLE_TRACE) begin 
trace_valid <= 1; 
$fwrite(f,"%0d cycle :trace_valid <= 1;\n"  , count_cycle); 
trace_data <= (irq_active ? TRACE_IRQ : 0) | TRACE_ADDR | ((reg_op1 + decoded_imm) & 32'hffffffff); 
$fwrite(f,"%0d cycle :if =  irq_active \n"  , count_cycle);
        if ( irq_active) begin
            $fwrite(f,"%0d cycle :trace_data =TRACE_IRQ | TRACE_ADDR | ((reg_op1 + decoded_imm) & 32'hffffffff) ; \n"  , count_cycle);
        end
        else begin
            $fwrite(f,"%0d cycle :trace_data =  0 | TRACE_ADDR | ((reg_op1 + decoded_imm) & 32'hffffffff); \n"  , count_cycle);
        end
        end 
reg_op1 <= reg_op1 + decoded_imm; 
$fwrite(f,"%0d cycle :reg_op1 <= reg_op1 + decoded_imm;\n"  , count_cycle); 
set_mem_do_wdata = 1; 
$fwrite(f,"%0d cycle :set_mem_do_wdata = 1;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (!mem_do_prefetch && mem_done) begin\n"  , count_cycle); 
if (!mem_do_prefetch && mem_done) begin 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_fetch;\n"  , count_cycle); 
decoder_trigger <= 1; 
$fwrite(f,"%0d cycle :decoder_trigger <= 1;\n"  , count_cycle); 
decoder_pseudo_trigger <= 1; 
$fwrite(f,"%0d cycle :decoder_pseudo_trigger <= 1;\n"  , count_cycle); 
end 
end 
end 
 
cpu_state_ldmem: begin 
latched_store <= 1; 
$fwrite(f,"%0d cycle :latched_store <= 1;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :if (!mem_do_prefetch || mem_done) begin\n"  , count_cycle); 
if (!mem_do_prefetch || mem_done) begin 
$fwrite(f,"%0d cycle :if (!mem_do_rdata) begin\n"  , count_cycle); 
if (!mem_do_rdata) begin 
(* parallel_case, full_case *) 
case (1'b1) 
instr_lb || instr_lbu: begin 
mem_wordsize <= 2; 
$fwrite(f,"%0d cycle :mem_wordsize <= 2;\n"  , count_cycle); 
end 
instr_lh || instr_lhu: begin 
mem_wordsize <= 1; 
$fwrite(f,"%0d cycle :mem_wordsize <= 1;\n"  , count_cycle); 
end 
instr_lw: begin 
mem_wordsize <= 0; 
$fwrite(f,"%0d cycle :mem_wordsize <= 0;\n"  , count_cycle); 
end 
endcase 
latched_is_lu <= is_lbu_lhu_lw; 
$fwrite(f,"%0d cycle :latched_is_lu <= is_lbu_lhu_lw;\n"  , count_cycle); 
latched_is_lh <= instr_lh; 
$fwrite(f,"%0d cycle :latched_is_lh <= instr_lh;\n"  , count_cycle); 
latched_is_lb <= instr_lb; 
$fwrite(f,"%0d cycle :latched_is_lb <= instr_lb;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :if (ENABLE_TRACE) begin\n"  , count_cycle); 
if (ENABLE_TRACE) begin 
trace_valid <= 1; 
$fwrite(f,"%0d cycle :trace_valid <= 1;\n"  , count_cycle); 
trace_data <= (irq_active ? TRACE_IRQ : 0) | TRACE_ADDR | ((reg_op1 + decoded_imm) & 32'hffffffff); 
$fwrite(f,"%0d cycle :if =  irq_active \n"  , count_cycle);
        if ( irq_active) begin
            $fwrite(f,"%0d cycle :trace_data =TRACE_IRQ | TRACE_ADDR | ((reg_op1 + decoded_imm) & 32'hffffffff) ; \n"  , count_cycle);
        end
        else begin
            $fwrite(f,"%0d cycle :trace_data =  0 | TRACE_ADDR | ((reg_op1 + decoded_imm) & 32'hffffffff); \n"  , count_cycle);
        end
        end 
reg_op1 <= reg_op1 + decoded_imm; 
$fwrite(f,"%0d cycle :reg_op1 <= reg_op1 + decoded_imm;\n"  , count_cycle); 
set_mem_do_rdata = 1; 
$fwrite(f,"%0d cycle :set_mem_do_rdata = 1;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (!mem_do_prefetch && mem_done) begin\n"  , count_cycle); 
if (!mem_do_prefetch && mem_done) begin 
(* parallel_case, full_case *) 
case (1'b1) 
latched_is_lu: begin 
reg_out <= mem_rdata_word; 
$fwrite(f,"%0d cycle :reg_out <= mem_rdata_word;\n"  , count_cycle); 
end 
latched_is_lh: begin 
reg_out <= $signed(mem_rdata_word[15:0]); 
$fwrite(f,"%0d cycle :reg_out <= $signed(mem_rdata_word[15:0]);\n"  , count_cycle); 
end 
latched_is_lb: begin 
reg_out <= $signed(mem_rdata_word[7:0]); 
$fwrite(f,"%0d cycle :reg_out <= $signed(mem_rdata_word[7:0]);\n"  , count_cycle); 
end 
endcase 
decoder_trigger <= 1; 
$fwrite(f,"%0d cycle :decoder_trigger <= 1;\n"  , count_cycle); 
decoder_pseudo_trigger <= 1; 
$fwrite(f,"%0d cycle :decoder_pseudo_trigger <= 1;\n"  , count_cycle); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_fetch;\n"  , count_cycle); 
end 
end 
end 
endcase 
 
$fwrite(f,"%0d cycle :if (CATCH_MISALIGN && resetn && (mem_do_rdata || mem_do_wdata)) begin\n"  , count_cycle); 
if (CATCH_MISALIGN && resetn && (mem_do_rdata || mem_do_wdata)) begin 
$fwrite(f,"%0d cycle :if (mem_wordsize == 0 && reg_op1[1:0] != 0) begin\n"  , count_cycle); 
if (mem_wordsize == 0 && reg_op1[1:0] != 0) begin 
 
$fwrite(f,"%0d cycle :if (ENABLE_IRQ && !irq_mask[irq_buserror] && !irq_active) begin\n"  , count_cycle); 
if (ENABLE_IRQ && !irq_mask[irq_buserror] && !irq_active) begin 
next_irq_pending[irq_buserror] = 1; 
$fwrite(f,"%0d cycle :next_irq_pending[irq_buserror] = 1;\n"  , count_cycle); 
end else 
cpu_state <= cpu_state_trap; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_trap;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (mem_wordsize == 1 && reg_op1[0] != 0) begin\n"  , count_cycle); 
if (mem_wordsize == 1 && reg_op1[0] != 0) begin 
 
$fwrite(f,"%0d cycle :if (ENABLE_IRQ && !irq_mask[irq_buserror] && !irq_active) begin\n"  , count_cycle); 
if (ENABLE_IRQ && !irq_mask[irq_buserror] && !irq_active) begin 
next_irq_pending[irq_buserror] = 1; 
$fwrite(f,"%0d cycle :next_irq_pending[irq_buserror] = 1;\n"  , count_cycle); 
end else 
cpu_state <= cpu_state_trap; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_trap;\n"  , count_cycle); 
end 
end 
$fwrite(f,"%0d cycle :if (CATCH_MISALIGN && resetn && mem_do_rinst && (COMPRESSED_ISA ? reg_pc[0] : |reg_pc[1:0])) begin\n"  , count_cycle); 
if (CATCH_MISALIGN && resetn && mem_do_rinst && (COMPRESSED_ISA ? reg_pc[0] : |reg_pc[1:0])) begin 
 
$fwrite(f,"%0d cycle :if (ENABLE_IRQ && !irq_mask[irq_buserror] && !irq_active) begin\n"  , count_cycle); 
if (ENABLE_IRQ && !irq_mask[irq_buserror] && !irq_active) begin 
next_irq_pending[irq_buserror] = 1; 
$fwrite(f,"%0d cycle :next_irq_pending[irq_buserror] = 1;\n"  , count_cycle); 
end else 
cpu_state <= cpu_state_trap; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_trap;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (!CATCH_ILLINSN && decoder_trigger_q && !decoder_pseudo_trigger_q && instr_ecall_ebreak) begin\n"  , count_cycle); 
if (!CATCH_ILLINSN && decoder_trigger_q && !decoder_pseudo_trigger_q && instr_ecall_ebreak) begin 
cpu_state <= cpu_state_trap; 
$fwrite(f,"%0d cycle :cpu_state <= cpu_state_trap;\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :if (!resetn || mem_done) begin\n"  , count_cycle); 
if (!resetn || mem_done) begin 
mem_do_prefetch <= 0; 
$fwrite(f,"%0d cycle :mem_do_prefetch <= 0;\n"  , count_cycle); 
mem_do_rinst <= 0; 
$fwrite(f,"%0d cycle :mem_do_rinst <= 0;\n"  , count_cycle); 
mem_do_rdata <= 0; 
$fwrite(f,"%0d cycle :mem_do_rdata <= 0;\n"  , count_cycle); 
mem_do_wdata <= 0; 
$fwrite(f,"%0d cycle :mem_do_wdata <= 0;\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :if (set_mem_do_rinst) begin\n"  , count_cycle); 
if (set_mem_do_rinst) begin 
mem_do_rinst <= 1; 
$fwrite(f,"%0d cycle :mem_do_rinst <= 1;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (set_mem_do_rdata) begin\n"  , count_cycle); 
if (set_mem_do_rdata) begin 
mem_do_rdata <= 1; 
$fwrite(f,"%0d cycle :mem_do_rdata <= 1;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (set_mem_do_wdata) begin\n"  , count_cycle); 
if (set_mem_do_wdata) begin 
mem_do_wdata <= 1; 
$fwrite(f,"%0d cycle :mem_do_wdata <= 1;\n"  , count_cycle); 
end 
 
irq_pending <= next_irq_pending & ~MASKED_IRQ; 
$fwrite(f,"%0d cycle :irq_pending <= next_irq_pending & ~MASKED_IRQ;\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :if (!CATCH_MISALIGN) begin\n"  , count_cycle); 
if (!CATCH_MISALIGN) begin 
$fwrite(f,"%0d cycle :if (COMPRESSED_ISA) begin\n"  , count_cycle); 
if (COMPRESSED_ISA) begin 
reg_pc[0] <= 0; 
$fwrite(f,"%0d cycle :reg_pc[0] <= 0;\n"  , count_cycle); 
reg_next_pc[0] <= 0; 
$fwrite(f,"%0d cycle :reg_next_pc[0] <= 0;\n"  , count_cycle); 
end else begin 
reg_pc[1:0] <= 0; 
$fwrite(f,"%0d cycle :reg_pc[1:0] <= 0;\n"  , count_cycle); 
reg_next_pc[1:0] <= 0; 
$fwrite(f,"%0d cycle :reg_next_pc[1:0] <= 0;\n"  , count_cycle); 
end 
end 
current_pc = 'bx; 
$fwrite(f,"%0d cycle :current_pc = \'bx;\n"  , count_cycle); 
end 
 
`ifdef RISCV_FORMAL 
reg dbg_irq_call; 
reg dbg_irq_enter; 
reg [31:0] dbg_irq_ret; 
always @(posedge clk) begin 
rvfi_valid <= resetn && (launch_next_insn || trap) && dbg_valid_insn; 
$fwrite(f,"%0d cycle :rvfi_valid <= resetn && (launch_next_insn || trap) && dbg_valid_insn;\n"  , count_cycle); 
rvfi_order <= resetn ? rvfi_order + rvfi_valid : 0; 
$fwrite(f,"%0d cycle :if =  resetn \n"  , count_cycle);
        if ( resetn) begin
            $fwrite(f,"%0d cycle :rvfi_order =rvfi_order + rvfi_valid; \n"  , count_cycle);
        end
        else begin
            $fwrite(f,"%0d cycle :rvfi_order =  0  ; \n"  , count_cycle);
        end 
rvfi_insn <= dbg_insn_opcode; 
$fwrite(f,"%0d cycle :rvfi_insn <= dbg_insn_opcode;\n"  , count_cycle); 
rvfi_rs1_addr <= dbg_rs1val_valid ? dbg_insn_rs1 : 0; 
$fwrite(f,"%0d cycle :if =  dbg_rs1val_valid \n"  , count_cycle);
        if ( dbg_rs1val_valid) begin
            $fwrite(f,"%0d cycle :rvfi_rs1_addr =dbg_insn_rs1; \n"  , count_cycle);
        end
        else begin
            $fwrite(f,"%0d cycle :rvfi_rs1_addr =  0  ; \n"  , count_cycle);
        end 
        rvfi_rs2_addr <= dbg_rs2val_valid ? dbg_insn_rs2 : 0; 
$fwrite(f,"%0d cycle :if =  dbg_rs2val_valid \n"  , count_cycle);
        if ( dbg_rs2val_valid) begin
            $fwrite(f,"%0d cycle :rvfi_rs2_addr =dbg_insn_rs2; \n"  , count_cycle);
        end
        else begin
            $fwrite(f,"%0d cycle :rvfi_rs2_addr =  0  ; \n"  , count_cycle);
        end 
        rvfi_pc_rdata <= dbg_insn_addr; 
$fwrite(f,"%0d cycle :rvfi_pc_rdata <= dbg_insn_addr;\n"  , count_cycle); 
rvfi_rs1_rdata <= dbg_rs1val_valid ? dbg_rs1val : 0; 
$fwrite(f,"%0d cycle :if =  dbg_rs1val_valid \n"  , count_cycle);
        if ( dbg_rs1val_valid) begin
            $fwrite(f,"%0d cycle :rvfi_rs1_rdata =dbg_rs1val; \n"  , count_cycle);
        end
        else begin
            $fwrite(f,"%0d cycle :rvfi_rs1_rdata =  0  ; \n"  , count_cycle);
        end 
        rvfi_rs2_rdata <= dbg_rs2val_valid ? dbg_rs2val : 0; 
$fwrite(f,"%0d cycle :if =  dbg_rs2val_valid \n"  , count_cycle);
        if ( dbg_rs2val_valid) begin
            $fwrite(f,"%0d cycle :rvfi_rs2_rdata =dbg_rs2val; \n"  , count_cycle);
        end
        else begin
            $fwrite(f,"%0d cycle :rvfi_rs2_rdata =  0  ; \n"  , count_cycle);
        end 
        rvfi_trap <= trap; 
$fwrite(f,"%0d cycle :rvfi_trap <= trap;\n"  , count_cycle); 
rvfi_halt <= trap; 
$fwrite(f,"%0d cycle :rvfi_halt <= trap;\n"  , count_cycle); 
rvfi_intr <= dbg_irq_enter; 
$fwrite(f,"%0d cycle :rvfi_intr <= dbg_irq_enter;\n"  , count_cycle); 
rvfi_mode <= 3; 
$fwrite(f,"%0d cycle :rvfi_mode <= 3;\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :if (!resetn) begin\n"  , count_cycle); 
if (!resetn) begin 
dbg_irq_call <= 0; 
$fwrite(f,"%0d cycle :dbg_irq_call <= 0;\n"  , count_cycle); 
dbg_irq_enter <= 0; 
$fwrite(f,"%0d cycle :dbg_irq_enter <= 0;\n"  , count_cycle); 
end else 
$fwrite(f,"%0d cycle :if (rvfi_valid) begin\n"  , count_cycle); 
if (rvfi_valid) begin 
dbg_irq_call <= 0; 
$fwrite(f,"%0d cycle :dbg_irq_call <= 0;\n"  , count_cycle); 
dbg_irq_enter <= dbg_irq_call; 
$fwrite(f,"%0d cycle :dbg_irq_enter <= dbg_irq_call;\n"  , count_cycle); 
end else 
$fwrite(f,"%0d cycle :if (irq_state == 1) begin\n"  , count_cycle); 
if (irq_state == 1) begin 
dbg_irq_call <= 1; 
$fwrite(f,"%0d cycle :dbg_irq_call <= 1;\n"  , count_cycle); 
dbg_irq_ret <= next_pc; 
$fwrite(f,"%0d cycle :dbg_irq_ret <= next_pc;\n"  , count_cycle); 
end 
 
$fwrite(f,"%0d cycle :if (!resetn) begin\n"  , count_cycle); 
if (!resetn) begin 
rvfi_rd_addr <= 0; 
$fwrite(f,"%0d cycle :rvfi_rd_addr <= 0;\n"  , count_cycle); 
rvfi_rd_wdata <= 0; 
$fwrite(f,"%0d cycle :rvfi_rd_wdata <= 0;\n"  , count_cycle); 
end else 
$fwrite(f,"%0d cycle :if (cpuregs_write && !irq_state) begin\n"  , count_cycle); 
if (cpuregs_write && !irq_state) begin 
rvfi_rd_addr <= latched_rd; 
$fwrite(f,"%0d cycle :rvfi_rd_addr <= latched_rd;\n"  , count_cycle); 
rvfi_rd_wdata <= latched_rd ? cpuregs_wrdata : 0; 
$fwrite(f,"%0d cycle :if =  latched_rd \n"  , count_cycle);
        if ( latched_rd) begin
            $fwrite(f,"%0d cycle :rvfi_rd_wdata =cpuregs_wrdata; \n"  , count_cycle);
        end
        else begin
            $fwrite(f,"%0d cycle :rvfi_rd_wdata =  0  ; \n"  , count_cycle);
        end 
        end else 
$fwrite(f,"%0d cycle :if (rvfi_valid) begin\n"  , count_cycle); 
if (rvfi_valid) begin 
rvfi_rd_addr <= 0; 
$fwrite(f,"%0d cycle :rvfi_rd_addr <= 0;\n"  , count_cycle); 
rvfi_rd_wdata <= 0; 
$fwrite(f,"%0d cycle :rvfi_rd_wdata <= 0;\n"  , count_cycle); 
end 
 
casez (dbg_insn_opcode) 
32'b 0000000_?????_000??_???_?????_0001011: begin // getq 
rvfi_rs1_addr <= 0; 
$fwrite(f,"%0d cycle :rvfi_rs1_addr <= 0;\n"  , count_cycle); 
rvfi_rs1_rdata <= 0; 
$fwrite(f,"%0d cycle :rvfi_rs1_rdata <= 0;\n"  , count_cycle); 
end 
32'b 0000001_?????_?????_???_000??_0001011: begin // setq 
rvfi_rd_addr <= 0; 
$fwrite(f,"%0d cycle :rvfi_rd_addr <= 0;\n"  , count_cycle); 
rvfi_rd_wdata <= 0; 
$fwrite(f,"%0d cycle :rvfi_rd_wdata <= 0;\n"  , count_cycle); 
end 
32'b 0000010_?????_00000_???_00000_0001011: begin // retirq 
rvfi_rs1_addr <= 0; 
$fwrite(f,"%0d cycle :rvfi_rs1_addr <= 0;\n"  , count_cycle); 
rvfi_rs1_rdata <= 0; 
$fwrite(f,"%0d cycle :rvfi_rs1_rdata <= 0;\n"  , count_cycle); 
end 
endcase 
 
$fwrite(f,"%0d cycle :if (!dbg_irq_call) begin\n"  , count_cycle); 
if (!dbg_irq_call) begin 
$fwrite(f,"%0d cycle :if (dbg_mem_instr) begin\n"  , count_cycle); 
if (dbg_mem_instr) begin 
rvfi_mem_addr <= 0; 
$fwrite(f,"%0d cycle :rvfi_mem_addr <= 0;\n"  , count_cycle); 
rvfi_mem_rmask <= 0; 
$fwrite(f,"%0d cycle :rvfi_mem_rmask <= 0;\n"  , count_cycle); 
rvfi_mem_wmask <= 0; 
$fwrite(f,"%0d cycle :rvfi_mem_wmask <= 0;\n"  , count_cycle); 
rvfi_mem_rdata <= 0; 
$fwrite(f,"%0d cycle :rvfi_mem_rdata <= 0;\n"  , count_cycle); 
rvfi_mem_wdata <= 0; 
$fwrite(f,"%0d cycle :rvfi_mem_wdata <= 0;\n"  , count_cycle); 
end else 
$fwrite(f,"%0d cycle :if (dbg_mem_valid && dbg_mem_ready) begin\n"  , count_cycle); 
if (dbg_mem_valid && dbg_mem_ready) begin 
rvfi_mem_addr <= dbg_mem_addr; 
$fwrite(f,"%0d cycle :rvfi_mem_addr <= dbg_mem_addr;\n"  , count_cycle); 
rvfi_mem_rmask <= dbg_mem_wstrb ? 0 : ~0; 
$fwrite(f,"%0d cycle :if =  dbg_mem_wstrb \n"  , count_cycle);
        if ( dbg_mem_wstrb) begin
            $fwrite(f,"%0d cycle :rvfi_mem_rmask =0; \n"  , count_cycle);
        end
        else begin
            $fwrite(f,"%0d cycle :rvfi_mem_rmask =  ~0  ; \n"  , count_cycle);
        end 
        rvfi_mem_wmask <= dbg_mem_wstrb; 
$fwrite(f,"%0d cycle :rvfi_mem_wmask <= dbg_mem_wstrb;\n"  , count_cycle); 
rvfi_mem_rdata <= dbg_mem_rdata; 
$fwrite(f,"%0d cycle :rvfi_mem_rdata <= dbg_mem_rdata;\n"  , count_cycle); 
rvfi_mem_wdata <= dbg_mem_wdata; 
$fwrite(f,"%0d cycle :rvfi_mem_wdata <= dbg_mem_wdata;\n"  , count_cycle); 
end 
end 
end 
 
always @* begin 
rvfi_pc_wdata = dbg_irq_call ? dbg_irq_ret : dbg_insn_addr; 
$fwrite(f,"%0d cycle :if =  dbg_irq_call \n"  , count_cycle);
        if ( dbg_irq_call) begin
            $fwrite(f,"%0d cycle :rvfi_pc_wdata =dbg_irq_ret; \n"  , count_cycle);
        end
        else begin
            $fwrite(f,"%0d cycle :rvfi_pc_wdata =  dbg_insn_addr  ; \n"  , count_cycle);
        end 
        end 
`endif 
 
// Formal Verification 
`ifdef FORMAL 
reg [3:0] last_mem_nowait; 
always @(posedge clk) begin 
last_mem_nowait <= {last_mem_nowait, mem_ready || !mem_valid}; 
$fwrite(f,"%0d cycle :last_mem_nowait <= {last_mem_nowait, mem_ready || !mem_valid};\n"  , count_cycle); 
end 
 
// stall the memory interface for max 4 cycles 
restrict property (|last_mem_nowait || mem_ready || !mem_valid); 
 
// resetn low in first cycle, after that resetn high 
restrict property (resetn != $initstate); 
$fwrite(f,"%0d cycle :restrict property (resetn != $initstate);\n"  , count_cycle); 
 
// this just makes it much easier to read traces. uncomment as needed. 
// assume property (mem_valid || !mem_ready); 
 
reg ok; 
always @* begin 
$fwrite(f,"%0d cycle :if (resetn) begin\n"  , count_cycle); 
if (resetn) begin 
// instruction fetches are read-only 
$fwrite(f,"%0d cycle :if (mem_valid && mem_instr) begin\n"  , count_cycle); 
if (mem_valid && mem_instr) begin 
assert (mem_wstrb == 0); 
$fwrite(f,"%0d cycle :assert (mem_wstrb == 0);\n"  , count_cycle); 
end 
 
// cpu_state must be valid 
ok = 0; 
$fwrite(f,"%0d cycle :ok = 0;\n"  , count_cycle); 
$fwrite(f,"%0d cycle :if (cpu_state == cpu_state_trap) begin\n"  , count_cycle); 
if (cpu_state == cpu_state_trap) begin 
ok = 1; 
$fwrite(f,"%0d cycle :ok = 1;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (cpu_state == cpu_state_fetch) begin\n"  , count_cycle); 
if (cpu_state == cpu_state_fetch) begin 
ok = 1; 
$fwrite(f,"%0d cycle :ok = 1;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (cpu_state == cpu_state_ld_rs1) begin\n"  , count_cycle); 
if (cpu_state == cpu_state_ld_rs1) begin 
ok = 1; 
$fwrite(f,"%0d cycle :ok = 1;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (cpu_state == cpu_state_ld_rs2) begin\n"  , count_cycle); 
if (cpu_state == cpu_state_ld_rs2) begin 
ok = !ENABLE_REGS_DUALPORT; 
$fwrite(f,"%0d cycle :ok = !ENABLE_REGS_DUALPORT;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (cpu_state == cpu_state_exec) begin\n"  , count_cycle); 
if (cpu_state == cpu_state_exec) begin 
ok = 1; 
$fwrite(f,"%0d cycle :ok = 1;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (cpu_state == cpu_state_shift) begin\n"  , count_cycle); 
if (cpu_state == cpu_state_shift) begin 
ok = 1; 
$fwrite(f,"%0d cycle :ok = 1;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (cpu_state == cpu_state_stmem) begin\n"  , count_cycle); 
if (cpu_state == cpu_state_stmem) begin 
ok = 1; 
$fwrite(f,"%0d cycle :ok = 1;\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (cpu_state == cpu_state_ldmem) begin\n"  , count_cycle); 
if (cpu_state == cpu_state_ldmem) begin 
ok = 1; 
$fwrite(f,"%0d cycle :ok = 1;\n"  , count_cycle); 
end 
assert (ok); 
end 
end 
 
reg last_mem_la_read = 0; 
$fwrite(f,"%0d cycle :reg last_mem_la_read = 0;\n"  , count_cycle); 
reg last_mem_la_write = 0; 
$fwrite(f,"%0d cycle :reg last_mem_la_write = 0;\n"  , count_cycle); 
reg [31:0] last_mem_la_addr; 
reg [31:0] last_mem_la_wdata; 
reg [3:0] last_mem_la_wstrb = 0; 
$fwrite(f,"%0d cycle :reg [3:0] last_mem_la_wstrb = 0;\n"  , count_cycle); 
 
always @(posedge clk) begin 
last_mem_la_read <= mem_la_read; 
$fwrite(f,"%0d cycle :last_mem_la_read <= mem_la_read;\n"  , count_cycle); 
last_mem_la_write <= mem_la_write; 
$fwrite(f,"%0d cycle :last_mem_la_write <= mem_la_write;\n"  , count_cycle); 
last_mem_la_addr <= mem_la_addr; 
$fwrite(f,"%0d cycle :last_mem_la_addr <= mem_la_addr;\n"  , count_cycle); 
last_mem_la_wdata <= mem_la_wdata; 
$fwrite(f,"%0d cycle :last_mem_la_wdata <= mem_la_wdata;\n"  , count_cycle); 
last_mem_la_wstrb <= mem_la_wstrb; 
$fwrite(f,"%0d cycle :last_mem_la_wstrb <= mem_la_wstrb;\n"  , count_cycle); 
 
$fwrite(f,"%0d cycle :if (last_mem_la_read) begin\n"  , count_cycle); 
if (last_mem_la_read) begin 
assert(mem_valid); 
assert(mem_addr == last_mem_la_addr); 
$fwrite(f,"%0d cycle :assert(mem_addr == last_mem_la_addr);\n"  , count_cycle); 
assert(mem_wstrb == 0); 
$fwrite(f,"%0d cycle :assert(mem_wstrb == 0);\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (last_mem_la_write) begin\n"  , count_cycle); 
if (last_mem_la_write) begin 
assert(mem_valid); 
assert(mem_addr == last_mem_la_addr); 
$fwrite(f,"%0d cycle :assert(mem_addr == last_mem_la_addr);\n"  , count_cycle); 
assert(mem_wdata == last_mem_la_wdata); 
$fwrite(f,"%0d cycle :assert(mem_wdata == last_mem_la_wdata);\n"  , count_cycle); 
assert(mem_wstrb == last_mem_la_wstrb); 
$fwrite(f,"%0d cycle :assert(mem_wstrb == last_mem_la_wstrb);\n"  , count_cycle); 
end 
$fwrite(f,"%0d cycle :if (mem_la_read || mem_la_write) begin\n"  , count_cycle); 
if (mem_la_read || mem_la_write) begin 
assert(!mem_valid || mem_ready); 
end 
end 
`endif 
endmodule 
 
 
 
 
/*************************************************************** 
* picorv32_pcpi_div 
***************************************************************/ 
 
