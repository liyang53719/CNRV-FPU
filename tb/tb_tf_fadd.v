
`include "R5FP_inc.vh"

module R5FP_add_wrap #(
	parameter USE_ACC=0,
	parameter EXP_W=5,
	parameter SIG_W=10) (
	input [EXP_W+SIG_W:0] a, b,
	input  [2:0] rnd,
	output reg [7:0] zStatus,
	output [EXP_W+SIG_W:0] z);

localparam I_SIG_W=SIG_W*2+5;
localparam EXP_W_P1=EXP_W+1;

wire [EXP_W+SIG_W+1:0] ax, bx, zx;
wire [EXP_W:0] zExp,tailZeroCnt;
wire [6-1:0] zStatusMiddle;
wire [I_SIG_W-1:0] zSig;
wire zSign;

R5FP_exp_incr #(
	.SIG_W(SIG_W),
	.EXP_W(EXP_W)) a_i (.a(a), .z(ax));
R5FP_exp_incr #(
	.SIG_W(SIG_W),
	.EXP_W(EXP_W)) b_i (.a(b), .z(bx));

wire [EXP_W_P1-1:0] dExp;
wire [6-1:0] dStatus;
wire [SIG_W*2+2:0] dSig;
wire dSign;
generate
if (USE_ACC) begin
	R5FP_mul_by_1 #(
		.EXP_W(EXP_W_P1),
		.SIG_W(SIG_W)) mul (
		.a(ax),
		.zExp(dExp),
		.zStatus(dStatus),
		.zSig(dSig),
		.zSign(dSign));
	R5FP_acc #(
		.SIG_W(SIG_W),
		.EXP_W(EXP_W_P1)) acc (
		.dExp(dExp),
		.dStatus(dStatus),
		.dSig(dSig),
		.dSign(dSign),
		.toInf(1'b0),
		.c(bx),
		.rnd(rnd),

/* verilator lint_off  PINCONNECTEMPTY */
		.zToInf(),
		.specialTiny(),
/* verilator lint_on  PINCONNECTEMPTY */
		.zExp(zExp), .tailZeroCnt(tailZeroCnt), .zStatus(zStatusMiddle),
		.zSig(zSig), .zSign(zSign));
end
else begin
	R5FP_add #(
		.SIG_W(SIG_W),
		.EXP_W(EXP_W+1)) add (
		.a(ax), .b(bx),
		.zExp(zExp), .tailZeroCnt(tailZeroCnt), .zStatus(zStatusMiddle),
		.zSig(zSig), .zSign(zSign));
end
endgenerate

R5FP_postproc #(
	.I_SIG_W(I_SIG_W),
	.SIG_W(SIG_W),
	.EXP_W(EXP_W+1)) pp (
	.tailZeroCnt(tailZeroCnt),
	.aExp(zExp),
	.aStatus(zStatusMiddle),
	.aSig(zSig),
	.rnd(rnd),
	.aSign(zSign),
	.zToInf(1'b0),
	.specialTiny(1'b0),
	.z(zx),
	.zStatus(zStatus));

R5FP_exp_decr #(
	.SIG_W(SIG_W),
	.EXP_W(EXP_W)) z_d (.a(zx), .z(z));

endmodule

///////////////////////////////////////////////////////////////////
module tb_fp_add(input clk, 
/* verilator lint_off UNUSED */
	input reset, 
/* verilator lint_on UNUSED */
	input [2:0] rnd);

`ifdef FP64
parameter EXP_W=11;
parameter SIG_W=52;
`else
parameter EXP_W=8;
parameter SIG_W=23;
`endif
integer fd, readcount;

