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
always@* begin 
$fwrite(f,"%0t cycle :picorv32.v:116\n"  , $time); 
end 
wire dbg_mem_instr = mem_instr; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32.v:120\n"  , $time); 
end 
wire dbg_mem_ready = mem_ready; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32.v:124\n"  , $time); 
end 
wire [31:0] dbg_mem_addr  = mem_addr; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32.v:128\n"  , $time); 
end 
wire [31:0] dbg_mem_wdata = mem_wdata; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32.v:132\n"  , $time); 
end 
wire [ 3:0] dbg_mem_wstrb = mem_wstrb; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32.v:136\n"  , $time); 
end 
wire [31:0] dbg_mem_rdata = mem_rdata; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32.v:140\n"  , $time); 
end 
 
assign pcpi_rs1 = reg_op1; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32.v:145\n"  , $time); 
end 
assign pcpi_rs2 = reg_op2; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32.v:149\n"  , $time); 
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
$fwrite(f,"%0t cycle :picorv32.v:218\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:221\n"  , $time); 
if (REGS_INIT_ZERO) begin 
for (i = 0; i < regfile_size; i = i+1) begin 
cpuregs[i] = 0; 
$fwrite(f,"%0t cycle :picorv32.v:223\n"  , $time); 
end 
end 
end 
`endif 
always @* begin 
pcpi_int_wr = 0; 
$fwrite(f,"%0t cycle :picorv32.v:230\n"  , $time); 
pcpi_int_rd = 32'bx; 
$fwrite(f,"%0t cycle :picorv32.v:232\n"  , $time); 
pcpi_int_wait  = |{ENABLE_PCPI && pcpi_wait,  (ENABLE_MUL || ENABLE_FAST_MUL) && pcpi_mul_wait,  ENABLE_DIV && pcpi_div_wait}; 
$fwrite(f,"%0t cycle :picorv32.v:234\n"  , $time); 
pcpi_int_ready = |{ENABLE_PCPI && pcpi_ready, (ENABLE_MUL || ENABLE_FAST_MUL) && pcpi_mul_ready, ENABLE_DIV && pcpi_div_ready}; 
$fwrite(f,"%0t cycle :picorv32.v:236\n"  , $time); 
 

(* parallel_case *) 

case (1'b1) 
ENABLE_PCPI && pcpi_ready: begin 
pcpi_int_wr = ENABLE_PCPI ? pcpi_wr : 0; 
$fwrite(f,"%0t cycle :picorv32.v:244\n"  , $time); 
pcpi_int_rd = ENABLE_PCPI ? pcpi_rd : 0; 
$fwrite(f,"%0t cycle :picorv32.v:246\n"  , $time); 
end 
(ENABLE_MUL || ENABLE_FAST_MUL) && pcpi_mul_ready: begin 
pcpi_int_wr = pcpi_mul_wr; 
$fwrite(f,"%0t cycle :picorv32.v:250\n"  , $time); 
pcpi_int_rd = pcpi_mul_rd; 
$fwrite(f,"%0t cycle :picorv32.v:252\n"  , $time); 
end 
ENABLE_DIV && pcpi_div_ready: begin 
pcpi_int_wr = pcpi_div_wr; 
$fwrite(f,"%0t cycle :picorv32.v:256\n"  , $time); 
pcpi_int_rd = pcpi_div_rd; 
$fwrite(f,"%0t cycle :picorv32.v:258\n"  , $time); 
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
$fwrite(f,"%0t cycle :picorv32.v:278\n"  , $time); 
end 
wire mem_la_firstword_xfer = COMPRESSED_ISA && mem_xfer && (!last_mem_valid ? mem_la_firstword : mem_la_firstword_reg); 
always@* begin 
$fwrite(f,"%0t cycle :picorv32.v:282\n"  , $time); 
end 
 
reg prefetched_high_word; 
reg clear_prefetched_high_word; 
reg [15:0] mem_16bit_buffer; 
 
wire [31:0] mem_rdata_latched_noshuffle; 
wire [31:0] mem_rdata_latched; 
 
wire mem_la_use_prefetched_high_word = COMPRESSED_ISA && mem_la_firstword && prefetched_high_word && !clear_prefetched_high_word; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32.v:294\n"  , $time); 
end 
assign mem_xfer = (mem_valid && mem_ready) || (mem_la_use_prefetched_high_word && mem_do_rinst); 
always@* begin 
$fwrite(f,"%0t cycle :picorv32.v:298\n"  , $time); 
end 
 
wire mem_busy = |{mem_do_prefetch, mem_do_rinst, mem_do_rdata, mem_do_wdata}; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32.v:303\n"  , $time); 
end 
wire mem_done = resetn && ((mem_xfer && |mem_state && (mem_do_rinst || mem_do_rdata || mem_do_wdata)) || (&mem_state && mem_do_rinst)) &&(!mem_la_firstword || (~&mem_rdata_latched[1:0] && mem_xfer)); 
always@* begin 
$fwrite(f,"%0t cycle :picorv32.v:307\n"  , $time); 
end 
 
assign mem_la_write = resetn && !mem_state && mem_do_wdata; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32.v:312\n"  , $time); 
end 
assign mem_la_read = resetn && ((!mem_la_use_prefetched_high_word && !mem_state && (mem_do_rinst || mem_do_prefetch || mem_do_rdata)) ||(COMPRESSED_ISA && mem_xfer && (!last_mem_valid ? mem_la_firstword : mem_la_firstword_reg) && !mem_la_secondword && &mem_rdata_latched[1:0])); 
always@* begin 
$fwrite(f,"%0t cycle :picorv32.v:316\n"  , $time); 
end 
assign mem_la_addr = (mem_do_prefetch || mem_do_rinst) ? {next_pc[31:2] + mem_la_firstword_xfer, 2'b00} : {reg_op1[31:2], 2'b00}; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32.v:320\n"  , $time); 
end 
 
assign mem_rdata_latched_noshuffle = (mem_xfer || LATCHED_MEM_RDATA) ? mem_rdata : mem_rdata_q; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32.v:325\n"  , $time); 
end 
 
assign mem_rdata_latched = COMPRESSED_ISA && mem_la_use_prefetched_high_word ? {16'bx, mem_16bit_buffer} :COMPRESSED_ISA && mem_la_secondword ? {mem_rdata_latched_noshuffle[15:0], mem_16bit_buffer} :COMPRESSED_ISA && mem_la_firstword ? {16'bx, mem_rdata_latched_noshuffle[31:16]} : mem_rdata_latched_noshuffle; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32.v:330\n"  , $time); 
end 
 
always @(posedge clk) begin 
$fwrite(f,"%0t cycle :picorv32.v:337\n"  , $time); 
if (!resetn) begin 
mem_la_firstword_reg <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:338\n"  , $time); 
last_mem_valid <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:340\n"  , $time); 
end else begin 
$fwrite(f,"%0t cycle :picorv32.v:344\n"  , $time); 
if (!last_mem_valid) begin 
mem_la_firstword_reg <= mem_la_firstword; 
$fwrite(f,"%0t cycle :picorv32.v:345\n"  , $time); 
end 
last_mem_valid <= mem_valid && !mem_ready; 
$fwrite(f,"%0t cycle :picorv32.v:348\n"  , $time); 
end 
end 
 
always @* begin 
$fwrite(f,"%0t cycle :picorv32.v:355\n"  , $time); 
(* full_case *) 
$fwrite(f,"%0t cycle :picorv32.v:357\n"  , $time); 
case (mem_wordsize) 
0: begin 
mem_la_wdata = reg_op2; 
$fwrite(f,"%0t cycle :picorv32.v:359\n"  , $time); 
mem_la_wstrb = 4'b1111; 
$fwrite(f,"%0t cycle :picorv32.v:361\n"  , $time); 
mem_rdata_word = mem_rdata; 
$fwrite(f,"%0t cycle :picorv32.v:363\n"  , $time); 
end 
1: begin 
mem_la_wdata = {2{reg_op2[15:0]}}; 
$fwrite(f,"%0t cycle :picorv32.v:367\n"  , $time); 
mem_la_wstrb = reg_op1[1] ? 4'b1100 : 4'b0011; 
$fwrite(f,"%0t cycle :picorv32.v:369\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:372\n"  , $time); 
case (reg_op1[1]) 
1'b0: begin 
mem_rdata_word = {16'b0, mem_rdata[15: 0]}; 
$fwrite(f,"%0t cycle :picorv32.v:374\n"  , $time); 
end 
1'b1: begin 
mem_rdata_word = {16'b0, mem_rdata[31:16]}; 
$fwrite(f,"%0t cycle :picorv32.v:378\n"  , $time); 
end 
endcase 
end 
2: begin 
mem_la_wdata = {4{reg_op2[7:0]}}; 
$fwrite(f,"%0t cycle :picorv32.v:384\n"  , $time); 
mem_la_wstrb = 4'b0001 << reg_op1[1:0]; 
$fwrite(f,"%0t cycle :picorv32.v:386\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:389\n"  , $time); 
case (reg_op1[1:0]) 
2'b00: begin 
mem_rdata_word = {24'b0, mem_rdata[ 7: 0]}; 
$fwrite(f,"%0t cycle :picorv32.v:391\n"  , $time); 
end 
2'b01: begin 
mem_rdata_word = {24'b0, mem_rdata[15: 8]}; 
$fwrite(f,"%0t cycle :picorv32.v:395\n"  , $time); 
end 
2'b10: begin 
mem_rdata_word = {24'b0, mem_rdata[23:16]}; 
$fwrite(f,"%0t cycle :picorv32.v:399\n"  , $time); 
end 
2'b11: begin 
mem_rdata_word = {24'b0, mem_rdata[31:24]}; 
$fwrite(f,"%0t cycle :picorv32.v:403\n"  , $time); 
end 
endcase 
end 
endcase 
end 
 
always @(posedge clk) begin 
$fwrite(f,"%0t cycle :picorv32.v:413\n"  , $time); 
if (mem_xfer) begin 
mem_rdata_q <= COMPRESSED_ISA ? mem_rdata_latched : mem_rdata; 
$fwrite(f,"%0t cycle :picorv32.v:414\n"  , $time); 
next_insn_opcode <= COMPRESSED_ISA ? mem_rdata_latched : mem_rdata; 
$fwrite(f,"%0t cycle :picorv32.v:416\n"  , $time); 
end 
 
$fwrite(f,"%0t cycle :picorv32.v:421\n"  , $time); 
if (COMPRESSED_ISA && mem_done && (mem_do_prefetch || mem_do_rinst)) begin 
$fwrite(f,"%0t cycle :picorv32.v:423\n"  , $time); 
case (mem_rdata_latched[1:0]) 
2'b00: begin // Quadrant 0 
$fwrite(f,"%0t cycle :picorv32.v:426\n"  , $time); 
case (mem_rdata_latched[15:13]) 
3'b000: begin // C.ADDI4SPN 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0t cycle :picorv32.v:428\n"  , $time); 
mem_rdata_q[31:20] <= {2'b0, mem_rdata_latched[10:7], mem_rdata_latched[12:11], mem_rdata_latched[5], mem_rdata_latched[6], 2'b00}; 
$fwrite(f,"%0t cycle :picorv32.v:430\n"  , $time); 
end 
3'b010: begin // C.LW 
mem_rdata_q[31:20] <= {5'b0, mem_rdata_latched[5], mem_rdata_latched[12:10], mem_rdata_latched[6], 2'b00}; 
$fwrite(f,"%0t cycle :picorv32.v:434\n"  , $time); 
mem_rdata_q[14:12] <= 3'b 010; 
$fwrite(f,"%0t cycle :picorv32.v:436\n"  , $time); 
end 
3'b 110: begin // C.SW 
{mem_rdata_q[31:25], mem_rdata_q[11:7]} <= {5'b0, mem_rdata_latched[5], mem_rdata_latched[12:10], mem_rdata_latched[6], 2'b00}; 
$fwrite(f,"%0t cycle :picorv32.v:440\n"  , $time); 
mem_rdata_q[14:12] <= 3'b 010; 
$fwrite(f,"%0t cycle :picorv32.v:442\n"  , $time); 
end 
endcase 
end 
2'b01: begin // Quadrant 1 
$fwrite(f,"%0t cycle :picorv32.v:449\n"  , $time); 
case (mem_rdata_latched[15:13]) 
3'b 000: begin // C.ADDI 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0t cycle :picorv32.v:451\n"  , $time); 
mem_rdata_q[31:20] <= $signed({mem_rdata_latched[12], mem_rdata_latched[6:2]}); 
$fwrite(f,"%0t cycle :picorv32.v:453\n"  , $time); 
end 
3'b 010: begin // C.LI 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0t cycle :picorv32.v:457\n"  , $time); 
mem_rdata_q[31:20] <= $signed({mem_rdata_latched[12], mem_rdata_latched[6:2]}); 
$fwrite(f,"%0t cycle :picorv32.v:459\n"  , $time); 
end 
3'b 011: begin 
$fwrite(f,"%0t cycle :picorv32.v:463\n"  , $time); 
if (mem_rdata_latched[11:7] == 2) begin // C.ADDI16SP 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0t cycle :picorv32.v:465\n"  , $time); 
mem_rdata_q[31:20] <= $signed({mem_rdata_latched[12], mem_rdata_latched[4:3],mem_rdata_latched[5], mem_rdata_latched[2], mem_rdata_latched[6], 4'b 0000}); 
$fwrite(f,"%0t cycle :picorv32.v:467\n"  , $time); 
end else begin // C.LUI 
mem_rdata_q[31:12] <= $signed({mem_rdata_latched[12], mem_rdata_latched[6:2]}); 
$fwrite(f,"%0t cycle :picorv32.v:470\n"  , $time); 
end 
end 
3'b100: begin 
$fwrite(f,"%0t cycle :picorv32.v:475\n"  , $time); 
if (mem_rdata_latched[11:10] == 2'b00) begin // C.SRLI 
mem_rdata_q[31:25] <= 7'b0000000; 
$fwrite(f,"%0t cycle :picorv32.v:477\n"  , $time); 
mem_rdata_q[14:12] <= 3'b 101; 
$fwrite(f,"%0t cycle :picorv32.v:479\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:482\n"  , $time); 
if (mem_rdata_latched[11:10] == 2'b01) begin // C.SRAI 
mem_rdata_q[31:25] <= 7'b0100000; 
$fwrite(f,"%0t cycle :picorv32.v:484\n"  , $time); 
mem_rdata_q[14:12] <= 3'b 101; 
$fwrite(f,"%0t cycle :picorv32.v:486\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:489\n"  , $time); 
if (mem_rdata_latched[11:10] == 2'b10) begin // C.ANDI 
mem_rdata_q[14:12] <= 3'b111; 
$fwrite(f,"%0t cycle :picorv32.v:491\n"  , $time); 
mem_rdata_q[31:20] <= $signed({mem_rdata_latched[12], mem_rdata_latched[6:2]}); 
$fwrite(f,"%0t cycle :picorv32.v:493\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:496\n"  , $time); 
if (mem_rdata_latched[12:10] == 3'b011) begin // C.SUB, C.XOR, C.OR, C.AND 
$fwrite(f,"%0t cycle :picorv32.v:498\n"  , $time); 
if (mem_rdata_latched[6:5] == 2'b00) begin 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0t cycle :picorv32.v:500\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:503\n"  , $time); 
if (mem_rdata_latched[6:5] == 2'b01) begin 
mem_rdata_q[14:12] <= 3'b100; 
$fwrite(f,"%0t cycle :picorv32.v:505\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:508\n"  , $time); 
if (mem_rdata_latched[6:5] == 2'b10) begin 
mem_rdata_q[14:12] <= 3'b110; 
$fwrite(f,"%0t cycle :picorv32.v:510\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:513\n"  , $time); 
if (mem_rdata_latched[6:5] == 2'b11) begin 
mem_rdata_q[14:12] <= 3'b111; 
$fwrite(f,"%0t cycle :picorv32.v:515\n"  , $time); 
end 
mem_rdata_q[31:25] <= mem_rdata_latched[6:5] == 2'b00 ? 7'b0100000 : 7'b0000000; 
$fwrite(f,"%0t cycle :picorv32.v:518\n"  , $time); 
end 
end 
3'b 110: begin // C.BEQZ 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0t cycle :picorv32.v:523\n"  , $time); 
{ mem_rdata_q[31], mem_rdata_q[7], mem_rdata_q[30:25], mem_rdata_q[11:8] } <=$signed({mem_rdata_latched[12], mem_rdata_latched[6:5], mem_rdata_latched[2],mem_rdata_latched[11:10], mem_rdata_latched[4:3]}); 
$fwrite(f,"%0t cycle :picorv32.v:525\n"  , $time); 
end 
3'b 111: begin // C.BNEZ 
mem_rdata_q[14:12] <= 3'b001; 
$fwrite(f,"%0t cycle :picorv32.v:529\n"  , $time); 
{ mem_rdata_q[31], mem_rdata_q[7], mem_rdata_q[30:25], mem_rdata_q[11:8] } <=$signed({mem_rdata_latched[12], mem_rdata_latched[6:5], mem_rdata_latched[2],mem_rdata_latched[11:10], mem_rdata_latched[4:3]}); 
$fwrite(f,"%0t cycle :picorv32.v:531\n"  , $time); 
end 
endcase 
end 
2'b10: begin // Quadrant 2 
$fwrite(f,"%0t cycle :picorv32.v:538\n"  , $time); 
case (mem_rdata_latched[15:13]) 
3'b000: begin // C.SLLI 
mem_rdata_q[31:25] <= 7'b0000000; 
$fwrite(f,"%0t cycle :picorv32.v:540\n"  , $time); 
mem_rdata_q[14:12] <= 3'b 001; 
$fwrite(f,"%0t cycle :picorv32.v:542\n"  , $time); 
end 
3'b010: begin // C.LWSP 
mem_rdata_q[31:20] <= {4'b0, mem_rdata_latched[3:2], mem_rdata_latched[12], mem_rdata_latched[6:4], 2'b00}; 
$fwrite(f,"%0t cycle :picorv32.v:546\n"  , $time); 
mem_rdata_q[14:12] <= 3'b 010; 
$fwrite(f,"%0t cycle :picorv32.v:548\n"  , $time); 
end 
3'b100: begin 
$fwrite(f,"%0t cycle :picorv32.v:552\n"  , $time); 
if (mem_rdata_latched[12] == 0 && mem_rdata_latched[6:2] == 0) begin // C.JR 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0t cycle :picorv32.v:554\n"  , $time); 
mem_rdata_q[31:20] <= 12'b0; 
$fwrite(f,"%0t cycle :picorv32.v:556\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:559\n"  , $time); 
if (mem_rdata_latched[12] == 0 && mem_rdata_latched[6:2] != 0) begin // C.MV 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0t cycle :picorv32.v:561\n"  , $time); 
mem_rdata_q[31:25] <= 7'b0000000; 
$fwrite(f,"%0t cycle :picorv32.v:563\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:566\n"  , $time); 
if (mem_rdata_latched[12] != 0 && mem_rdata_latched[11:7] != 0 && mem_rdata_latched[6:2] == 0) begin // C.JALR 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0t cycle :picorv32.v:568\n"  , $time); 
mem_rdata_q[31:20] <= 12'b0; 
$fwrite(f,"%0t cycle :picorv32.v:570\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:573\n"  , $time); 
if (mem_rdata_latched[12] != 0 && mem_rdata_latched[6:2] != 0) begin // C.ADD 
mem_rdata_q[14:12] <= 3'b000; 
$fwrite(f,"%0t cycle :picorv32.v:575\n"  , $time); 
mem_rdata_q[31:25] <= 7'b0000000; 
$fwrite(f,"%0t cycle :picorv32.v:577\n"  , $time); 
end 
end 
3'b110: begin // C.SWSP 
{mem_rdata_q[31:25], mem_rdata_q[11:7]} <= {4'b0, mem_rdata_latched[8:7], mem_rdata_latched[12:9], 2'b00}; 
$fwrite(f,"%0t cycle :picorv32.v:582\n"  , $time); 
mem_rdata_q[14:12] <= 3'b 010; 
$fwrite(f,"%0t cycle :picorv32.v:584\n"  , $time); 
end 
endcase 
end 
endcase 
end 
end 
 
always @(posedge clk) begin 
$fwrite(f,"%0t cycle :picorv32.v:595\n"  , $time); 
if (!resetn || trap) begin 
$fwrite(f,"%0t cycle :picorv32.v:597\n"  , $time); 
if (!resetn) begin 
mem_state <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:598\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:602\n"  , $time); 
if (!resetn || mem_ready) begin 
mem_valid <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:603\n"  , $time); 
end 
mem_la_secondword <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:606\n"  , $time); 
prefetched_high_word <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:608\n"  , $time); 
end else begin 
$fwrite(f,"%0t cycle :picorv32.v:612\n"  , $time); 
if (mem_la_read || mem_la_write) begin 
mem_addr <= mem_la_addr; 
$fwrite(f,"%0t cycle :picorv32.v:613\n"  , $time); 
mem_wstrb <= mem_la_wstrb & {4{mem_la_write}}; 
$fwrite(f,"%0t cycle :picorv32.v:615\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:619\n"  , $time); 
if (mem_la_write) begin 
mem_wdata <= mem_la_wdata; 
$fwrite(f,"%0t cycle :picorv32.v:620\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:624\n"  , $time); 
case (mem_state) 
0: begin 
$fwrite(f,"%0t cycle :picorv32.v:627\n"  , $time); 
if (mem_do_prefetch || mem_do_rinst || mem_do_rdata) begin 
mem_valid <= !mem_la_use_prefetched_high_word; 
$fwrite(f,"%0t cycle :picorv32.v:628\n"  , $time); 
mem_instr <= mem_do_prefetch || mem_do_rinst; 
$fwrite(f,"%0t cycle :picorv32.v:630\n"  , $time); 
mem_wstrb <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:632\n"  , $time); 
mem_state <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:634\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:638\n"  , $time); 
if (mem_do_wdata) begin 
mem_valid <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:639\n"  , $time); 
mem_instr <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:641\n"  , $time); 
mem_state <= 2; 
$fwrite(f,"%0t cycle :picorv32.v:643\n"  , $time); 
end 
end 
1: begin 
$fwrite(f,"%0t cycle :picorv32.v:649\n"  , $time); 
if (mem_xfer) begin 
$fwrite(f,"%0t cycle :picorv32.v:651\n"  , $time); 
if (COMPRESSED_ISA && mem_la_read) begin 
mem_valid <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:652\n"  , $time); 
mem_la_secondword <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:654\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:657\n"  , $time); 
if (!mem_la_use_prefetched_high_word) begin 
mem_16bit_buffer <= mem_rdata[31:16]; 
$fwrite(f,"%0t cycle :picorv32.v:658\n"  , $time); 
end 
end else begin 
mem_valid <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:662\n"  , $time); 
mem_la_secondword <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:664\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:667\n"  , $time); 
if (COMPRESSED_ISA && !mem_do_rdata) begin 
$fwrite(f,"%0t cycle :picorv32.v:669\n"  , $time); 
if (~&mem_rdata[1:0] || mem_la_secondword) begin 
mem_16bit_buffer <= mem_rdata[31:16]; 
$fwrite(f,"%0t cycle :picorv32.v:670\n"  , $time); 
prefetched_high_word <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:672\n"  , $time); 
end else begin 
prefetched_high_word <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:675\n"  , $time); 
end 
end 
mem_state <= mem_do_rinst || mem_do_rdata ? 0 : 3; 
$fwrite(f,"%0t cycle :picorv32.v:679\n"  , $time); 
end 
end 
end 
2: begin 
 
$fwrite(f,"%0t cycle :picorv32.v:687\n"  , $time); 
if (mem_xfer) begin 
mem_valid <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:688\n"  , $time); 
mem_state <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:690\n"  , $time); 
end 
end 
3: begin 
 
$fwrite(f,"%0t cycle :picorv32.v:697\n"  , $time); 
if (mem_do_rinst) begin 
mem_state <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:698\n"  , $time); 
end 
end 
endcase 
end 
 
$fwrite(f,"%0t cycle :picorv32.v:706\n"  , $time); 
if (clear_prefetched_high_word) begin 
prefetched_high_word <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:707\n"  , $time); 
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
$fwrite(f,"%0t cycle :picorv32.v:747\n"  , $time); 
end 
 
wire is_rdcycle_rdcycleh_rdinstr_rdinstrh; 
assign is_rdcycle_rdcycleh_rdinstr_rdinstrh = |{instr_rdcycle, instr_rdcycleh, instr_rdinstr, instr_rdinstrh}; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32.v:753\n"  , $time); 
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
$fwrite(f,"%0t cycle :picorv32.v:770\n"  , $time); 
 
$fwrite(f,"%0t cycle :picorv32.v:774\n"  , $time); 
if (instr_lui) begin 
new_ascii_instr = "lui"; 
$fwrite(f,"%0t cycle :picorv32.v:775\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:779\n"  , $time); 
if (instr_auipc) begin 
new_ascii_instr = "auipc"; 
$fwrite(f,"%0t cycle :picorv32.v:780\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:784\n"  , $time); 
if (instr_jal) begin 
new_ascii_instr = "jal"; 
$fwrite(f,"%0t cycle :picorv32.v:785\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:789\n"  , $time); 
if (instr_jalr) begin 
new_ascii_instr = "jalr"; 
$fwrite(f,"%0t cycle :picorv32.v:790\n"  , $time); 
end 
 
$fwrite(f,"%0t cycle :picorv32.v:795\n"  , $time); 
if (instr_beq) begin 
new_ascii_instr = "beq"; 
$fwrite(f,"%0t cycle :picorv32.v:796\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:800\n"  , $time); 
if (instr_bne) begin 
new_ascii_instr = "bne"; 
$fwrite(f,"%0t cycle :picorv32.v:801\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:805\n"  , $time); 
if (instr_blt) begin 
new_ascii_instr = "blt"; 
$fwrite(f,"%0t cycle :picorv32.v:806\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:810\n"  , $time); 
if (instr_bge) begin 
new_ascii_instr = "bge"; 
$fwrite(f,"%0t cycle :picorv32.v:811\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:815\n"  , $time); 
if (instr_bltu) begin 
new_ascii_instr = "bltu"; 
$fwrite(f,"%0t cycle :picorv32.v:816\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:820\n"  , $time); 
if (instr_bgeu) begin 
new_ascii_instr = "bgeu"; 
$fwrite(f,"%0t cycle :picorv32.v:821\n"  , $time); 
end 
 
$fwrite(f,"%0t cycle :picorv32.v:826\n"  , $time); 
if (instr_lb) begin 
new_ascii_instr = "lb"; 
$fwrite(f,"%0t cycle :picorv32.v:827\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:831\n"  , $time); 
if (instr_lh) begin 
new_ascii_instr = "lh"; 
$fwrite(f,"%0t cycle :picorv32.v:832\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:836\n"  , $time); 
if (instr_lw) begin 
new_ascii_instr = "lw"; 
$fwrite(f,"%0t cycle :picorv32.v:837\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:841\n"  , $time); 
if (instr_lbu) begin 
new_ascii_instr = "lbu"; 
$fwrite(f,"%0t cycle :picorv32.v:842\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:846\n"  , $time); 
if (instr_lhu) begin 
new_ascii_instr = "lhu"; 
$fwrite(f,"%0t cycle :picorv32.v:847\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:851\n"  , $time); 
if (instr_sb) begin 
new_ascii_instr = "sb"; 
$fwrite(f,"%0t cycle :picorv32.v:852\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:856\n"  , $time); 
if (instr_sh) begin 
new_ascii_instr = "sh"; 
$fwrite(f,"%0t cycle :picorv32.v:857\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:861\n"  , $time); 
if (instr_sw) begin 
new_ascii_instr = "sw"; 
$fwrite(f,"%0t cycle :picorv32.v:862\n"  , $time); 
end 
 
$fwrite(f,"%0t cycle :picorv32.v:867\n"  , $time); 
if (instr_addi) begin 
new_ascii_instr = "addi"; 
$fwrite(f,"%0t cycle :picorv32.v:868\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:872\n"  , $time); 
if (instr_slti) begin 
new_ascii_instr = "slti"; 
$fwrite(f,"%0t cycle :picorv32.v:873\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:877\n"  , $time); 
if (instr_sltiu) begin 
new_ascii_instr = "sltiu"; 
$fwrite(f,"%0t cycle :picorv32.v:878\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:882\n"  , $time); 
if (instr_xori) begin 
new_ascii_instr = "xori"; 
$fwrite(f,"%0t cycle :picorv32.v:883\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:887\n"  , $time); 
if (instr_ori) begin 
new_ascii_instr = "ori"; 
$fwrite(f,"%0t cycle :picorv32.v:888\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:892\n"  , $time); 
if (instr_andi) begin 
new_ascii_instr = "andi"; 
$fwrite(f,"%0t cycle :picorv32.v:893\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:897\n"  , $time); 
if (instr_slli) begin 
new_ascii_instr = "slli"; 
$fwrite(f,"%0t cycle :picorv32.v:898\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:902\n"  , $time); 
if (instr_srli) begin 
new_ascii_instr = "srli"; 
$fwrite(f,"%0t cycle :picorv32.v:903\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:907\n"  , $time); 
if (instr_srai) begin 
new_ascii_instr = "srai"; 
$fwrite(f,"%0t cycle :picorv32.v:908\n"  , $time); 
end 
 
$fwrite(f,"%0t cycle :picorv32.v:913\n"  , $time); 
if (instr_add) begin 
new_ascii_instr = "add"; 
$fwrite(f,"%0t cycle :picorv32.v:914\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:918\n"  , $time); 
if (instr_sub) begin 
new_ascii_instr = "sub"; 
$fwrite(f,"%0t cycle :picorv32.v:919\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:923\n"  , $time); 
if (instr_sll) begin 
new_ascii_instr = "sll"; 
$fwrite(f,"%0t cycle :picorv32.v:924\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:928\n"  , $time); 
if (instr_slt) begin 
new_ascii_instr = "slt"; 
$fwrite(f,"%0t cycle :picorv32.v:929\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:933\n"  , $time); 
if (instr_sltu) begin 
new_ascii_instr = "sltu"; 
$fwrite(f,"%0t cycle :picorv32.v:934\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:938\n"  , $time); 
if (instr_xor) begin 
new_ascii_instr = "xor"; 
$fwrite(f,"%0t cycle :picorv32.v:939\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:943\n"  , $time); 
if (instr_srl) begin 
new_ascii_instr = "srl"; 
$fwrite(f,"%0t cycle :picorv32.v:944\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:948\n"  , $time); 
if (instr_sra) begin 
new_ascii_instr = "sra"; 
$fwrite(f,"%0t cycle :picorv32.v:949\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:953\n"  , $time); 
if (instr_or) begin 
new_ascii_instr = "or"; 
$fwrite(f,"%0t cycle :picorv32.v:954\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:958\n"  , $time); 
if (instr_and) begin 
new_ascii_instr = "and"; 
$fwrite(f,"%0t cycle :picorv32.v:959\n"  , $time); 
end 
 
$fwrite(f,"%0t cycle :picorv32.v:964\n"  , $time); 
if (instr_rdcycle) begin 
new_ascii_instr = "rdcycle"; 
$fwrite(f,"%0t cycle :picorv32.v:965\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:969\n"  , $time); 
if (instr_rdcycleh) begin 
new_ascii_instr = "rdcycleh"; 
$fwrite(f,"%0t cycle :picorv32.v:970\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:974\n"  , $time); 
if (instr_rdinstr) begin 
new_ascii_instr = "rdinstr"; 
$fwrite(f,"%0t cycle :picorv32.v:975\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:979\n"  , $time); 
if (instr_rdinstrh) begin 
new_ascii_instr = "rdinstrh"; 
$fwrite(f,"%0t cycle :picorv32.v:980\n"  , $time); 
end 
 
$fwrite(f,"%0t cycle :picorv32.v:985\n"  , $time); 
if (instr_getq) begin 
new_ascii_instr = "getq"; 
$fwrite(f,"%0t cycle :picorv32.v:986\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:990\n"  , $time); 
if (instr_setq) begin 
new_ascii_instr = "setq"; 
$fwrite(f,"%0t cycle :picorv32.v:991\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:995\n"  , $time); 
if (instr_retirq) begin 
new_ascii_instr = "retirq"; 
$fwrite(f,"%0t cycle :picorv32.v:996\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:1000\n"  , $time); 
if (instr_maskirq) begin 
new_ascii_instr = "maskirq"; 
$fwrite(f,"%0t cycle :picorv32.v:1001\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:1005\n"  , $time); 
if (instr_waitirq) begin 
new_ascii_instr = "waitirq"; 
$fwrite(f,"%0t cycle :picorv32.v:1006\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:1010\n"  , $time); 
if (instr_timer) begin 
new_ascii_instr = "timer"; 
$fwrite(f,"%0t cycle :picorv32.v:1011\n"  , $time); 
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
$fwrite(f,"%0t cycle :picorv32.v:1035\n"  , $time); 
q_insn_imm <= dbg_insn_imm; 
$fwrite(f,"%0t cycle :picorv32.v:1037\n"  , $time); 
q_insn_opcode <= dbg_insn_opcode; 
$fwrite(f,"%0t cycle :picorv32.v:1039\n"  , $time); 
q_insn_rs1 <= dbg_insn_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:1041\n"  , $time); 
q_insn_rs2 <= dbg_insn_rs2; 
$fwrite(f,"%0t cycle :picorv32.v:1043\n"  , $time); 
q_insn_rd <= dbg_insn_rd; 
$fwrite(f,"%0t cycle :picorv32.v:1045\n"  , $time); 
dbg_next <= launch_next_insn; 
$fwrite(f,"%0t cycle :picorv32.v:1047\n"  , $time); 
 
$fwrite(f,"%0t cycle :picorv32.v:1052\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:1056\n"  , $time); 
if (!resetn || trap) begin 
dbg_valid_insn <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1053\n"  , $time); 
end 
else if (launch_next_insn) begin 
dbg_valid_insn <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:1057\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:1061\n"  , $time); 
if (decoder_trigger_q) begin 
cached_ascii_instr <= new_ascii_instr; 
$fwrite(f,"%0t cycle :picorv32.v:1062\n"  , $time); 
cached_insn_imm <= decoded_imm; 
$fwrite(f,"%0t cycle :picorv32.v:1064\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:1067\n"  , $time); 
if (&next_insn_opcode[1:0]) begin 
cached_insn_opcode <= next_insn_opcode; 
$fwrite(f,"%0t cycle :picorv32.v:1068\n"  , $time); 
end 
else 
cached_insn_opcode <= {16'b0, next_insn_opcode[15:0]}; 
$fwrite(f,"%0t cycle :picorv32.v:1072\n"  , $time); 
cached_insn_rs1 <= decoded_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:1074\n"  , $time); 
cached_insn_rs2 <= decoded_rs2; 
$fwrite(f,"%0t cycle :picorv32.v:1076\n"  , $time); 
cached_insn_rd <= decoded_rd; 
$fwrite(f,"%0t cycle :picorv32.v:1078\n"  , $time); 
end 
 
$fwrite(f,"%0t cycle :picorv32.v:1083\n"  , $time); 
if (launch_next_insn) begin 
dbg_insn_addr <= next_pc; 
$fwrite(f,"%0t cycle :picorv32.v:1084\n"  , $time); 
end 
end 
 
always @* begin 
dbg_ascii_instr = q_ascii_instr; 
$fwrite(f,"%0t cycle :picorv32.v:1090\n"  , $time); 
dbg_insn_imm = q_insn_imm; 
$fwrite(f,"%0t cycle :picorv32.v:1092\n"  , $time); 
dbg_insn_opcode = q_insn_opcode; 
$fwrite(f,"%0t cycle :picorv32.v:1094\n"  , $time); 
dbg_insn_rs1 = q_insn_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:1096\n"  , $time); 
dbg_insn_rs2 = q_insn_rs2; 
$fwrite(f,"%0t cycle :picorv32.v:1098\n"  , $time); 
dbg_insn_rd = q_insn_rd; 
$fwrite(f,"%0t cycle :picorv32.v:1100\n"  , $time); 
 
$fwrite(f,"%0t cycle :picorv32.v:1104\n"  , $time); 
if (dbg_next) begin 
$fwrite(f,"%0t cycle :picorv32.v:1106\n"  , $time); 
if (decoder_pseudo_trigger_q) begin 
dbg_ascii_instr = cached_ascii_instr; 
$fwrite(f,"%0t cycle :picorv32.v:1107\n"  , $time); 
dbg_insn_imm = cached_insn_imm; 
$fwrite(f,"%0t cycle :picorv32.v:1109\n"  , $time); 
dbg_insn_opcode = cached_insn_opcode; 
$fwrite(f,"%0t cycle :picorv32.v:1111\n"  , $time); 
dbg_insn_rs1 = cached_insn_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:1113\n"  , $time); 
dbg_insn_rs2 = cached_insn_rs2; 
$fwrite(f,"%0t cycle :picorv32.v:1115\n"  , $time); 
dbg_insn_rd = cached_insn_rd; 
$fwrite(f,"%0t cycle :picorv32.v:1117\n"  , $time); 
end else begin 
dbg_ascii_instr = new_ascii_instr; 
$fwrite(f,"%0t cycle :picorv32.v:1120\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:1123\n"  , $time); 
if (&next_insn_opcode[1:0]) begin 
dbg_insn_opcode = next_insn_opcode; 
$fwrite(f,"%0t cycle :picorv32.v:1124\n"  , $time); 
end 
else 
dbg_insn_opcode = {16'b0, next_insn_opcode[15:0]}; 
$fwrite(f,"%0t cycle :picorv32.v:1128\n"  , $time); 
dbg_insn_imm = decoded_imm; 
$fwrite(f,"%0t cycle :picorv32.v:1130\n"  , $time); 
dbg_insn_rs1 = decoded_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:1132\n"  , $time); 
dbg_insn_rs2 = decoded_rs2; 
$fwrite(f,"%0t cycle :picorv32.v:1134\n"  , $time); 
dbg_insn_rd = decoded_rd; 
$fwrite(f,"%0t cycle :picorv32.v:1136\n"  , $time); 
end 
end 
end 
 
`ifdef DEBUGASM 
always @(posedge clk) begin 
$fwrite(f,"%0t cycle :picorv32.v:1145\n"  , $time); 
if (dbg_next) begin 
$display("debugasm %x %x %s", dbg_insn_addr, dbg_insn_opcode, dbg_ascii_instr ? dbg_ascii_instr : "*"); 
end 
end 
`endif 
 
`ifdef DEBUG 
always @(posedge clk) begin 
$fwrite(f,"%0t cycle :picorv32.v:1154\n"  , $time); 
if (dbg_next) begin 
$fwrite(f,"%0t cycle :picorv32.v:1156\n"  , $time); 
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
$fwrite(f,"%0t cycle :picorv32.v:1166\n"  , $time); 
is_lui_auipc_jal_jalr_addi_add_sub <= |{instr_lui, instr_auipc, instr_jal, instr_jalr, instr_addi, instr_add, instr_sub}; 
$fwrite(f,"%0t cycle :picorv32.v:1168\n"  , $time); 
is_slti_blt_slt <= |{instr_slti, instr_blt, instr_slt}; 
$fwrite(f,"%0t cycle :picorv32.v:1170\n"  , $time); 
is_sltiu_bltu_sltu <= |{instr_sltiu, instr_bltu, instr_sltu}; 
$fwrite(f,"%0t cycle :picorv32.v:1172\n"  , $time); 
is_lbu_lhu_lw <= |{instr_lbu, instr_lhu, instr_lw}; 
$fwrite(f,"%0t cycle :picorv32.v:1174\n"  , $time); 
is_compare <= |{is_beq_bne_blt_bge_bltu_bgeu, instr_slti, instr_slt, instr_sltiu, instr_sltu}; 
$fwrite(f,"%0t cycle :picorv32.v:1176\n"  , $time); 
 
