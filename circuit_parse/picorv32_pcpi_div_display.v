/* verilator lint_off WIDTH */ 
/* verilator lint_off CASEINCOMPLETE */ 
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
integer f ; 
initial begin 
f = $fopen("cpu_rw_2.txt", "w"); 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:17\n"  , $time); 
end 
reg instr_div, instr_divu, instr_rem, instr_remu; 
wire instr_any_div_rem = |{instr_div, instr_divu, instr_rem, instr_remu}; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:21\n"  , $time); 
end 
 
reg pcpi_wait_q; 
wire start = pcpi_wait && !pcpi_wait_q; 
always@* begin 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:27\n"  , $time); 
end 
 
always @(posedge clk) begin 
instr_div <= 0; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:33\n"  , $time); 
instr_divu <= 0; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:35\n"  , $time); 
instr_rem <= 0; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:37\n"  , $time); 
instr_remu <= 0; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:39\n"  , $time); 
 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:42\n"  , $time); 
if (resetn && pcpi_valid && !pcpi_ready && pcpi_insn[6:0] == 7'b0110011 && pcpi_insn[31:25] == 7'b0000001) begin 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:45\n"  , $time); 
case (pcpi_insn[14:12]) 
3'b100: begin 
instr_div <= 1; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:47\n"  , $time); 
end 
3'b101: begin 
instr_divu <= 1; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:51\n"  , $time); 
end 
3'b110: begin 
instr_rem <= 1; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:55\n"  , $time); 
end 
3'b111: begin 
instr_remu <= 1; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:59\n"  , $time); 
end 
endcase 
end 
 
pcpi_wait <= instr_any_div_rem && resetn; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:65\n"  , $time); 
pcpi_wait_q <= pcpi_wait && resetn; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:67\n"  , $time); 
end 
 
reg [31:0] dividend; 
reg [62:0] divisor; 
reg [31:0] quotient; 
reg [31:0] quotient_msk; 
reg running; 
reg outsign; 
 
always @(posedge clk) begin 
pcpi_ready <= 0; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:79\n"  , $time); 
pcpi_wr <= 0; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:81\n"  , $time); 
pcpi_rd <= 'bx; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:83\n"  , $time); 
 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:87\n"  , $time); 
if (!resetn) begin 
running <= 0; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:88\n"  , $time); 
end else 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:92\n"  , $time); 
if (start) begin 
running <= 1; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:93\n"  , $time); 
dividend <= (instr_div || instr_rem) && pcpi_rs1[31] ? -pcpi_rs1 : pcpi_rs1; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:95\n"  , $time); 
divisor <= ((instr_div || instr_rem) && pcpi_rs2[31] ? -pcpi_rs2 : pcpi_rs2) << 31; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:97\n"  , $time); 
outsign <= (instr_div && (pcpi_rs1[31] != pcpi_rs2[31]) && |pcpi_rs2) || (instr_rem && pcpi_rs1[31]); 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:99\n"  , $time); 
quotient <= 0; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:101\n"  , $time); 
quotient_msk <= 1 << 31; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:103\n"  , $time); 
end else 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:107\n"  , $time); 
if (!quotient_msk && running) begin 
running <= 0; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:108\n"  , $time); 
pcpi_ready <= 1; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:110\n"  , $time); 
pcpi_wr <= 1; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:112\n"  , $time); 
`ifdef RISCV_FORMAL_ALTOPS 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:116\n"  , $time); 
case (1) 
instr_div: begin 
pcpi_rd <= (pcpi_rs1 - pcpi_rs2) ^ 32'h7f8529ec; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:118\n"  , $time); 
end 
instr_divu: begin 
pcpi_rd <= (pcpi_rs1 - pcpi_rs2) ^ 32'h10e8fd70; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:122\n"  , $time); 
end 
instr_rem: begin 
pcpi_rd <= (pcpi_rs1 - pcpi_rs2) ^ 32'h8da68fa5; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:126\n"  , $time); 
end 
instr_remu: begin 
pcpi_rd <= (pcpi_rs1 - pcpi_rs2) ^ 32'h3138d0e1; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:130\n"  , $time); 
end 
endcase 
`else 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:136\n"  , $time); 
if (instr_div || instr_divu) begin 
pcpi_rd <= outsign ? -quotient : quotient; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:137\n"  , $time); 
end 
else 
pcpi_rd <= outsign ? -dividend : dividend; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:141\n"  , $time); 
`endif 
end else begin 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:145\n"  , $time); 
if (divisor <= dividend) begin 
dividend <= dividend - divisor; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:147\n"  , $time); 
quotient <= quotient | quotient_msk; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:149\n"  , $time); 
end 
divisor <= divisor >> 1; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:152\n"  , $time); 
`ifdef RISCV_FORMAL_ALTOPS 
quotient_msk <= quotient_msk >> 5; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:155\n"  , $time); 
`else 
quotient_msk <= quotient_msk >> 1; 
$fwrite(f,"%0t cycle :picorv32_pcpi_div.v:158\n"  , $time); 
`endif 
end 
end 
endmodule 