logic aSign;
logic bSign;
logic ySign;
logic z0Sign;
logic [SIG_W-1:0] aSig;
logic [SIG_W-1:0] bSig;
logic [SIG_W-1:0] ySig;
logic [SIG_W-1:0] z0Sig;
logic [EXP_W-1:0] aExp;
logic [EXP_W-1:0] bExp;
logic [EXP_W-1:0] yExp;
logic [EXP_W-1:0] z0Exp;
logic [7:0] ySpre;
logic [4:0] s0pre,s0,yS;
assign yS=to_tf_flags(ySpre);
logic [EXP_W+SIG_W:0] a,b,z0;
assign {aSign,aExp,aSig}=a;
assign {bSign,bExp,bSig}=b;
assign {z0Sign,z0Exp,z0Sig}=z0;

R5FP_add_wrap #(
	.USE_ACC(1),
	.EXP_W(EXP_W),
	.SIG_W(SIG_W)) I (
	.a(a), .b(b), .rnd(rnd[2:0]), .z({ySign,yExp,ySig}), .zStatus(ySpre));

initial begin
	fd=$fopen("/dev/stdin","r");
	$display("fd is %d", fd);
	readcount = $fscanf(fd, "DUMP: %x %x %x %x", a, b, z0, s0pre);
	$display("New data:  %h %h %h %b", a, b, z0, s0pre);
	if(readcount != 4) $display("Read Error! %d", readcount);
end
/* verilator lint_off BLKSEQ */
always @(negedge clk) begin
	if($feof(fd)) $finish();
	readcount = $fscanf(fd, "DUMP: %x %x %x %x", a, b, z0, s0pre);
	//$display("New data:  %h %h %h %b", a, b, z0, s0pre);
	if(readcount != 4) begin
		$display("Read Error! %d", readcount);
		$finish();
	end
end

always @(posedge clk) begin
	//$display("Now a: %b.%b.%b  b: %b.%b.%b", aSign,aExp,aSig,  bSign,bExp,bSig);
	reg pass;
	pass={z0Sign,z0Exp,z0Sig}=={ySign,yExp,ySig}||{z0Exp,z0Sig,yExp,ySig}==0;

	//special case for NaN
	if((&z0Exp)==1&&(&yExp)==1&&z0Sig!=0&&ySig!=0) pass=1;

	s0=s0pre;
	s0[3]=0; //useless bit

	if(s0!=yS) pass=0;
	if(pass) begin
		//$display("Pass");
		//$display("a:  %b.%b.%b  b:  %b.%b.%b  z0: %b.%b.%b", aSign,aExp,aSig,  bSign,bExp,bSig,  z0Sign,z0Exp,z0Sig);
		//$display("a:  %b.%b.%b  b:  %b.%b.%b  y:  %b.%b.%b", aSign,aExp,aSig,  bSign,bExp,bSig, ySign,yExp,ySig);
		//$display("----");
	end
	else begin
		$display("Fail!!");
		$display("a b: %08h %08h",a,b);
		$display("a:  %b.%b.%b  b:  %b.%b.%b  z0: %b.%b.%b", aSign,aExp,aSig,  bSign,bExp,bSig,  z0Sign,z0Exp,z0Sig);
		$display("a:  %b.%b.%b  b:  %b.%b.%b  y:  %b.%b.%b", aSign,aExp,aSig,  bSign,bExp,bSig, ySign,yExp,ySig);
		$display("ax: %b.%b.%b bx: %b.%b.%b zx: %b.%b.%b", I.ax[EXP_W+SIG_W+1],I.ax[EXP_W+SIG_W:SIG_W],I.ax[SIG_W-1:0], I.bx[EXP_W+SIG_W+1],I.bx[EXP_W+SIG_W:SIG_W],I.bx[SIG_W-1:0], I.zx[EXP_W+SIG_W+1],I.zx[EXP_W+SIG_W:SIG_W],I.zx[SIG_W-1:0]);
		$display("dx: %b.%b.%b", I.dSign, I.dExp, I.dSig);
		//$display("s0: %b  yS:%b invalid:%b zStatusMiddle:%b pp.zStatus:%b ySpre:%b", 
		//	s0, yS, I.add.I.isInvalid, I.zStatusMiddle, I.pp.zStatus, ySpre);
		$finish();
	end
end
/* verilator lint_on BLKSEQ */

endmodule