$fwrite(f,"%0t cycle :picorv32.v:1180\n"  , $time); 
if (mem_do_rinst && mem_done) begin 
instr_lui     <= mem_rdata_latched[6:0] == 7'b0110111; 
$fwrite(f,"%0t cycle :picorv32.v:1181\n"  , $time); 
instr_auipc   <= mem_rdata_latched[6:0] == 7'b0010111; 
$fwrite(f,"%0t cycle :picorv32.v:1183\n"  , $time); 
instr_jal     <= mem_rdata_latched[6:0] == 7'b1101111; 
$fwrite(f,"%0t cycle :picorv32.v:1185\n"  , $time); 
instr_jalr    <= mem_rdata_latched[6:0] == 7'b1100111 && mem_rdata_latched[14:12] == 3'b000; 
$fwrite(f,"%0t cycle :picorv32.v:1187\n"  , $time); 
instr_retirq  <= mem_rdata_latched[6:0] == 7'b0001011 && mem_rdata_latched[31:25] == 7'b0000010 && ENABLE_IRQ; 
$fwrite(f,"%0t cycle :picorv32.v:1189\n"  , $time); 
instr_waitirq <= mem_rdata_latched[6:0] == 7'b0001011 && mem_rdata_latched[31:25] == 7'b0000100 && ENABLE_IRQ; 
$fwrite(f,"%0t cycle :picorv32.v:1191\n"  , $time); 
 
