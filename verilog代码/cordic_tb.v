`timescale 1ns/1ns


module cordic_tb ();

parameter   MAX_CNT     =   70      ;   // 每隔 70 个时钟，输入下一个角度
parameter	N_INT		=	4	    ;   // 整数位宽
parameter	N_FRAC		=	12	    ;   // 小数部分位宽
parameter	BIT_WIDTH	=	16	    ;   // 整体位宽
parameter	K		    =	2487	;   // K=0.6072529350088814 的定点数表达
parameter	DEPTH		=	12	    ;   // 参考角度数量

parameter   N           =   300     ;   // 测试数据长度

reg sys_clk;
reg sys_rst_n;


reg[7:0]            cnt;                // 下标变换的间隔计数
wire[15:0]          theta;              // 角度值
reg[10:0]           index;              // 角度以及计算好的 cos、sin数据的下标，0~300
wire                idx_add;            // index++ 标志
reg                 theta_in_flag;      // 角度数据输入信号

wire[BIT_WIDTH-1:0] cos_real;
wire[BIT_WIDTH-1:0] sin_real;   
wire[BIT_WIDTH-1:0] cos_cordic;
wire[BIT_WIDTH-1:0] sin_cordic;   
wire                valid;

reg[BIT_WIDTH-1:0]  cos_data[N-1:0];    // 提前计算好的 cos 值，用来验证
reg[BIT_WIDTH-1:0]  sin_data[N-1:0];    // 提前计算好的 sin 值，用来验证
reg[BIT_WIDTH-1:0]  theta_data[N-1:0];  // 角度定点表达


assign  idx_add = (cnt == MAX_CNT-1) & (index < N);
assign  theta = (index < N-1 ? theta_data[index] : 0);
assign  cos_real = (index < N-1 ? cos_data[index] : 0);
assign  sin_real = (index < N-1 ? sin_data[index] : 0);
// 加载文件
initial begin
    $readmemh("G:/my_program/VerilogHDL/cordic/sim/cos.txt", cos_data);
    $readmemh("G:/my_program/VerilogHDL/cordic/sim/sin.txt", sin_data);
    $readmemh("G:/my_program/VerilogHDL/cordic/sim/theta.txt", theta_data);
end

// 初始化相关操作
initial begin
    sys_clk <= 1'b1;
    sys_rst_n <= 1'b0;
    #40 sys_rst_n <= 1'b1;
end

always  begin
    #5 sys_clk <= ~sys_clk;
end


// 5个时钟发送一次
always @(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        cnt <= 8'd0;
    else
        cnt <= (cnt==MAX_CNT ? 8'd0 : cnt+1'b1);
end

// 数据输入信号
always @(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        theta_in_flag <= 0;
    else 
        theta_in_flag <= (cnt == 0) & (index < N);
end

always @(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        index <= 0;
    else if(idx_add)
        index <= (index >= N ? index : index+10);
end

cordic #(
    .N_INT(N_INT),
    .N_FRAC(N_FRAC),
    .BIT_WIDTH(BIT_WIDTH),
    .DEPTH(DEPTH),
    .K(K)
)
ci(
    .sys_clk(sys_clk),
    .sys_rst_n(sys_rst_n),
    .theta(theta),
    .start(theta_in_flag),
    .sin(sin_cordic),
    .cos(cos_cordic),
    .valid(valid)
);

endmodule
