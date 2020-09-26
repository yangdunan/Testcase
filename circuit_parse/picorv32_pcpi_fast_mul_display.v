/* verilator lint_off WIDTH */ 
/* verilator lint_off CASEINCOMPLETE */ 
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
integer f; 
initial begin 
f = $fopen("cpu_rw_3.txt", "w"); 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:21\n"  , $time); 
end 
reg instr_mul, instr_mulh, instr_mulhsu, instr_mulhu; 
wire instr_any_mul = |{instr_mul, instr_mulh, instr_mulhsu, instr_mulhu}; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:25\n"  , $time); 
end 
wire instr_any_mulh = |{instr_mulh, instr_mulhsu, instr_mulhu}; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:29\n"  , $time); 
end 
wire instr_rs1_signed = |{instr_mulh, instr_mulhsu}; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:33\n"  , $time); 
end 
wire instr_rs2_signed = |{instr_mulh}; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:37\n"  , $time); 
end 
 
reg shift_out; 
reg [3:0] active; 
reg [32:0] rs1, rs2, rs1_q, rs2_q; 
reg [63:0] rd, rd_q; 
 
wire pcpi_insn_valid = pcpi_valid && pcpi_insn[6:0] == 7'b0110011 && pcpi_insn[31:25] == 7'b0000001; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:47\n"  , $time); 
end 
reg pcpi_insn_valid_q; 
 
always @* begin 
instr_mul = 0; 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:54\n"  , $time); 
instr_mulh = 0; 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:56\n"  , $time); 
instr_mulhsu = 0; 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:58\n"  , $time); 
instr_mulhu = 0; 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:60\n"  , $time); 
 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:64\n"  , $time); 
if (resetn && (EXTRA_INSN_FFS ? pcpi_insn_valid_q : pcpi_insn_valid)) begin 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:66\n"  , $time); 
case (pcpi_insn[14:12]) 
3'b000: begin 
instr_mul = 1; 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:68\n"  , $time); 
end 
3'b001: begin 
instr_mulh = 1; 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:72\n"  , $time); 
end 
3'b010: begin 
instr_mulhsu = 1; 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:76\n"  , $time); 
end 
3'b011: begin 
instr_mulhu = 1; 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:80\n"  , $time); 
end 
endcase 
end 
end 
 
always @(posedge clk) begin 
pcpi_insn_valid_q <= pcpi_insn_valid; 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:88\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:91\n"  , $time); 
if (!MUL_CLKGATE || active[0]) begin 
rs1_q <= rs1; 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:92\n"  , $time); 
rs2_q <= rs2; 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:94\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:98\n"  , $time); 
if (!MUL_CLKGATE || active[1]) begin 
rd <= $signed(EXTRA_MUL_FFS ? rs1_q : rs1) * $signed(EXTRA_MUL_FFS ? rs2_q : rs2); 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:99\n"  , $time); 
end 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:103\n"  , $time); 
if (!MUL_CLKGATE || active[2]) begin 
rd_q <= rd; 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:104\n"  , $time); 
end 
end 
 
always @(posedge clk) begin 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:111\n"  , $time); 
if (instr_any_mul && !(EXTRA_MUL_FFS ? active[3:0] : active[1:0])) begin 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:113\n"  , $time); 
if (instr_rs1_signed) begin 
rs1 <= $signed(pcpi_rs1); 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:114\n"  , $time); 
end 
else 
rs1 <= $unsigned(pcpi_rs1); 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:118\n"  , $time); 
 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:122\n"  , $time); 
if (instr_rs2_signed) begin 
rs2 <= $signed(pcpi_rs2); 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:123\n"  , $time); 
end 
else 
rs2 <= $unsigned(pcpi_rs2); 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:127\n"  , $time); 
active[0] <= 1; 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:129\n"  , $time); 
end else begin 
active[0] <= 0; 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:132\n"  , $time); 
end 
 
active[3:1] <= active; 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:136\n"  , $time); 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:138\n"  , $time); 
shift_out <= instr_any_mulh; 
 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:142\n"  , $time); 
if (!resetn) begin 
active <= 0; 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:143\n"  , $time); 
end 
end 
 
assign pcpi_wr = active[EXTRA_MUL_FFS ? 3 : 1]; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:148\n"  , $time); 
end 
assign pcpi_wait = 0; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:152\n"  , $time); 
end 
assign pcpi_ready = active[EXTRA_MUL_FFS ? 3 : 1]; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:156\n"  , $time); 
end 
`ifdef RISCV_FORMAL_ALTOPS 
assign pcpi_rd =instr_mul    ? (pcpi_rs1 + pcpi_rs2) ^ 32'h5876063e :instr_mulh   ? (pcpi_rs1 + pcpi_rs2) ^ 32'hf6583fb7 :instr_mulhsu ? (pcpi_rs1 - pcpi_rs2) ^ 32'hecfbe137 :instr_mulhu  ? (pcpi_rs1 + pcpi_rs2) ^ 32'h949ce5e8 : 1'bx; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:161\n"  , $time); 
end 
`else 
always@* begin 
$fwrite(f,"%0t cycle :picorv32_pcpi_fast_mul.v:169\n"  , $time); 
end
assign pcpi_rd = shift_out ? (EXTRA_MUL_FFS ? rd_q : rd) >> 32 : (EXTRA_MUL_FFS ? rd_q : rd); 
`endif 
endmodule 