is_beq_bne_blt_bge_bltu_bgeu <= mem_rdata_latched[6:0] == 7'b1100011; 
$fwrite(f,"%0t cycle :picorv32.v:1194\n"  , $time); 
is_lb_lh_lw_lbu_lhu          <= mem_rdata_latched[6:0] == 7'b0000011; 
$fwrite(f,"%0t cycle :picorv32.v:1196\n"  , $time); 
is_sb_sh_sw                  <= mem_rdata_latched[6:0] == 7'b0100011; 
$fwrite(f,"%0t cycle :picorv32.v:1198\n"  , $time); 
is_alu_reg_imm               <= mem_rdata_latched[6:0] == 7'b0010011; 
$fwrite(f,"%0t cycle :picorv32.v:1200\n"  , $time); 
is_alu_reg_reg               <= mem_rdata_latched[6:0] == 7'b0110011; 
$fwrite(f,"%0t cycle :picorv32.v:1202\n"  , $time); 
 
{ decoded_imm_j[31:20], decoded_imm_j[10:1], decoded_imm_j[11], decoded_imm_j[19:12], decoded_imm_j[0] } <= $signed({mem_rdata_latched[31:12], 1'b0}); 
$fwrite(f,"%0t cycle :picorv32.v:1205\n"  , $time); 
 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1208\n"  , $time); 
decoded_rs1 <= mem_rdata_latched[19:15]; 
$fwrite(f,"%0t cycle :picorv32.v:1210\n"  , $time); 
decoded_rs2 <= mem_rdata_latched[24:20]; 
$fwrite(f,"%0t cycle :picorv32.v:1212\n"  , $time); 
 
$fwrite(f,"%0t cycle :picorv32.v:1215\n"  , $time); 
if (mem_rdata_latched[6:0] == 7'b0001011 && mem_rdata_latched[31:25] == 7'b0000000 && ENABLE_IRQ && ENABLE_IRQ_QREGS) begin 
decoded_rs1[regindex_bits-1] <= 1; // instr_getq 
$fwrite(f,"%0t cycle :picorv32.v:1217\n"  , $time); 
end 
 
$fwrite(f,"%0t cycle :picorv32.v:1221\n"  , $time); 
if (mem_rdata_latched[6:0] == 7'b0001011 && mem_rdata_latched[31:25] == 7'b0000010 && ENABLE_IRQ) begin 
decoded_rs1 <= ENABLE_IRQ_QREGS ? irqregs_offset : 3; // instr_retirq 
$fwrite(f,"%0t cycle :picorv32.v:1223\n"  , $time); 
end 
 
compressed_instr <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1227\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:1229\n"  , $time); 
if (COMPRESSED_ISA && mem_rdata_latched[1:0] != 2'b11) begin 
compressed_instr <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:1231\n"  , $time); 
decoded_rd <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1233\n"  , $time); 
decoded_rs1 <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1235\n"  , $time); 
decoded_rs2 <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1237\n"  , $time); 
 
{ decoded_imm_j[31:11], decoded_imm_j[4], decoded_imm_j[9:8], decoded_imm_j[10], decoded_imm_j[6], 
decoded_imm_j[7], decoded_imm_j[3:1], decoded_imm_j[5], decoded_imm_j[0] } <= $signed({mem_rdata_latched[12:2], 1'b0}); 
$fwrite(f,"%0t cycle :picorv32.v:1241\n"  , $time); 
 
$fwrite(f,"%0t cycle :picorv32.v:1245\n"  , $time); 
case (mem_rdata_latched[1:0]) 
2'b00: begin // Quadrant 0 
$fwrite(f,"%0t cycle :picorv32.v:1248\n"  , $time); 
case (mem_rdata_latched[15:13]) 
3'b000: begin // C.ADDI4SPN 
is_alu_reg_imm <= |mem_rdata_latched[12:5]; 
$fwrite(f,"%0t cycle :picorv32.v:1250\n"  , $time); 
decoded_rs1 <= 2; 
$fwrite(f,"%0t cycle :picorv32.v:1252\n"  , $time); 
decoded_rd <= 8 + mem_rdata_latched[4:2]; 
$fwrite(f,"%0t cycle :picorv32.v:1254\n"  , $time); 
end 
3'b010: begin // C.LW 
is_lb_lh_lw_lbu_lhu <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:1258\n"  , $time); 
decoded_rs1 <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1260\n"  , $time); 
decoded_rd <= 8 + mem_rdata_latched[4:2]; 
$fwrite(f,"%0t cycle :picorv32.v:1262\n"  , $time); 
end 
3'b110: begin // C.SW 
is_sb_sh_sw <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:1266\n"  , $time); 
decoded_rs1 <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1268\n"  , $time); 
decoded_rs2 <= 8 + mem_rdata_latched[4:2]; 
$fwrite(f,"%0t cycle :picorv32.v:1270\n"  , $time); 
end 
endcase 
end 
2'b01: begin // Quadrant 1 
$fwrite(f,"%0t cycle :picorv32.v:1277\n"  , $time); 
case (mem_rdata_latched[15:13]) 
3'b000: begin // C.NOP / C.ADDI 
is_alu_reg_imm <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:1279\n"  , $time); 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1281\n"  , $time); 
decoded_rs1 <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1283\n"  , $time); 
end 
3'b001: begin // C.JAL 
instr_jal <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:1287\n"  , $time); 
decoded_rd <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:1289\n"  , $time); 
end 
3'b 010: begin // C.LI 
is_alu_reg_imm <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:1293\n"  , $time); 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1295\n"  , $time); 
decoded_rs1 <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1297\n"  , $time); 
end 
3'b 011: begin 
$fwrite(f,"%0t cycle :picorv32.v:1302\n"  , $time); 
if (mem_rdata_latched[12] || mem_rdata_latched[6:2]) begin 
$fwrite(f,"%0t cycle :picorv32.v:1303\n"  , $time); 
if (mem_rdata_latched[11:7] == 2) begin // C.ADDI16SP 
is_alu_reg_imm <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:1305\n"  , $time); 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1307\n"  , $time); 
decoded_rs1 <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1309\n"  , $time); 
end else begin // C.LUI 
instr_lui <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:1312\n"  , $time); 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1314\n"  , $time); 
decoded_rs1 <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1316\n"  , $time); 
end 
end 
end 
3'b100: begin 
$fwrite(f,"%0t cycle :picorv32.v:1323\n"  , $time); 
if (!mem_rdata_latched[11] && !mem_rdata_latched[12]) begin // C.SRLI, C.SRAI 
is_alu_reg_imm <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:1324\n"  , $time); 
decoded_rd <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1326\n"  , $time); 
decoded_rs1 <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1328\n"  , $time); 
decoded_rs2 <= {mem_rdata_latched[12], mem_rdata_latched[6:2]}; 
$fwrite(f,"%0t cycle :picorv32.v:1330\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:1333\n"  , $time); 
if (mem_rdata_latched[11:10] == 2'b10) begin // C.ANDI 
is_alu_reg_imm <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:1335\n"  , $time); 
decoded_rd <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1337\n"  , $time); 
decoded_rs1 <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1339\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:1342\n"  , $time); 
if (mem_rdata_latched[12:10] == 3'b011) begin // C.SUB, C.XOR, C.OR, C.AND 
is_alu_reg_reg <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:1344\n"  , $time); 
decoded_rd <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1346\n"  , $time); 
decoded_rs1 <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1348\n"  , $time); 
decoded_rs2 <= 8 + mem_rdata_latched[4:2]; 
$fwrite(f,"%0t cycle :picorv32.v:1350\n"  , $time); 
end 
end 
3'b101: begin // C.J 
instr_jal <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:1355\n"  , $time); 
end 
3'b110: begin // C.BEQZ 
is_beq_bne_blt_bge_bltu_bgeu <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:1359\n"  , $time); 
decoded_rs1 <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1361\n"  , $time); 
decoded_rs2 <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1363\n"  , $time); 
end 
3'b111: begin // C.BNEZ 
is_beq_bne_blt_bge_bltu_bgeu <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:1367\n"  , $time); 
decoded_rs1 <= 8 + mem_rdata_latched[9:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1369\n"  , $time); 
decoded_rs2 <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1371\n"  , $time); 
end 
endcase 
end 
2'b10: begin // Quadrant 2 
$fwrite(f,"%0t cycle :picorv32.v:1378\n"  , $time); 
case (mem_rdata_latched[15:13]) 
3'b000: begin // C.SLLI 
$fwrite(f,"%0t cycle :picorv32.v:1381\n"  , $time); 
if (!mem_rdata_latched[12]) begin 
is_alu_reg_imm <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:1382\n"  , $time); 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1384\n"  , $time); 
decoded_rs1 <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1386\n"  , $time); 
decoded_rs2 <= {mem_rdata_latched[12], mem_rdata_latched[6:2]}; 
$fwrite(f,"%0t cycle :picorv32.v:1388\n"  , $time); 
end 
end 
3'b010: begin // C.LWSP 
$fwrite(f,"%0t cycle :picorv32.v:1394\n"  , $time); 
if (mem_rdata_latched[11:7]) begin 
is_lb_lh_lw_lbu_lhu <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:1395\n"  , $time); 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1397\n"  , $time); 
decoded_rs1 <= 2; 
$fwrite(f,"%0t cycle :picorv32.v:1399\n"  , $time); 
end 
end 
3'b100: begin 
$fwrite(f,"%0t cycle :picorv32.v:1404\n"  , $time); 
if (mem_rdata_latched[12] == 0 && mem_rdata_latched[11:7] != 0 && mem_rdata_latched[6:2] == 0) begin // C.JR 
instr_jalr <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:1406\n"  , $time); 
decoded_rd <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1408\n"  , $time); 
decoded_rs1 <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1410\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:1413\n"  , $time); 
if (mem_rdata_latched[12] == 0 && mem_rdata_latched[6:2] != 0) begin // C.MV 
is_alu_reg_reg <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:1415\n"  , $time); 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1417\n"  , $time); 
decoded_rs1 <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1419\n"  , $time); 
decoded_rs2 <= mem_rdata_latched[6:2]; 
$fwrite(f,"%0t cycle :picorv32.v:1421\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:1424\n"  , $time); 
if (mem_rdata_latched[12] != 0 && mem_rdata_latched[11:7] != 0 && mem_rdata_latched[6:2] == 0) begin // C.JALR 
instr_jalr <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:1426\n"  , $time); 
decoded_rd <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:1428\n"  , $time); 
decoded_rs1 <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1430\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:1433\n"  , $time); 
if (mem_rdata_latched[12] != 0 && mem_rdata_latched[6:2] != 0) begin // C.ADD 
is_alu_reg_reg <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:1435\n"  , $time); 
decoded_rd <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1437\n"  , $time); 
decoded_rs1 <= mem_rdata_latched[11:7]; 
$fwrite(f,"%0t cycle :picorv32.v:1439\n"  , $time); 
decoded_rs2 <= mem_rdata_latched[6:2]; 
$fwrite(f,"%0t cycle :picorv32.v:1441\n"  , $time); 
end 
end 
3'b110: begin // C.SWSP 
is_sb_sh_sw <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:1446\n"  , $time); 
decoded_rs1 <= 2; 
$fwrite(f,"%0t cycle :picorv32.v:1448\n"  , $time); 
decoded_rs2 <= mem_rdata_latched[6:2]; 
$fwrite(f,"%0t cycle :picorv32.v:1450\n"  , $time); 
end 
endcase 
end 
endcase 
end 
end 
 
$fwrite(f,"%0t cycle :picorv32.v:1460\n"  , $time); 
if (decoder_trigger && !decoder_pseudo_trigger) begin 
pcpi_insn <= WITH_PCPI ? mem_rdata_q : 'bx; 
$fwrite(f,"%0t cycle :picorv32.v:1461\n"  , $time); 
 
instr_beq   <= is_beq_bne_blt_bge_bltu_bgeu && mem_rdata_q[14:12] == 3'b000; 
$fwrite(f,"%0t cycle :picorv32.v:1464\n"  , $time); 
instr_bne   <= is_beq_bne_blt_bge_bltu_bgeu && mem_rdata_q[14:12] == 3'b001; 
$fwrite(f,"%0t cycle :picorv32.v:1466\n"  , $time); 
instr_blt   <= is_beq_bne_blt_bge_bltu_bgeu && mem_rdata_q[14:12] == 3'b100; 
$fwrite(f,"%0t cycle :picorv32.v:1468\n"  , $time); 
instr_bge   <= is_beq_bne_blt_bge_bltu_bgeu && mem_rdata_q[14:12] == 3'b101; 
$fwrite(f,"%0t cycle :picorv32.v:1470\n"  , $time); 
instr_bltu  <= is_beq_bne_blt_bge_bltu_bgeu && mem_rdata_q[14:12] == 3'b110; 
$fwrite(f,"%0t cycle :picorv32.v:1472\n"  , $time); 
instr_bgeu  <= is_beq_bne_blt_bge_bltu_bgeu && mem_rdata_q[14:12] == 3'b111; 
$fwrite(f,"%0t cycle :picorv32.v:1474\n"  , $time); 
 
instr_lb    <= is_lb_lh_lw_lbu_lhu && mem_rdata_q[14:12] == 3'b000; 
$fwrite(f,"%0t cycle :picorv32.v:1477\n"  , $time); 
instr_lh    <= is_lb_lh_lw_lbu_lhu && mem_rdata_q[14:12] == 3'b001; 
$fwrite(f,"%0t cycle :picorv32.v:1479\n"  , $time); 
instr_lw    <= is_lb_lh_lw_lbu_lhu && mem_rdata_q[14:12] == 3'b010; 
$fwrite(f,"%0t cycle :picorv32.v:1481\n"  , $time); 
instr_lbu   <= is_lb_lh_lw_lbu_lhu && mem_rdata_q[14:12] == 3'b100; 
$fwrite(f,"%0t cycle :picorv32.v:1483\n"  , $time); 
instr_lhu   <= is_lb_lh_lw_lbu_lhu && mem_rdata_q[14:12] == 3'b101; 
$fwrite(f,"%0t cycle :picorv32.v:1485\n"  , $time); 
 
instr_sb    <= is_sb_sh_sw && mem_rdata_q[14:12] == 3'b000; 
$fwrite(f,"%0t cycle :picorv32.v:1488\n"  , $time); 
instr_sh    <= is_sb_sh_sw && mem_rdata_q[14:12] == 3'b001; 
$fwrite(f,"%0t cycle :picorv32.v:1490\n"  , $time); 
instr_sw    <= is_sb_sh_sw && mem_rdata_q[14:12] == 3'b010; 
$fwrite(f,"%0t cycle :picorv32.v:1492\n"  , $time); 
 
instr_addi  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b000; 
$fwrite(f,"%0t cycle :picorv32.v:1495\n"  , $time); 
instr_slti  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b010; 
$fwrite(f,"%0t cycle :picorv32.v:1497\n"  , $time); 
instr_sltiu <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b011; 
$fwrite(f,"%0t cycle :picorv32.v:1499\n"  , $time); 
instr_xori  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b100; 
$fwrite(f,"%0t cycle :picorv32.v:1501\n"  , $time); 
instr_ori   <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b110; 
$fwrite(f,"%0t cycle :picorv32.v:1503\n"  , $time); 
instr_andi  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b111; 
$fwrite(f,"%0t cycle :picorv32.v:1505\n"  , $time); 
 
instr_slli  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b001 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0t cycle :picorv32.v:1508\n"  , $time); 
instr_srli  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b101 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0t cycle :picorv32.v:1510\n"  , $time); 
instr_srai  <= is_alu_reg_imm && mem_rdata_q[14:12] == 3'b101 && mem_rdata_q[31:25] == 7'b0100000; 
$fwrite(f,"%0t cycle :picorv32.v:1512\n"  , $time); 
 
instr_add   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b000 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0t cycle :picorv32.v:1515\n"  , $time); 
instr_sub   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b000 && mem_rdata_q[31:25] == 7'b0100000; 
$fwrite(f,"%0t cycle :picorv32.v:1517\n"  , $time); 
instr_sll   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b001 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0t cycle :picorv32.v:1519\n"  , $time); 
instr_slt   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b010 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0t cycle :picorv32.v:1521\n"  , $time); 
instr_sltu  <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b011 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0t cycle :picorv32.v:1523\n"  , $time); 
instr_xor   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b100 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0t cycle :picorv32.v:1525\n"  , $time); 
instr_srl   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b101 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0t cycle :picorv32.v:1527\n"  , $time); 
instr_sra   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b101 && mem_rdata_q[31:25] == 7'b0100000; 
$fwrite(f,"%0t cycle :picorv32.v:1529\n"  , $time); 
instr_or    <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b110 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0t cycle :picorv32.v:1531\n"  , $time); 
instr_and   <= is_alu_reg_reg && mem_rdata_q[14:12] == 3'b111 && mem_rdata_q[31:25] == 7'b0000000; 
$fwrite(f,"%0t cycle :picorv32.v:1533\n"  , $time); 
 
instr_rdcycle  <= ((mem_rdata_q[6:0] == 7'b1110011 && mem_rdata_q[31:12] == 'b11000000000000000010) ||(mem_rdata_q[6:0] == 7'b1110011 && mem_rdata_q[31:12] == 'b11000000000100000010)) && ENABLE_COUNTERS; 
$fwrite(f,"%0t cycle :picorv32.v:1536\n"  , $time); 
instr_rdcycleh <= ((mem_rdata_q[6:0] == 7'b1110011 && mem_rdata_q[31:12] == 'b11001000000000000010) ||(mem_rdata_q[6:0] == 7'b1110011 && mem_rdata_q[31:12] == 'b11001000000100000010)) && ENABLE_COUNTERS && ENABLE_COUNTERS64; 
$fwrite(f,"%0t cycle :picorv32.v:1538\n"  , $time); 
instr_rdinstr  <=  (mem_rdata_q[6:0] == 7'b1110011 && mem_rdata_q[31:12] == 'b11000000001000000010) && ENABLE_COUNTERS; 
$fwrite(f,"%0t cycle :picorv32.v:1540\n"  , $time); 
instr_rdinstrh <=  (mem_rdata_q[6:0] == 7'b1110011 && mem_rdata_q[31:12] == 'b11001000001000000010) && ENABLE_COUNTERS && ENABLE_COUNTERS64; 
$fwrite(f,"%0t cycle :picorv32.v:1542\n"  , $time); 
 
instr_ecall_ebreak <= ((mem_rdata_q[6:0] == 7'b1110011 && !mem_rdata_q[31:21] && !mem_rdata_q[19:7]) ||(COMPRESSED_ISA && mem_rdata_q[15:0] == 16'h9002)); 
$fwrite(f,"%0t cycle :picorv32.v:1545\n"  , $time); 
 
instr_getq    <= mem_rdata_q[6:0] == 7'b0001011 && mem_rdata_q[31:25] == 7'b0000000 && ENABLE_IRQ && ENABLE_IRQ_QREGS; 
$fwrite(f,"%0t cycle :picorv32.v:1548\n"  , $time); 
instr_setq    <= mem_rdata_q[6:0] == 7'b0001011 && mem_rdata_q[31:25] == 7'b0000001 && ENABLE_IRQ && ENABLE_IRQ_QREGS; 
$fwrite(f,"%0t cycle :picorv32.v:1550\n"  , $time); 
instr_maskirq <= mem_rdata_q[6:0] == 7'b0001011 && mem_rdata_q[31:25] == 7'b0000011 && ENABLE_IRQ; 
$fwrite(f,"%0t cycle :picorv32.v:1552\n"  , $time); 
instr_timer   <= mem_rdata_q[6:0] == 7'b0001011 && mem_rdata_q[31:25] == 7'b0000101 && ENABLE_IRQ && ENABLE_IRQ_TIMER; 
$fwrite(f,"%0t cycle :picorv32.v:1554\n"  , $time); 
 
is_slli_srli_srai <= is_alu_reg_imm && |{mem_rdata_q[14:12] == 3'b001 && mem_rdata_q[31:25] == 7'b0000000,mem_rdata_q[14:12] == 3'b101 && mem_rdata_q[31:25] == 7'b0000000,mem_rdata_q[14:12] == 3'b101 && mem_rdata_q[31:25] == 7'b0100000}; 
$fwrite(f,"%0t cycle :picorv32.v:1557\n"  , $time); 
 
is_jalr_addi_slti_sltiu_xori_ori_andi <= instr_jalr || is_alu_reg_imm && |{mem_rdata_q[14:12] == 3'b000,mem_rdata_q[14:12] == 3'b010,mem_rdata_q[14:12] == 3'b011,mem_rdata_q[14:12] == 3'b100,mem_rdata_q[14:12] == 3'b110,mem_rdata_q[14:12] == 3'b111}; 
$fwrite(f,"%0t cycle :picorv32.v:1560\n"  , $time); 
 
is_sll_srl_sra <= is_alu_reg_reg && |{mem_rdata_q[14:12] == 3'b001 && mem_rdata_q[31:25] == 7'b0000000,mem_rdata_q[14:12] == 3'b101 && mem_rdata_q[31:25] == 7'b0000000,mem_rdata_q[14:12] == 3'b101 && mem_rdata_q[31:25] == 7'b0100000}; 
$fwrite(f,"%0t cycle :picorv32.v:1563\n"  , $time); 
 
is_lui_auipc_jal_jalr_addi_add_sub <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1566\n"  , $time); 
is_compare <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1568\n"  , $time); 
 

(* parallel_case *) 

case (1'b1) 
instr_jal: begin 
decoded_imm <= decoded_imm_j; 
$fwrite(f,"%0t cycle :picorv32.v:1576\n"  , $time); 
end 
|{instr_lui, instr_auipc}: begin 
decoded_imm <= mem_rdata_q[31:12] << 12; 
$fwrite(f,"%0t cycle :picorv32.v:1580\n"  , $time); 
end 
|{instr_jalr, is_lb_lh_lw_lbu_lhu, is_alu_reg_imm}: begin 
decoded_imm <= $signed(mem_rdata_q[31:20]); 
$fwrite(f,"%0t cycle :picorv32.v:1584\n"  , $time); 
end 
is_beq_bne_blt_bge_bltu_bgeu: begin 
decoded_imm <= $signed({mem_rdata_q[31], mem_rdata_q[7], mem_rdata_q[30:25], mem_rdata_q[11:8], 1'b0}); 
$fwrite(f,"%0t cycle :picorv32.v:1588\n"  , $time); 
end 
is_sb_sh_sw: begin 
decoded_imm <= $signed({mem_rdata_q[31:25], mem_rdata_q[11:7]}); 
$fwrite(f,"%0t cycle :picorv32.v:1592\n"  , $time); 
end 
default: begin 
decoded_imm <= 1'bx; 
$fwrite(f,"%0t cycle :picorv32.v:1596\n"  , $time); 
end 
endcase 
end 
 
$fwrite(f,"%0t cycle :picorv32.v:1603\n"  , $time); 
if (!resetn) begin 
is_beq_bne_blt_bge_bltu_bgeu <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1604\n"  , $time); 
is_compare <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1606\n"  , $time); 
 
instr_beq   <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1609\n"  , $time); 
instr_bne   <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1611\n"  , $time); 
instr_blt   <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1613\n"  , $time); 
instr_bge   <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1615\n"  , $time); 
instr_bltu  <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1617\n"  , $time); 
instr_bgeu  <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1619\n"  , $time); 
 
instr_addi  <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1622\n"  , $time); 
instr_slti  <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1624\n"  , $time); 
instr_sltiu <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1626\n"  , $time); 
instr_xori  <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1628\n"  , $time); 
instr_ori   <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1630\n"  , $time); 
instr_andi  <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1632\n"  , $time); 
 
instr_add   <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1635\n"  , $time); 
instr_sub   <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1637\n"  , $time); 
instr_sll   <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1639\n"  , $time); 
instr_slt   <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1641\n"  , $time); 
instr_sltu  <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1643\n"  , $time); 
instr_xor   <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1645\n"  , $time); 
instr_srl   <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1647\n"  , $time); 
instr_sra   <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1649\n"  , $time); 
instr_or    <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1651\n"  , $time); 
instr_and   <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1653\n"  , $time); 
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
$fwrite(f,"%0t cycle :picorv32.v:1688\n"  , $time); 
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
$fwrite(f,"%0t cycle :picorv32.v:1710\n"  , $time); 
alu_eq <= reg_op1 == reg_op2; 
$fwrite(f,"%0t cycle :picorv32.v:1712\n"  , $time); 
alu_lts <= $signed(reg_op1) < $signed(reg_op2); 
$fwrite(f,"%0t cycle :picorv32.v:1714\n"  , $time); 
alu_ltu <= reg_op1 < reg_op2; 
$fwrite(f,"%0t cycle :picorv32.v:1716\n"  , $time); 
alu_shl <= reg_op1 << reg_op2[4:0]; 
$fwrite(f,"%0t cycle :picorv32.v:1718\n"  , $time); 
alu_shr <= $signed({instr_sra || instr_srai ? reg_op1[31] : 1'b0, reg_op1}) >>> reg_op2[4:0]; 
$fwrite(f,"%0t cycle :picorv32.v:1720\n"  , $time); 
end 
end else begin 
always @* begin 
alu_add_sub = instr_sub ? reg_op1 - reg_op2 : reg_op1 + reg_op2; 
$fwrite(f,"%0t cycle :picorv32.v:1725\n"  , $time); 
alu_eq = reg_op1 == reg_op2; 
$fwrite(f,"%0t cycle :picorv32.v:1727\n"  , $time); 
alu_lts = $signed(reg_op1) < $signed(reg_op2); 
$fwrite(f,"%0t cycle :picorv32.v:1729\n"  , $time); 
alu_ltu = reg_op1 < reg_op2; 
$fwrite(f,"%0t cycle :picorv32.v:1731\n"  , $time); 
alu_shl = reg_op1 << reg_op2[4:0]; 
$fwrite(f,"%0t cycle :picorv32.v:1733\n"  , $time); 
alu_shr = $signed({instr_sra || instr_srai ? reg_op1[31] : 1'b0, reg_op1}) >>> reg_op2[4:0]; 
$fwrite(f,"%0t cycle :picorv32.v:1735\n"  , $time); 
end 
end endgenerate 
 
always @* begin 
alu_out_0 = 'bx; 
$fwrite(f,"%0t cycle :picorv32.v:1741\n"  , $time); 

(* parallel_case, full_case *) 

case (1'b1) 
instr_beq: begin 
alu_out_0 = alu_eq; 
$fwrite(f,"%0t cycle :picorv32.v:1748\n"  , $time); 
end 
instr_bne: begin 
alu_out_0 = !alu_eq; 
$fwrite(f,"%0t cycle :picorv32.v:1752\n"  , $time); 
end 
instr_bge: begin 
alu_out_0 = !alu_lts; 
$fwrite(f,"%0t cycle :picorv32.v:1756\n"  , $time); 
end 
instr_bgeu: begin 
alu_out_0 = !alu_ltu; 
$fwrite(f,"%0t cycle :picorv32.v:1760\n"  , $time); 
end 
is_slti_blt_slt && (!TWO_CYCLE_COMPARE || !{instr_beq,instr_bne,instr_bge,instr_bgeu}): begin 
alu_out_0 = alu_lts; 
$fwrite(f,"%0t cycle :picorv32.v:1764\n"  , $time); 
end 
is_sltiu_bltu_sltu && (!TWO_CYCLE_COMPARE || !{instr_beq,instr_bne,instr_bge,instr_bgeu}): begin 
alu_out_0 = alu_ltu; 
$fwrite(f,"%0t cycle :picorv32.v:1768\n"  , $time); 
end 
endcase 
 
alu_out = 'bx; 
$fwrite(f,"%0t cycle :picorv32.v:1773\n"  , $time); 

(* parallel_case, full_case *) 

case (1'b1) 
is_lui_auipc_jal_jalr_addi_add_sub: begin 
alu_out = alu_add_sub; 
$fwrite(f,"%0t cycle :picorv32.v:1780\n"  , $time); 
end 
is_compare: begin 
alu_out = alu_out_0; 
$fwrite(f,"%0t cycle :picorv32.v:1784\n"  , $time); 
end 
instr_xori || instr_xor: begin 
alu_out = reg_op1 ^ reg_op2; 
$fwrite(f,"%0t cycle :picorv32.v:1788\n"  , $time); 
end 
instr_ori || instr_or: begin 
alu_out = reg_op1 | reg_op2; 
$fwrite(f,"%0t cycle :picorv32.v:1792\n"  , $time); 
end 
instr_andi || instr_and: begin 
alu_out = reg_op1 & reg_op2; 
$fwrite(f,"%0t cycle :picorv32.v:1796\n"  , $time); 
end 
BARREL_SHIFTER && (instr_sll || instr_slli): begin 
alu_out = alu_shl; 
$fwrite(f,"%0t cycle :picorv32.v:1800\n"  , $time); 
end 
BARREL_SHIFTER && (instr_srl || instr_srli || instr_sra || instr_srai): begin 
alu_out = alu_shr; 
$fwrite(f,"%0t cycle :picorv32.v:1804\n"  , $time); 
end 
endcase 
 
`ifdef RISCV_FORMAL_BLACKBOX_ALU 
alu_out_0 = $anyseq; 
$fwrite(f,"%0t cycle :picorv32.v:1810\n"  , $time); 
alu_out = $anyseq; 
$fwrite(f,"%0t cycle :picorv32.v:1812\n"  , $time); 
`endif 
end 
 
reg clear_prefetched_high_word_q; 
always @(posedge clk) begin 
clear_prefetched_high_word_q <= clear_prefetched_high_word; 
$fwrite(f,"%0t cycle :picorv32.v:1819\n"  , $time); 
end 
 
always @* begin 
clear_prefetched_high_word = clear_prefetched_high_word_q; 
$fwrite(f,"%0t cycle :picorv32.v:1824\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:1827\n"  , $time); 
if (!prefetched_high_word) begin 
clear_prefetched_high_word = 0; 
$fwrite(f,"%0t cycle :picorv32.v:1828\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:1832\n"  , $time); 
if (latched_branch || irq_state || !resetn) begin 
clear_prefetched_high_word = COMPRESSED_ISA; 
$fwrite(f,"%0t cycle :picorv32.v:1833\n"  , $time); 
end 
end 
 
reg cpuregs_write; 
reg [31:0] cpuregs_wrdata; 
reg [31:0] cpuregs_rs1; 
reg [31:0] cpuregs_rs2; 
reg [regindex_bits-1:0] decoded_rs; 
 
always @* begin 
cpuregs_write = 0; 
$fwrite(f,"%0t cycle :picorv32.v:1845\n"  , $time); 
cpuregs_wrdata = 'bx; 
$fwrite(f,"%0t cycle :picorv32.v:1847\n"  , $time); 
 
$fwrite(f,"%0t cycle :picorv32.v:1850\n"  , $time); 
if (cpu_state == cpu_state_fetch) begin 

(* parallel_case *) 

case (1'b1) 
latched_branch: begin 
cpuregs_wrdata = reg_pc + (latched_compr ? 2 : 4); 
$fwrite(f,"%0t cycle :picorv32.v:1857\n"  , $time); 
cpuregs_write = 1; 
$fwrite(f,"%0t cycle :picorv32.v:1859\n"  , $time); 
end 
latched_store && !latched_branch: begin 
cpuregs_wrdata = latched_stalu ? alu_out_q : reg_out; 
$fwrite(f,"%0t cycle :picorv32.v:1863\n"  , $time); 
cpuregs_write = 1; 
$fwrite(f,"%0t cycle :picorv32.v:1865\n"  , $time); 
end 
ENABLE_IRQ && irq_state[0]: begin 
cpuregs_wrdata = reg_next_pc | latched_compr; 
$fwrite(f,"%0t cycle :picorv32.v:1869\n"  , $time); 
cpuregs_write = 1; 
$fwrite(f,"%0t cycle :picorv32.v:1871\n"  , $time); 
end 
ENABLE_IRQ && irq_state[1]: begin 
cpuregs_wrdata = irq_pending & ~irq_mask; 
$fwrite(f,"%0t cycle :picorv32.v:1875\n"  , $time); 
cpuregs_write = 1; 
$fwrite(f,"%0t cycle :picorv32.v:1877\n"  , $time); 
end 
endcase 
end 
end 
 
`ifndef PICORV32_REGS 
always @(posedge clk) begin 
$fwrite(f,"%0t cycle :picorv32.v:1887\n"  , $time); 
if (resetn && cpuregs_write && latched_rd) begin 
cpuregs[latched_rd] <= cpuregs_wrdata; 
$fwrite(f,"%0t cycle :picorv32.v:1888\n"  , $time); 
end 
end 
 
always @* begin 
decoded_rs = 'bx; 
$fwrite(f,"%0t cycle :picorv32.v:1894\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:1897\n"  , $time); 
if (ENABLE_REGS_DUALPORT) begin 
`ifndef RISCV_FORMAL_BLACKBOX_REGS 
cpuregs_rs1 = decoded_rs1 ? cpuregs[decoded_rs1] : 0; 
$fwrite(f,"%0t cycle :picorv32.v:1899\n"  , $time); 
cpuregs_rs2 = decoded_rs2 ? cpuregs[decoded_rs2] : 0; 
$fwrite(f,"%0t cycle :picorv32.v:1901\n"  , $time); 
`else 
cpuregs_rs1 = decoded_rs1 ? $anyseq : 0; 
$fwrite(f,"%0t cycle :picorv32.v:1904\n"  , $time); 
cpuregs_rs2 = decoded_rs2 ? $anyseq : 0; 
$fwrite(f,"%0t cycle :picorv32.v:1906\n"  , $time); 
`endif 
end else begin 
decoded_rs = (cpu_state == cpu_state_ld_rs2) ? decoded_rs2 : decoded_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:1910\n"  , $time); 
`ifndef RISCV_FORMAL_BLACKBOX_REGS 
cpuregs_rs1 = decoded_rs ? cpuregs[decoded_rs] : 0; 
$fwrite(f,"%0t cycle :picorv32.v:1913\n"  , $time); 
`else 
cpuregs_rs1 = decoded_rs ? $anyseq : 0; 
$fwrite(f,"%0t cycle :picorv32.v:1916\n"  , $time); 
`endif 
cpuregs_rs2 = cpuregs_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:1919\n"  , $time); 
end 
end 
`else 
wire[31:0] cpuregs_rdata1; 
wire[31:0] cpuregs_rdata2; 
 
wire [5:0] cpuregs_waddr = latched_rd; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32.v:1927\n"  , $time); 
end 
wire [5:0] cpuregs_raddr1 = ENABLE_REGS_DUALPORT ? decoded_rs1 : decoded_rs; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32.v:1931\n"  , $time); 
end 
wire [5:0] cpuregs_raddr2 = ENABLE_REGS_DUALPORT ? decoded_rs2 : 0; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32.v:1935\n"  , $time); 
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
$fwrite(f,"%0t cycle :picorv32.v:1952\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:1955\n"  , $time); 
if (ENABLE_REGS_DUALPORT) begin 
cpuregs_rs1 = decoded_rs1 ? cpuregs_rdata1 : 0; 
$fwrite(f,"%0t cycle :picorv32.v:1956\n"  , $time); 
cpuregs_rs2 = decoded_rs2 ? cpuregs_rdata2 : 0; 
$fwrite(f,"%0t cycle :picorv32.v:1958\n"  , $time); 
end else begin 
decoded_rs = (cpu_state == cpu_state_ld_rs2) ? decoded_rs2 : decoded_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:1961\n"  , $time); 
cpuregs_rs1 = decoded_rs ? cpuregs_rdata1 : 0; 
$fwrite(f,"%0t cycle :picorv32.v:1963\n"  , $time); 
cpuregs_rs2 = cpuregs_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:1965\n"  , $time); 
end 
end 
`endif 
 
assign launch_next_insn = cpu_state == cpu_state_fetch && decoder_trigger && (!ENABLE_IRQ || irq_delay || irq_active || !(irq_pending & ~irq_mask)); 
always@* begin 
$fwrite(f,"%0t cycle :picorv32.v:1971\n"  , $time); 
end 
 
always @(posedge clk) begin 
trap <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1977\n"  , $time); 
reg_sh <= 'bx; 
$fwrite(f,"%0t cycle :picorv32.v:1979\n"  , $time); 
reg_out <= 'bx; 
$fwrite(f,"%0t cycle :picorv32.v:1981\n"  , $time); 
set_mem_do_rinst = 0; 
$fwrite(f,"%0t cycle :picorv32.v:1983\n"  , $time); 
set_mem_do_rdata = 0; 
$fwrite(f,"%0t cycle :picorv32.v:1985\n"  , $time); 
set_mem_do_wdata = 0; 
$fwrite(f,"%0t cycle :picorv32.v:1987\n"  , $time); 
 
alu_out_0_q <= alu_out_0; 
$fwrite(f,"%0t cycle :picorv32.v:1990\n"  , $time); 
alu_out_q <= alu_out; 
$fwrite(f,"%0t cycle :picorv32.v:1992\n"  , $time); 
 
alu_wait <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1995\n"  , $time); 
alu_wait_2 <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:1997\n"  , $time); 
 
$fwrite(f,"%0t cycle :picorv32.v:2001\n"  , $time); 
if (launch_next_insn) begin 
dbg_rs1val <= 'bx; 
$fwrite(f,"%0t cycle :picorv32.v:2002\n"  , $time); 
dbg_rs2val <= 'bx; 
$fwrite(f,"%0t cycle :picorv32.v:2004\n"  , $time); 
dbg_rs1val_valid <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2006\n"  , $time); 
dbg_rs2val_valid <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2008\n"  , $time); 
end 
 
$fwrite(f,"%0t cycle :picorv32.v:2013\n"  , $time); 
if (WITH_PCPI && CATCH_ILLINSN) begin 
$fwrite(f,"%0t cycle :picorv32.v:2015\n"  , $time); 
if (resetn && pcpi_valid && !pcpi_int_wait) begin 
$fwrite(f,"%0t cycle :picorv32.v:2017\n"  , $time); 
if (pcpi_timeout_counter) begin 
pcpi_timeout_counter <= pcpi_timeout_counter - 1; 
$fwrite(f,"%0t cycle :picorv32.v:2018\n"  , $time); 
end 
end else 
pcpi_timeout_counter <= ~0; 
$fwrite(f,"%0t cycle :picorv32.v:2022\n"  , $time); 
pcpi_timeout <= !pcpi_timeout_counter; 
$fwrite(f,"%0t cycle :picorv32.v:2024\n"  , $time); 
end 
 
$fwrite(f,"%0t cycle :picorv32.v:2029\n"  , $time); 
if (ENABLE_COUNTERS) begin 
count_cycle <= resetn ? count_cycle + 1 : 0; 
$fwrite(f,"%0t cycle :picorv32.v:2030\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:2033\n"  , $time); 
if (!ENABLE_COUNTERS64) begin 
count_cycle[63:32] <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2034\n"  , $time); 
end 
end else begin 
count_cycle <= 'bx; 
$fwrite(f,"%0t cycle :picorv32.v:2038\n"  , $time); 
count_instr <= 'bx; 
$fwrite(f,"%0t cycle :picorv32.v:2040\n"  , $time); 
end 
 
next_irq_pending = ENABLE_IRQ ? irq_pending & LATCHED_IRQ : 'bx; 
$fwrite(f,"%0t cycle :picorv32.v:2044\n"  , $time); 
 
$fwrite(f,"%0t cycle :picorv32.v:2048\n"  , $time); 
if (ENABLE_IRQ && ENABLE_IRQ_TIMER && timer) begin 
$fwrite(f,"%0t cycle :picorv32.v:2049\n"  , $time); 
if (timer - 1 == 0) begin 
next_irq_pending[irq_timer] = 1; 
$fwrite(f,"%0t cycle :picorv32.v:2051\n"  , $time); 
end 
timer <= timer - 1; 
$fwrite(f,"%0t cycle :picorv32.v:2054\n"  , $time); 
end 
 
$fwrite(f,"%0t cycle :picorv32.v:2059\n"  , $time); 
if (ENABLE_IRQ) begin 
next_irq_pending = next_irq_pending | irq; 
$fwrite(f,"%0t cycle :picorv32.v:2060\n"  , $time); 
end 
 
decoder_trigger <= mem_do_rinst && mem_done; 
$fwrite(f,"%0t cycle :picorv32.v:2064\n"  , $time); 
decoder_trigger_q <= decoder_trigger; 
$fwrite(f,"%0t cycle :picorv32.v:2066\n"  , $time); 
decoder_pseudo_trigger <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2068\n"  , $time); 
decoder_pseudo_trigger_q <= decoder_pseudo_trigger; 
$fwrite(f,"%0t cycle :picorv32.v:2070\n"  , $time); 
do_waitirq <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2072\n"  , $time); 
 
trace_valid <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2075\n"  , $time); 
 
$fwrite(f,"%0t cycle :picorv32.v:2079\n"  , $time); 
if (!ENABLE_TRACE) begin 
trace_data <= 'bx; 
$fwrite(f,"%0t cycle :picorv32.v:2080\n"  , $time); 
end 
 
$fwrite(f,"%0t cycle :picorv32.v:2085\n"  , $time); 
if (!resetn) begin 
reg_pc <= PROGADDR_RESET; 
$fwrite(f,"%0t cycle :picorv32.v:2086\n"  , $time); 
reg_next_pc <= PROGADDR_RESET; 
$fwrite(f,"%0t cycle :picorv32.v:2088\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:2091\n"  , $time); 
if (ENABLE_COUNTERS) begin 
count_instr <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2092\n"  , $time); 
end 
latched_store <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2095\n"  , $time); 
latched_stalu <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2097\n"  , $time); 
latched_branch <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2099\n"  , $time); 
latched_trace <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2101\n"  , $time); 
latched_is_lu <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2103\n"  , $time); 
latched_is_lh <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2105\n"  , $time); 
latched_is_lb <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2107\n"  , $time); 
pcpi_valid <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2109\n"  , $time); 
pcpi_timeout <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2111\n"  , $time); 
irq_active <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2113\n"  , $time); 
irq_delay <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2115\n"  , $time); 
irq_mask <= ~0; 
$fwrite(f,"%0t cycle :picorv32.v:2117\n"  , $time); 
next_irq_pending = 0; 
$fwrite(f,"%0t cycle :picorv32.v:2119\n"  , $time); 
irq_state <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2121\n"  , $time); 
eoi <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2123\n"  , $time); 
timer <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2125\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:2128\n"  , $time); 
if (~STACKADDR) begin 
latched_store <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2129\n"  , $time); 
latched_rd <= 2; 
$fwrite(f,"%0t cycle :picorv32.v:2131\n"  , $time); 
reg_out <= STACKADDR; 
$fwrite(f,"%0t cycle :picorv32.v:2133\n"  , $time); 
end 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0t cycle :picorv32.v:2136\n"  , $time); 
end else 

(* parallel_case, full_case *) 

case (cpu_state) 
cpu_state_trap: begin 
trap <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2144\n"  , $time); 
end 
 
cpu_state_fetch: begin 
mem_do_rinst <= !decoder_trigger && !do_waitirq; 
$fwrite(f,"%0t cycle :picorv32.v:2149\n"  , $time); 
mem_wordsize <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2151\n"  , $time); 
 
current_pc = reg_next_pc; 
$fwrite(f,"%0t cycle :picorv32.v:2154\n"  , $time); 
 

(* parallel_case *) 

case (1'b1) 
latched_branch: begin 
current_pc = latched_store ? (latched_stalu ? alu_out_q : reg_out) & ~1 : reg_next_pc; 
$fwrite(f,"%0t cycle :picorv32.v:2162\n"  , $time); 
 
end 
latched_store && !latched_branch: begin 
 
end 
ENABLE_IRQ && irq_state[0]: begin 
current_pc = PROGADDR_IRQ; 
$fwrite(f,"%0t cycle :picorv32.v:2170\n"  , $time); 
irq_active <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2172\n"  , $time); 
mem_do_rinst <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2174\n"  , $time); 
end 
ENABLE_IRQ && irq_state[1]: begin 
eoi <= irq_pending & ~irq_mask; 
$fwrite(f,"%0t cycle :picorv32.v:2178\n"  , $time); 
next_irq_pending = next_irq_pending & irq_mask; 
$fwrite(f,"%0t cycle :picorv32.v:2180\n"  , $time); 
end 
endcase 
 
$fwrite(f,"%0t cycle :picorv32.v:2186\n"  , $time); 
if (ENABLE_TRACE && latched_trace) begin 
latched_trace <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2187\n"  , $time); 
trace_valid <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2189\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:2192\n"  , $time); 
if (latched_branch) begin 
trace_data <= (irq_active ? TRACE_IRQ : 0) | TRACE_BRANCH | (current_pc & 32'hfffffffe); 
$fwrite(f,"%0t cycle :picorv32.v:2193\n"  , $time); 
end 
else 
trace_data <= (irq_active ? TRACE_IRQ : 0) | (latched_stalu ? alu_out_q : reg_out); 
$fwrite(f,"%0t cycle :picorv32.v:2197\n"  , $time); 
end 
 
reg_pc <= current_pc; 
$fwrite(f,"%0t cycle :picorv32.v:2201\n"  , $time); 
reg_next_pc <= current_pc; 
$fwrite(f,"%0t cycle :picorv32.v:2203\n"  , $time); 
 
latched_store <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2206\n"  , $time); 
latched_stalu <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2208\n"  , $time); 
latched_branch <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2210\n"  , $time); 
latched_is_lu <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2212\n"  , $time); 
latched_is_lh <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2214\n"  , $time); 
latched_is_lb <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2216\n"  , $time); 
latched_rd <= decoded_rd; 
$fwrite(f,"%0t cycle :picorv32.v:2218\n"  , $time); 
latched_compr <= compressed_instr; 
$fwrite(f,"%0t cycle :picorv32.v:2220\n"  , $time); 
 
$fwrite(f,"%0t cycle :picorv32.v:2224\n"  , $time); 
if (ENABLE_IRQ && ((decoder_trigger && !irq_active && !irq_delay && |(irq_pending & ~irq_mask)) || irq_state)) begin 
irq_state <=irq_state == 2'b00 ? 2'b01 :irq_state == 2'b01 ? 2'b10 : 2'b00; 
$fwrite(f,"%0t cycle :picorv32.v:2225\n"  , $time); 
latched_compr <= latched_compr; 
$fwrite(f,"%0t cycle :picorv32.v:2227\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:2230\n"  , $time); 
if (ENABLE_IRQ_QREGS) begin 
latched_rd <= irqregs_offset | irq_state[0]; 
$fwrite(f,"%0t cycle :picorv32.v:2231\n"  , $time); 
end 
else 
latched_rd <= irq_state[0] ? 4 : 3; 
$fwrite(f,"%0t cycle :picorv32.v:2235\n"  , $time); 
end else 
$fwrite(f,"%0t cycle :picorv32.v:2239\n"  , $time); 
if (ENABLE_IRQ && (decoder_trigger || do_waitirq) && instr_waitirq) begin 
$fwrite(f,"%0t cycle :picorv32.v:2241\n"  , $time); 
if (irq_pending) begin 
latched_store <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2242\n"  , $time); 
reg_out <= irq_pending; 
$fwrite(f,"%0t cycle :picorv32.v:2244\n"  , $time); 
reg_next_pc <= current_pc + (compressed_instr ? 2 : 4); 
$fwrite(f,"%0t cycle :picorv32.v:2246\n"  , $time); 
mem_do_rinst <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2248\n"  , $time); 
end else 
do_waitirq <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2251\n"  , $time); 
end else 
$fwrite(f,"%0t cycle :picorv32.v:2255\n"  , $time); 
if (decoder_trigger) begin 
 
irq_delay <= irq_active; 
$fwrite(f,"%0t cycle :picorv32.v:2257\n"  , $time); 
reg_next_pc <= current_pc + (compressed_instr ? 2 : 4); 
$fwrite(f,"%0t cycle :picorv32.v:2259\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:2262\n"  , $time); 
if (ENABLE_TRACE) begin 
latched_trace <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2263\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:2267\n"  , $time); 
if (ENABLE_COUNTERS) begin 
count_instr <= count_instr + 1; 
$fwrite(f,"%0t cycle :picorv32.v:2268\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:2271\n"  , $time); 
if (!ENABLE_COUNTERS64) begin 
count_instr[63:32] <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2272\n"  , $time); 
end 
end 
$fwrite(f,"%0t cycle :picorv32.v:2277\n"  , $time); 
if (instr_jal) begin 
mem_do_rinst <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2278\n"  , $time); 
reg_next_pc <= current_pc + decoded_imm_j; 
$fwrite(f,"%0t cycle :picorv32.v:2280\n"  , $time); 
latched_branch <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2282\n"  , $time); 
end else begin 
mem_do_rinst <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2285\n"  , $time); 
mem_do_prefetch <= !instr_jalr && !instr_retirq; 
$fwrite(f,"%0t cycle :picorv32.v:2287\n"  , $time); 
cpu_state <= cpu_state_ld_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:2289\n"  , $time); 
end 
end 
end 
 
cpu_state_ld_rs1: begin 
reg_op1 <= 'bx; 
$fwrite(f,"%0t cycle :picorv32.v:2296\n"  , $time); 
reg_op2 <= 'bx; 
$fwrite(f,"%0t cycle :picorv32.v:2298\n"  , $time); 
 

(* parallel_case *) 

case (1'b1) 
(CATCH_ILLINSN || WITH_PCPI) && instr_trap: begin 
$fwrite(f,"%0t cycle :picorv32.v:2307\n"  , $time); 
if (WITH_PCPI) begin 
 
reg_op1 <= cpuregs_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:2309\n"  , $time); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:2311\n"  , $time); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2313\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:2316\n"  , $time); 
if (ENABLE_REGS_DUALPORT) begin 
pcpi_valid <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2317\n"  , $time); 
 
reg_sh <= cpuregs_rs2; 
$fwrite(f,"%0t cycle :picorv32.v:2320\n"  , $time); 
reg_op2 <= cpuregs_rs2; 
$fwrite(f,"%0t cycle :picorv32.v:2322\n"  , $time); 
dbg_rs2val <= cpuregs_rs2; 
$fwrite(f,"%0t cycle :picorv32.v:2324\n"  , $time); 
dbg_rs2val_valid <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2326\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:2329\n"  , $time); 
if (pcpi_int_ready) begin 
mem_do_rinst <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2330\n"  , $time); 
pcpi_valid <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2332\n"  , $time); 
reg_out <= pcpi_int_rd; 
$fwrite(f,"%0t cycle :picorv32.v:2334\n"  , $time); 
latched_store <= pcpi_int_wr; 
$fwrite(f,"%0t cycle :picorv32.v:2336\n"  , $time); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0t cycle :picorv32.v:2338\n"  , $time); 
end else 
$fwrite(f,"%0t cycle :picorv32.v:2342\n"  , $time); 
if (CATCH_ILLINSN && (pcpi_timeout || instr_ecall_ebreak)) begin 
pcpi_valid <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2343\n"  , $time); 
 
$fwrite(f,"%0t cycle :picorv32.v:2347\n"  , $time); 
if (ENABLE_IRQ && !irq_mask[irq_ebreak] && !irq_active) begin 
next_irq_pending[irq_ebreak] = 1; 
$fwrite(f,"%0t cycle :picorv32.v:2348\n"  , $time); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0t cycle :picorv32.v:2350\n"  , $time); 
end else 
cpu_state <= cpu_state_trap; 
$fwrite(f,"%0t cycle :picorv32.v:2353\n"  , $time); 
end 
end else begin 
cpu_state <= cpu_state_ld_rs2; 
$fwrite(f,"%0t cycle :picorv32.v:2357\n"  , $time); 
end 
end else begin 
 
$fwrite(f,"%0t cycle :picorv32.v:2363\n"  , $time); 
if (ENABLE_IRQ && !irq_mask[irq_ebreak] && !irq_active) begin 
next_irq_pending[irq_ebreak] = 1; 
$fwrite(f,"%0t cycle :picorv32.v:2364\n"  , $time); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0t cycle :picorv32.v:2366\n"  , $time); 
end else 
cpu_state <= cpu_state_trap; 
$fwrite(f,"%0t cycle :picorv32.v:2369\n"  , $time); 
end 
end 
ENABLE_COUNTERS && is_rdcycle_rdcycleh_rdinstr_rdinstrh: begin 

(* parallel_case, full_case *) 

case (1'b1) 
instr_rdcycle: begin 
reg_out <= count_cycle[31:0]; 
$fwrite(f,"%0t cycle :picorv32.v:2379\n"  , $time); 
end 
instr_rdcycleh && ENABLE_COUNTERS64: begin 
reg_out <= count_cycle[63:32]; 
$fwrite(f,"%0t cycle :picorv32.v:2383\n"  , $time); 
end 
instr_rdinstr: begin 
reg_out <= count_instr[31:0]; 
$fwrite(f,"%0t cycle :picorv32.v:2387\n"  , $time); 
end 
instr_rdinstrh && ENABLE_COUNTERS64: begin 
reg_out <= count_instr[63:32]; 
$fwrite(f,"%0t cycle :picorv32.v:2391\n"  , $time); 
end 
endcase 
latched_store <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2395\n"  , $time); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0t cycle :picorv32.v:2397\n"  , $time); 
end 
is_lui_auipc_jal: begin 
reg_op1 <= instr_lui ? 0 : reg_pc; 
$fwrite(f,"%0t cycle :picorv32.v:2401\n"  , $time); 
reg_op2 <= decoded_imm; 
$fwrite(f,"%0t cycle :picorv32.v:2403\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:2406\n"  , $time); 
if (TWO_CYCLE_ALU) begin 
alu_wait <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2407\n"  , $time); 
end 
else 
mem_do_rinst <= mem_do_prefetch; 
$fwrite(f,"%0t cycle :picorv32.v:2411\n"  , $time); 
cpu_state <= cpu_state_exec; 
$fwrite(f,"%0t cycle :picorv32.v:2413\n"  , $time); 
end 
ENABLE_IRQ && ENABLE_IRQ_QREGS && instr_getq: begin 
 
reg_out <= cpuregs_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:2418\n"  , $time); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:2420\n"  , $time); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2422\n"  , $time); 
latched_store <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2424\n"  , $time); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0t cycle :picorv32.v:2426\n"  , $time); 
end 
ENABLE_IRQ && ENABLE_IRQ_QREGS && instr_setq: begin 
 
reg_out <= cpuregs_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:2431\n"  , $time); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:2433\n"  , $time); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2435\n"  , $time); 
latched_rd <= latched_rd | irqregs_offset; 
$fwrite(f,"%0t cycle :picorv32.v:2437\n"  , $time); 
latched_store <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2439\n"  , $time); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0t cycle :picorv32.v:2441\n"  , $time); 
end 
ENABLE_IRQ && instr_retirq: begin 
eoi <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2445\n"  , $time); 
irq_active <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2447\n"  , $time); 
latched_branch <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2449\n"  , $time); 
latched_store <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2451\n"  , $time); 
 
reg_out <= CATCH_MISALIGN ? (cpuregs_rs1 & 32'h fffffffe) : cpuregs_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:2454\n"  , $time); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:2456\n"  , $time); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2458\n"  , $time); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0t cycle :picorv32.v:2460\n"  , $time); 
end 
ENABLE_IRQ && instr_maskirq: begin 
latched_store <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2464\n"  , $time); 
reg_out <= irq_mask; 
$fwrite(f,"%0t cycle :picorv32.v:2466\n"  , $time); 
 
irq_mask <= cpuregs_rs1 | MASKED_IRQ; 
$fwrite(f,"%0t cycle :picorv32.v:2469\n"  , $time); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:2471\n"  , $time); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2473\n"  , $time); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0t cycle :picorv32.v:2475\n"  , $time); 
end 
ENABLE_IRQ && ENABLE_IRQ_TIMER && instr_timer: begin 
latched_store <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2479\n"  , $time); 
reg_out <= timer; 
$fwrite(f,"%0t cycle :picorv32.v:2481\n"  , $time); 
 
timer <= cpuregs_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:2484\n"  , $time); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:2486\n"  , $time); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2488\n"  , $time); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0t cycle :picorv32.v:2490\n"  , $time); 
end 
is_lb_lh_lw_lbu_lhu && !instr_trap: begin 
 
reg_op1 <= cpuregs_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:2495\n"  , $time); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:2497\n"  , $time); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2499\n"  , $time); 
cpu_state <= cpu_state_ldmem; 
$fwrite(f,"%0t cycle :picorv32.v:2501\n"  , $time); 
mem_do_rinst <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2503\n"  , $time); 
end 
is_slli_srli_srai && !BARREL_SHIFTER: begin 
 
reg_op1 <= cpuregs_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:2508\n"  , $time); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:2510\n"  , $time); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2512\n"  , $time); 
reg_sh <= decoded_rs2; 
$fwrite(f,"%0t cycle :picorv32.v:2514\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:2516\n"  , $time); 
cpu_state <= cpu_state_shift; 
end 
is_jalr_addi_slti_sltiu_xori_ori_andi, is_slli_srli_srai && BARREL_SHIFTER: begin 
 
reg_op1 <= cpuregs_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:2521\n"  , $time); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:2523\n"  , $time); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2525\n"  , $time); 
reg_op2 <= is_slli_srli_srai && BARREL_SHIFTER ? decoded_rs2 : decoded_imm; 
$fwrite(f,"%0t cycle :picorv32.v:2527\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:2530\n"  , $time); 
if (TWO_CYCLE_ALU) begin 
alu_wait <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2531\n"  , $time); 
end 
else 
mem_do_rinst <= mem_do_prefetch; 
$fwrite(f,"%0t cycle :picorv32.v:2535\n"  , $time); 
cpu_state <= cpu_state_exec; 
$fwrite(f,"%0t cycle :picorv32.v:2537\n"  , $time); 
end 
default: begin 
 
reg_op1 <= cpuregs_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:2542\n"  , $time); 
dbg_rs1val <= cpuregs_rs1; 
$fwrite(f,"%0t cycle :picorv32.v:2544\n"  , $time); 
dbg_rs1val_valid <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2546\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:2549\n"  , $time); 
if (ENABLE_REGS_DUALPORT) begin 
 
reg_sh <= cpuregs_rs2; 
$fwrite(f,"%0t cycle :picorv32.v:2551\n"  , $time); 
reg_op2 <= cpuregs_rs2; 
$fwrite(f,"%0t cycle :picorv32.v:2553\n"  , $time); 
dbg_rs2val <= cpuregs_rs2; 
$fwrite(f,"%0t cycle :picorv32.v:2555\n"  , $time); 
dbg_rs2val_valid <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2557\n"  , $time); 

(* parallel_case *) 

case (1'b1) 
is_sb_sh_sw: begin 
cpu_state <= cpu_state_stmem; 
$fwrite(f,"%0t cycle :picorv32.v:2564\n"  , $time); 
mem_do_rinst <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2566\n"  , $time); 
end 
is_sll_srl_sra && !BARREL_SHIFTER: begin 
$fwrite(f,"%0t cycle :picorv32.v:2570\n"  , $time); 
cpu_state <= cpu_state_shift; 
end 
default: begin 
$fwrite(f,"%0t cycle :picorv32.v:2575\n"  , $time); 
if (TWO_CYCLE_ALU || (TWO_CYCLE_COMPARE && is_beq_bne_blt_bge_bltu_bgeu)) begin 
alu_wait_2 <= TWO_CYCLE_ALU && (TWO_CYCLE_COMPARE && is_beq_bne_blt_bge_bltu_bgeu); 
$fwrite(f,"%0t cycle :picorv32.v:2576\n"  , $time); 
alu_wait <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2578\n"  , $time); 
end else 
mem_do_rinst <= mem_do_prefetch; 
$fwrite(f,"%0t cycle :picorv32.v:2581\n"  , $time); 
cpu_state <= cpu_state_exec; 
$fwrite(f,"%0t cycle :picorv32.v:2583\n"  , $time); 
end 
endcase 
end else 
cpu_state <= cpu_state_ld_rs2; 
$fwrite(f,"%0t cycle :picorv32.v:2588\n"  , $time); 
end 
endcase 
end 
 
cpu_state_ld_rs2: begin 
 
reg_sh <= cpuregs_rs2; 
$fwrite(f,"%0t cycle :picorv32.v:2596\n"  , $time); 
reg_op2 <= cpuregs_rs2; 
$fwrite(f,"%0t cycle :picorv32.v:2598\n"  , $time); 
dbg_rs2val <= cpuregs_rs2; 
$fwrite(f,"%0t cycle :picorv32.v:2600\n"  , $time); 
dbg_rs2val_valid <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2602\n"  , $time); 
 

(* parallel_case *) 

case (1'b1) 
WITH_PCPI && instr_trap: begin 
pcpi_valid <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2610\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:2613\n"  , $time); 
if (pcpi_int_ready) begin 
mem_do_rinst <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2614\n"  , $time); 
pcpi_valid <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2616\n"  , $time); 
reg_out <= pcpi_int_rd; 
$fwrite(f,"%0t cycle :picorv32.v:2618\n"  , $time); 
latched_store <= pcpi_int_wr; 
$fwrite(f,"%0t cycle :picorv32.v:2620\n"  , $time); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0t cycle :picorv32.v:2622\n"  , $time); 
end else 
$fwrite(f,"%0t cycle :picorv32.v:2626\n"  , $time); 
if (CATCH_ILLINSN && (pcpi_timeout || instr_ecall_ebreak)) begin 
pcpi_valid <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2627\n"  , $time); 
 
$fwrite(f,"%0t cycle :picorv32.v:2631\n"  , $time); 
if (ENABLE_IRQ && !irq_mask[irq_ebreak] && !irq_active) begin 
next_irq_pending[irq_ebreak] = 1; 
$fwrite(f,"%0t cycle :picorv32.v:2632\n"  , $time); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0t cycle :picorv32.v:2634\n"  , $time); 
end else 
cpu_state <= cpu_state_trap; 
$fwrite(f,"%0t cycle :picorv32.v:2637\n"  , $time); 
end 
end 
is_sb_sh_sw: begin 
cpu_state <= cpu_state_stmem; 
$fwrite(f,"%0t cycle :picorv32.v:2642\n"  , $time); 
mem_do_rinst <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2644\n"  , $time); 
end 
is_sll_srl_sra && !BARREL_SHIFTER: begin 
$fwrite(f,"%0t cycle :picorv32.v:2648\n"  , $time); 
cpu_state <= cpu_state_shift; 
end 
default: begin 
$fwrite(f,"%0t cycle :picorv32.v:2653\n"  , $time); 
if (TWO_CYCLE_ALU || (TWO_CYCLE_COMPARE && is_beq_bne_blt_bge_bltu_bgeu)) begin 
alu_wait_2 <= TWO_CYCLE_ALU && (TWO_CYCLE_COMPARE && is_beq_bne_blt_bge_bltu_bgeu); 
$fwrite(f,"%0t cycle :picorv32.v:2654\n"  , $time); 
alu_wait <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2656\n"  , $time); 
end else 
mem_do_rinst <= mem_do_prefetch; 
$fwrite(f,"%0t cycle :picorv32.v:2659\n"  , $time); 
cpu_state <= cpu_state_exec; 
$fwrite(f,"%0t cycle :picorv32.v:2661\n"  , $time); 
end 
endcase 
end 
 
cpu_state_exec: begin 
reg_out <= reg_pc + decoded_imm; 
$fwrite(f,"%0t cycle :picorv32.v:2668\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:2671\n"  , $time); 
if ((TWO_CYCLE_ALU || TWO_CYCLE_COMPARE) && (alu_wait || alu_wait_2)) begin 
mem_do_rinst <= mem_do_prefetch && !alu_wait_2; 
$fwrite(f,"%0t cycle :picorv32.v:2672\n"  , $time); 
alu_wait <= alu_wait_2; 
$fwrite(f,"%0t cycle :picorv32.v:2674\n"  , $time); 
end else 
$fwrite(f,"%0t cycle :picorv32.v:2678\n"  , $time); 
if (is_beq_bne_blt_bge_bltu_bgeu) begin 
latched_rd <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2679\n"  , $time); 
latched_store <= TWO_CYCLE_COMPARE ? alu_out_0_q : alu_out_0; 
$fwrite(f,"%0t cycle :picorv32.v:2681\n"  , $time); 
latched_branch <= TWO_CYCLE_COMPARE ? alu_out_0_q : alu_out_0; 
$fwrite(f,"%0t cycle :picorv32.v:2683\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:2686\n"  , $time); 
if (mem_done) begin 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0t cycle :picorv32.v:2687\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:2691\n"  , $time); 
if (TWO_CYCLE_COMPARE ? alu_out_0_q : alu_out_0) begin 
decoder_trigger <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2692\n"  , $time); 
set_mem_do_rinst = 1; 
$fwrite(f,"%0t cycle :picorv32.v:2694\n"  , $time); 
end 
end else begin 
latched_branch <= instr_jalr; 
$fwrite(f,"%0t cycle :picorv32.v:2698\n"  , $time); 
latched_store <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2700\n"  , $time); 
latched_stalu <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2702\n"  , $time); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0t cycle :picorv32.v:2704\n"  , $time); 
end 
end 
 
cpu_state_shift: begin 
latched_store <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2710\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:2712\n"  , $time); 
if (reg_sh == 0) begin 
reg_out <= reg_op1; 
$fwrite(f,"%0t cycle :picorv32.v:2714\n"  , $time); 
mem_do_rinst <= mem_do_prefetch; 
$fwrite(f,"%0t cycle :picorv32.v:2716\n"  , $time); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0t cycle :picorv32.v:2718\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:2720\n"  , $time); 
end else if (TWO_STAGE_SHIFT && reg_sh >= 4) begin 

(* parallel_case, full_case *) 

case (1'b1) 
instr_slli || instr_sll: begin 
reg_op1 <= reg_op1 << 4; 
$fwrite(f,"%0t cycle :picorv32.v:2727\n"  , $time); 
end 
instr_srli || instr_srl: begin 
reg_op1 <= reg_op1 >> 4; 
$fwrite(f,"%0t cycle :picorv32.v:2731\n"  , $time); 
end 
instr_srai || instr_sra: begin 
reg_op1 <= $signed(reg_op1) >>> 4; 
$fwrite(f,"%0t cycle :picorv32.v:2735\n"  , $time); 
end 
endcase 
reg_sh <= reg_sh - 4; 
$fwrite(f,"%0t cycle :picorv32.v:2739\n"  , $time); 
end else begin 

(* parallel_case, full_case *) 

case (1'b1) 
instr_slli || instr_sll: begin 
reg_op1 <= reg_op1 << 1; 
$fwrite(f,"%0t cycle :picorv32.v:2747\n"  , $time); 
end 
instr_srli || instr_srl: begin 
reg_op1 <= reg_op1 >> 1; 
$fwrite(f,"%0t cycle :picorv32.v:2751\n"  , $time); 
end 
instr_srai || instr_sra: begin 
reg_op1 <= $signed(reg_op1) >>> 1; 
$fwrite(f,"%0t cycle :picorv32.v:2755\n"  , $time); 
end 
endcase 
reg_sh <= reg_sh - 1; 
$fwrite(f,"%0t cycle :picorv32.v:2759\n"  , $time); 
end 
end 
 
cpu_state_stmem: begin 
$fwrite(f,"%0t cycle :picorv32.v:2766\n"  , $time); 
if (ENABLE_TRACE) begin 
reg_out <= reg_op2; 
$fwrite(f,"%0t cycle :picorv32.v:2767\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:2771\n"  , $time); 
if (!mem_do_prefetch || mem_done) begin 
$fwrite(f,"%0t cycle :picorv32.v:2773\n"  , $time); 
if (!mem_do_wdata) begin 

(* parallel_case, full_case *) 

case (1'b1) 
instr_sb: begin 
mem_wordsize <= 2; 
$fwrite(f,"%0t cycle :picorv32.v:2779\n"  , $time); 
end 
instr_sh: begin 
mem_wordsize <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2783\n"  , $time); 
end 
instr_sw: begin 
mem_wordsize <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2787\n"  , $time); 
end 
endcase 
$fwrite(f,"%0t cycle :picorv32.v:2792\n"  , $time); 
if (ENABLE_TRACE) begin 
trace_valid <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2793\n"  , $time); 
trace_data <= (irq_active ? TRACE_IRQ : 0) | TRACE_ADDR | ((reg_op1 + decoded_imm) & 32'hffffffff); 
$fwrite(f,"%0t cycle :picorv32.v:2795\n"  , $time); 
end 
reg_op1 <= reg_op1 + decoded_imm; 
$fwrite(f,"%0t cycle :picorv32.v:2798\n"  , $time); 
set_mem_do_wdata = 1; 
$fwrite(f,"%0t cycle :picorv32.v:2800\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:2804\n"  , $time); 
if (!mem_do_prefetch && mem_done) begin 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0t cycle :picorv32.v:2805\n"  , $time); 
decoder_trigger <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2807\n"  , $time); 
decoder_pseudo_trigger <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2809\n"  , $time); 
end 
end 
end 
 
cpu_state_ldmem: begin 
latched_store <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2816\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:2819\n"  , $time); 
if (!mem_do_prefetch || mem_done) begin 
$fwrite(f,"%0t cycle :picorv32.v:2821\n"  , $time); 
if (!mem_do_rdata) begin 

(* parallel_case, full_case *) 

case (1'b1) 
instr_lb || instr_lbu: begin 
mem_wordsize <= 2; 
$fwrite(f,"%0t cycle :picorv32.v:2827\n"  , $time); 
end 
instr_lh || instr_lhu: begin 
mem_wordsize <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2831\n"  , $time); 
end 
instr_lw: begin 
mem_wordsize <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2835\n"  , $time); 
end 
endcase 
latched_is_lu <= is_lbu_lhu_lw; 
$fwrite(f,"%0t cycle :picorv32.v:2839\n"  , $time); 
latched_is_lh <= instr_lh; 
$fwrite(f,"%0t cycle :picorv32.v:2841\n"  , $time); 
latched_is_lb <= instr_lb; 
$fwrite(f,"%0t cycle :picorv32.v:2843\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:2846\n"  , $time); 
if (ENABLE_TRACE) begin 
trace_valid <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2847\n"  , $time); 
trace_data <= (irq_active ? TRACE_IRQ : 0) | TRACE_ADDR | ((reg_op1 + decoded_imm) & 32'hffffffff); 
$fwrite(f,"%0t cycle :picorv32.v:2849\n"  , $time); 
end 
reg_op1 <= reg_op1 + decoded_imm; 
$fwrite(f,"%0t cycle :picorv32.v:2852\n"  , $time); 
set_mem_do_rdata = 1; 
$fwrite(f,"%0t cycle :picorv32.v:2854\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:2858\n"  , $time); 
if (!mem_do_prefetch && mem_done) begin 

(* parallel_case, full_case *) 

case (1'b1) 
latched_is_lu: begin 
reg_out <= mem_rdata_word; 
$fwrite(f,"%0t cycle :picorv32.v:2864\n"  , $time); 
end 
latched_is_lh: begin 
reg_out <= $signed(mem_rdata_word[15:0]); 
$fwrite(f,"%0t cycle :picorv32.v:2868\n"  , $time); 
end 
latched_is_lb: begin 
reg_out <= $signed(mem_rdata_word[7:0]); 
$fwrite(f,"%0t cycle :picorv32.v:2872\n"  , $time); 
end 
endcase 
decoder_trigger <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2876\n"  , $time); 
decoder_pseudo_trigger <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2878\n"  , $time); 
cpu_state <= cpu_state_fetch; 
$fwrite(f,"%0t cycle :picorv32.v:2880\n"  , $time); 
end 
end 
end 
endcase 
 
$fwrite(f,"%0t cycle :picorv32.v:2888\n"  , $time); 
if (CATCH_MISALIGN && resetn && (mem_do_rdata || mem_do_wdata)) begin 
$fwrite(f,"%0t cycle :picorv32.v:2889\n"  , $time); 
if (mem_wordsize == 0 && reg_op1[1:0] != 0) begin 
 
$fwrite(f,"%0t cycle :picorv32.v:2893\n"  , $time); 
if (ENABLE_IRQ && !irq_mask[irq_buserror] && !irq_active) begin 
next_irq_pending[irq_buserror] = 1; 
$fwrite(f,"%0t cycle :picorv32.v:2894\n"  , $time); 
end else 
cpu_state <= cpu_state_trap; 
$fwrite(f,"%0t cycle :picorv32.v:2897\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:2900\n"  , $time); 
if (mem_wordsize == 1 && reg_op1[0] != 0) begin 
 
$fwrite(f,"%0t cycle :picorv32.v:2904\n"  , $time); 
if (ENABLE_IRQ && !irq_mask[irq_buserror] && !irq_active) begin 
next_irq_pending[irq_buserror] = 1; 
$fwrite(f,"%0t cycle :picorv32.v:2905\n"  , $time); 
end else 
cpu_state <= cpu_state_trap; 
$fwrite(f,"%0t cycle :picorv32.v:2908\n"  , $time); 
end 
end 
$fwrite(f,"%0t cycle :picorv32.v:2913\n"  , $time); 
if (CATCH_MISALIGN && resetn && mem_do_rinst && (COMPRESSED_ISA ? reg_pc[0] : |reg_pc[1:0])) begin 
 
$fwrite(f,"%0t cycle :picorv32.v:2916\n"  , $time); 
if (ENABLE_IRQ && !irq_mask[irq_buserror] && !irq_active) begin 
next_irq_pending[irq_buserror] = 1; 
$fwrite(f,"%0t cycle :picorv32.v:2917\n"  , $time); 
end else 
cpu_state <= cpu_state_trap; 
$fwrite(f,"%0t cycle :picorv32.v:2920\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:2924\n"  , $time); 
if (!CATCH_ILLINSN && decoder_trigger_q && !decoder_pseudo_trigger_q && instr_ecall_ebreak) begin 
cpu_state <= cpu_state_trap; 
$fwrite(f,"%0t cycle :picorv32.v:2925\n"  , $time); 
end 
 
$fwrite(f,"%0t cycle :picorv32.v:2930\n"  , $time); 
if (!resetn || mem_done) begin 
mem_do_prefetch <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2931\n"  , $time); 
mem_do_rinst <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2933\n"  , $time); 
mem_do_rdata <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2935\n"  , $time); 
mem_do_wdata <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2937\n"  , $time); 
end 
 
$fwrite(f,"%0t cycle :picorv32.v:2942\n"  , $time); 
if (set_mem_do_rinst) begin 
mem_do_rinst <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2943\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:2947\n"  , $time); 
if (set_mem_do_rdata) begin 
mem_do_rdata <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2948\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:2952\n"  , $time); 
if (set_mem_do_wdata) begin 
mem_do_wdata <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:2953\n"  , $time); 
end 
 
irq_pending <= next_irq_pending & ~MASKED_IRQ; 
$fwrite(f,"%0t cycle :picorv32.v:2957\n"  , $time); 
 
$fwrite(f,"%0t cycle :picorv32.v:2961\n"  , $time); 
if (!CATCH_MISALIGN) begin 
$fwrite(f,"%0t cycle :picorv32.v:2963\n"  , $time); 
if (COMPRESSED_ISA) begin 
reg_pc[0] <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2964\n"  , $time); 
reg_next_pc[0] <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2966\n"  , $time); 
end else begin 
reg_pc[1:0] <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2969\n"  , $time); 
reg_next_pc[1:0] <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:2971\n"  , $time); 
end 
end 
current_pc = 'bx; 
$fwrite(f,"%0t cycle :picorv32.v:2975\n"  , $time); 
end 
 
`ifdef RISCV_FORMAL 
reg dbg_irq_call; 
reg dbg_irq_enter; 
reg [31:0] dbg_irq_ret; 
always @(posedge clk) begin 
rvfi_valid <= resetn && (launch_next_insn || trap) && dbg_valid_insn; 
$fwrite(f,"%0t cycle :picorv32.v:2984\n"  , $time); 
rvfi_order <= resetn ? rvfi_order + rvfi_valid : 0; 
$fwrite(f,"%0t cycle :picorv32.v:2986\n"  , $time); 
 
rvfi_insn <= dbg_insn_opcode; 
$fwrite(f,"%0t cycle :picorv32.v:2989\n"  , $time); 
rvfi_rs1_addr <= dbg_rs1val_valid ? dbg_insn_rs1 : 0; 
$fwrite(f,"%0t cycle :picorv32.v:2991\n"  , $time); 
rvfi_rs2_addr <= dbg_rs2val_valid ? dbg_insn_rs2 : 0; 
$fwrite(f,"%0t cycle :picorv32.v:2993\n"  , $time); 
rvfi_pc_rdata <= dbg_insn_addr; 
$fwrite(f,"%0t cycle :picorv32.v:2995\n"  , $time); 
rvfi_rs1_rdata <= dbg_rs1val_valid ? dbg_rs1val : 0; 
$fwrite(f,"%0t cycle :picorv32.v:2997\n"  , $time); 
rvfi_rs2_rdata <= dbg_rs2val_valid ? dbg_rs2val : 0; 
$fwrite(f,"%0t cycle :picorv32.v:2999\n"  , $time); 
rvfi_trap <= trap; 
$fwrite(f,"%0t cycle :picorv32.v:3001\n"  , $time); 
rvfi_halt <= trap; 
$fwrite(f,"%0t cycle :picorv32.v:3003\n"  , $time); 
rvfi_intr <= dbg_irq_enter; 
$fwrite(f,"%0t cycle :picorv32.v:3005\n"  , $time); 
rvfi_mode <= 3; 
$fwrite(f,"%0t cycle :picorv32.v:3007\n"  , $time); 
 
$fwrite(f,"%0t cycle :picorv32.v:3011\n"  , $time); 
if (!resetn) begin 
dbg_irq_call <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:3012\n"  , $time); 
dbg_irq_enter <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:3014\n"  , $time); 
end else 
$fwrite(f,"%0t cycle :picorv32.v:3018\n"  , $time); 
if (rvfi_valid) begin 
dbg_irq_call <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:3019\n"  , $time); 
dbg_irq_enter <= dbg_irq_call; 
$fwrite(f,"%0t cycle :picorv32.v:3021\n"  , $time); 
end else 
$fwrite(f,"%0t cycle :picorv32.v:3024\n"  , $time); 
if (irq_state == 1) begin 
dbg_irq_call <= 1; 
$fwrite(f,"%0t cycle :picorv32.v:3026\n"  , $time); 
dbg_irq_ret <= next_pc; 
$fwrite(f,"%0t cycle :picorv32.v:3028\n"  , $time); 
end 
 
$fwrite(f,"%0t cycle :picorv32.v:3033\n"  , $time); 
if (!resetn) begin 
rvfi_rd_addr <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:3034\n"  , $time); 
rvfi_rd_wdata <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:3036\n"  , $time); 
end else 
$fwrite(f,"%0t cycle :picorv32.v:3040\n"  , $time); 
if (cpuregs_write && !irq_state) begin 
rvfi_rd_addr <= latched_rd; 
$fwrite(f,"%0t cycle :picorv32.v:3041\n"  , $time); 
rvfi_rd_wdata <= latched_rd ? cpuregs_wrdata : 0; 
$fwrite(f,"%0t cycle :picorv32.v:3043\n"  , $time); 
end else 
$fwrite(f,"%0t cycle :picorv32.v:3047\n"  , $time); 
if (rvfi_valid) begin 
rvfi_rd_addr <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:3048\n"  , $time); 
rvfi_rd_wdata <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:3050\n"  , $time); 
end 
 
$fwrite(f,"%0t cycle :picorv32.v:3055\n"  , $time); 
casez (dbg_insn_opcode) 
32'b 0000000_?????_000??_???_?????_0001011: begin // getq 
rvfi_rs1_addr <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:3057\n"  , $time); 
rvfi_rs1_rdata <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:3059\n"  , $time); 
end 
32'b 0000001_?????_?????_???_000??_0001011: begin // setq 
rvfi_rd_addr <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:3063\n"  , $time); 
rvfi_rd_wdata <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:3065\n"  , $time); 
end 
32'b 0000010_?????_00000_???_00000_0001011: begin // retirq 
rvfi_rs1_addr <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:3069\n"  , $time); 
rvfi_rs1_rdata <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:3071\n"  , $time); 
end 
endcase 
 
$fwrite(f,"%0t cycle :picorv32.v:3077\n"  , $time); 
if (!dbg_irq_call) begin 
$fwrite(f,"%0t cycle :picorv32.v:3079\n"  , $time); 
if (dbg_mem_instr) begin 
rvfi_mem_addr <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:3080\n"  , $time); 
rvfi_mem_rmask <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:3082\n"  , $time); 
rvfi_mem_wmask <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:3084\n"  , $time); 
rvfi_mem_rdata <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:3086\n"  , $time); 
rvfi_mem_wdata <= 0; 
$fwrite(f,"%0t cycle :picorv32.v:3088\n"  , $time); 
end else 
$fwrite(f,"%0t cycle :picorv32.v:3092\n"  , $time); 
if (dbg_mem_valid && dbg_mem_ready) begin 
rvfi_mem_addr <= dbg_mem_addr; 
$fwrite(f,"%0t cycle :picorv32.v:3093\n"  , $time); 
rvfi_mem_rmask <= dbg_mem_wstrb ? 0 : ~0; 
$fwrite(f,"%0t cycle :picorv32.v:3095\n"  , $time); 
rvfi_mem_wmask <= dbg_mem_wstrb; 
$fwrite(f,"%0t cycle :picorv32.v:3097\n"  , $time); 
rvfi_mem_rdata <= dbg_mem_rdata; 
$fwrite(f,"%0t cycle :picorv32.v:3099\n"  , $time); 
rvfi_mem_wdata <= dbg_mem_wdata; 
$fwrite(f,"%0t cycle :picorv32.v:3101\n"  , $time); 
end 
end 
end 
 
always @* begin 
rvfi_pc_wdata = dbg_irq_call ? dbg_irq_ret : dbg_insn_addr; 
$fwrite(f,"%0t cycle :picorv32.v:3108\n"  , $time); 
end 
`endif 
 
// Formal Verification 
`ifdef FORMAL 
reg [3:0] last_mem_nowait; 
always @(posedge clk) begin 
last_mem_nowait <= {last_mem_nowait, mem_ready || !mem_valid}; 
$fwrite(f,"%0t cycle :picorv32.v:3117\n"  , $time); 
end 
 
// stall the memory interface for max 4 cycles 
restrict property (|last_mem_nowait || mem_ready || !mem_valid); 
 
// resetn low in first cycle, after that resetn high 
restrict property (resetn != $initstate); 
$fwrite(f,"%0t cycle :picorv32.v:3125\n"  , $time); 
 
// this just makes it much easier to read traces. uncomment as needed. 
// assume property (mem_valid || !mem_ready); 
 
reg ok; 
always @* begin 
$fwrite(f,"%0t cycle :picorv32.v:3134\n"  , $time); 
if (resetn) begin 
// instruction fetches are read-only 
$fwrite(f,"%0t cycle :picorv32.v:3137\n"  , $time); 
if (mem_valid && mem_instr) begin 
assert (mem_wstrb == 0); 
$fwrite(f,"%0t cycle :picorv32.v:3138\n"  , $time); 
end 
 
// cpu_state must be valid 
ok = 0; 
$fwrite(f,"%0t cycle :picorv32.v:3143\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32.v:3145\n"  , $time); 
if (cpu_state == cpu_state_trap) begin 
ok = 1; 
$fwrite(f,"%0t cycle :picorv32.v:3147\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:3150\n"  , $time); 
if (cpu_state == cpu_state_fetch) begin 
ok = 1; 
$fwrite(f,"%0t cycle :picorv32.v:3152\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:3155\n"  , $time); 
if (cpu_state == cpu_state_ld_rs1) begin 
ok = 1; 
$fwrite(f,"%0t cycle :picorv32.v:3157\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:3160\n"  , $time); 
if (cpu_state == cpu_state_ld_rs2) begin 
ok = !ENABLE_REGS_DUALPORT; 
$fwrite(f,"%0t cycle :picorv32.v:3162\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:3165\n"  , $time); 
if (cpu_state == cpu_state_exec) begin 
ok = 1; 
$fwrite(f,"%0t cycle :picorv32.v:3167\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:3170\n"  , $time); 
if (cpu_state == cpu_state_shift) begin 
ok = 1; 
$fwrite(f,"%0t cycle :picorv32.v:3172\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:3175\n"  , $time); 
if (cpu_state == cpu_state_stmem) begin 
ok = 1; 
$fwrite(f,"%0t cycle :picorv32.v:3177\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:3180\n"  , $time); 
if (cpu_state == cpu_state_ldmem) begin 
ok = 1; 
$fwrite(f,"%0t cycle :picorv32.v:3182\n"  , $time); 
end 
assert (ok); 
end 
end 
 
reg last_mem_la_read = 0; 
$fwrite(f,"%0t cycle :picorv32.v:3189\n"  , $time); 
reg last_mem_la_write = 0; 
$fwrite(f,"%0t cycle :picorv32.v:3191\n"  , $time); 
reg [31:0] last_mem_la_addr; 
reg [31:0] last_mem_la_wdata; 
reg [3:0] last_mem_la_wstrb = 0; 
$fwrite(f,"%0t cycle :picorv32.v:3195\n"  , $time); 
 
always @(posedge clk) begin 
last_mem_la_read <= mem_la_read; 
$fwrite(f,"%0t cycle :picorv32.v:3199\n"  , $time); 
last_mem_la_write <= mem_la_write; 
$fwrite(f,"%0t cycle :picorv32.v:3201\n"  , $time); 
last_mem_la_addr <= mem_la_addr; 
$fwrite(f,"%0t cycle :picorv32.v:3203\n"  , $time); 
last_mem_la_wdata <= mem_la_wdata; 
$fwrite(f,"%0t cycle :picorv32.v:3205\n"  , $time); 
last_mem_la_wstrb <= mem_la_wstrb; 
$fwrite(f,"%0t cycle :picorv32.v:3207\n"  , $time); 
 
$fwrite(f,"%0t cycle :picorv32.v:3211\n"  , $time); 
if (last_mem_la_read) begin 
assert(mem_valid); 
assert(mem_addr == last_mem_la_addr); 
$fwrite(f,"%0t cycle :picorv32.v:3213\n"  , $time); 
assert(mem_wstrb == 0); 
$fwrite(f,"%0t cycle :picorv32.v:3215\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:3219\n"  , $time); 
if (last_mem_la_write) begin 
assert(mem_valid); 
assert(mem_addr == last_mem_la_addr); 
$fwrite(f,"%0t cycle :picorv32.v:3221\n"  , $time); 
assert(mem_wdata == last_mem_la_wdata); 
$fwrite(f,"%0t cycle :picorv32.v:3223\n"  , $time); 
assert(mem_wstrb == last_mem_la_wstrb); 
$fwrite(f,"%0t cycle :picorv32.v:3225\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32.v:3229\n"  , $time); 
if (mem_la_read || mem_la_write) begin 
assert(!mem_valid || mem_ready); 
end 
end 
`endif 
endmodule 
 
 
 
 
/*************************************************************** 
* picorv32_pcpi_div 
***************************************************************/ 
 
