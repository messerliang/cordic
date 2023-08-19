/*
 * 使用 cordic 算法，以及定点小数，来计算三角函数
 *
 */

module cordic#(
    //-----------------------定义查表参数----------------------
    parameter	N_INT		=	8	,   // 整数位宽
    parameter	N_FRAC		=	8	,   // 小数位宽
    parameter   BIT_WIDTH   =   16  ,   // 定点小数位宽
    parameter	K		    =	155	,   // 增益 0.6072529350088814 的定点数表达
    parameter	DEPTH		=	8	,   // cordic 算法的迭代次数，迭代次数受到 N_FRAC的影响
    parameter	HALF_PI		=	402	,   // pi / 2 的定点表示
    parameter	THETA_REF0	=	201	,   // 提前计算好的角度值
    parameter	THETA_REF1	=	118	,
    parameter	THETA_REF2	=	62	,
    parameter	THETA_REF3	=	31	,
    parameter	THETA_REF4	=	15	,
    parameter	THETA_REF5	=	7	,
    parameter	THETA_REF6	=	3	,
    parameter	THETA_REF7	=	1	 
)
(
    input   wire                sys_clk     ,
    input   wire                sys_rst_n   ,
    input   wire[BIT_WIDTH-1:0] theta       ,   // 输入的角度
    input   wire                start       ,   // 持续一个时钟的开始信号

    output  reg[BIT_WIDTH-1:0]  sin         ,   // 输出定点表达的 sin 值
    output  reg[BIT_WIDTH-1:0]  cos         ,   // 输出定点表达的 cos 值
    output  reg                 valid           // 持续一个时钟的输出信号有效
);

    localparam  IDLE        =   4'b0001,    // 空闲
                CHECK_SIGN  =   4'b0010,    // 检查输入的角度的符号
                CHANGE_QUAD =   4'b0100,    // 将输入的角度通过加减 pi / 2 ，变到第1象限
                CORDICING   =   4'b1000,    // 正在进行 cordic 算法迭代
                CORDIC_END  =   4'b1001;    // cordic 算法结束
    
    //----------------------寄存器变量-------------------------
    reg[7:0]    cnt_iter            ;   // 当前的迭代次数
    reg         neg_flag            ;   // 判断输入的角度是否是负数
    reg[1:0]    quad_idx            ;   // 所输入的角度所在的象限，0~3对应 1~4 象限
    reg[3:0]    state               ;   // 表明当前所处的状态
    reg[BIT_WIDTH-1:0]  theta_reg   ;   // 缓存输入的角度 theta
    reg[BIT_WIDTH-1:0]  theta_app   ;   // 用 theta_app 来逼近 theta_reg
    reg[BIT_WIDTH-1:0]  sin_reg     ;   // 计算过程缓存 sin 
    reg[BIT_WIDTH-1:0]  cos_reg     ;   // 计算过程缓存 cos
    reg[BIT_WIDTH-1:0]  sin_reg_rshift     ; //右移结果
    reg[BIT_WIDTH-1:0]  cos_reg_rshift     ; //右移结果
    reg[1:0]    shift_flag          ;   // 计算负数移位包括3个步骤：负数求补-> 移位 -> 再求补
                                        // 整数的话，直接移位即可

    //----------------------线变量定义--------------------------
    wire[BIT_WIDTH-1:0] THETA_REFS[DEPTH-1:0] ; // 提前计算好的各个角度的定点数表示

    wire                change_quad_end     ;   // 完成角度到第一象限的变换
    wire                cordic_iter_end     ;   // cordic 迭代过程结束
    
    assign		THETA_REFS[0]	=	THETA_REF0	;
    assign		THETA_REFS[1]	=	THETA_REF1	;
    assign		THETA_REFS[2]	=	THETA_REF2	;
    assign		THETA_REFS[3]	=	THETA_REF3	;
    assign		THETA_REFS[4]	=	THETA_REF4	;
    assign		THETA_REFS[5]	=	THETA_REF5	;
    assign		THETA_REFS[6]	=	THETA_REF6	;
    assign		THETA_REFS[7]	=	THETA_REF7	;

    // 左边变换结束
    assign      change_quad_end = ( CHANGE_QUAD==state && (theta_reg <= HALF_PI));
    // cordic 迭代过程结束
    assign      cordic_iter_end = ( (CORDICING == state) && 
                                        ( (cnt_iter == DEPTH) 
                                        || (theta_app + 1 == theta_reg) 
                                        || (theta_app == theta_reg + 1) 
                                        || (theta_app == theta_reg)
                                        ) 
                                    );
    //-----------------------状态机跳转-------------------------
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n)
            state <= IDLE;
        else
            case (state)
                IDLE:       // 由开始脉冲来启动
                    state <= (start ? CHECK_SIGN : state);
                CHECK_SIGN: // 检查输入角度的符号
                    state <= CHANGE_QUAD;
                CHANGE_QUAD:// 变换到第一象限后，跳转到下一个状态
                    state <= (change_quad_end ? CORDICING : state);
                CORDICING:
                    state <= (cordic_iter_end ? CORDIC_END : state);
                CORDIC_END:
                    state <= IDLE;
                default: 
                    state <= IDLE;
            endcase
    end

    //------------------theta_reg 接收输入的角度，并进行象限调整-----------------
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n)begin
            theta_reg <= {BIT_WIDTH{1'd0}};
            quad_idx <= 2'd0;
        end
        else if(IDLE == state )begin // 在开始信号驱动下，从总线上缓存 theta
            theta_reg <= start ? theta : theta_reg;
            quad_idx <= 2'd0;
        end
        else if(CHECK_SIGN == state)begin // 如果是负数，将其变换为整数
            theta_reg <= ( theta_reg[BIT_WIDTH-1] ? ~theta_reg + 1'b1 : theta_reg );
        end
        else if(CHANGE_QUAD == state)begin // 如果不在第一象限，就变换到第一象限
            if(theta_reg > HALF_PI)begin
                theta_reg <= theta_reg - HALF_PI;
                quad_idx <= quad_idx + 1'b1;
            end
        end
    end    

    //-----------------------检查输入角度的符号-----------------------
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n)
            neg_flag <= 1'b0;
        else if(IDLE == state)        //空闲时置为 0
            neg_flag <= 1'b0;
        else if(CHECK_SIGN == state)
            neg_flag <= (theta_reg[BIT_WIDTH - 1]); // 只有在 check_sign 状态下才进行标志位检查
        else
            neg_flag <= neg_flag;
    end    

    //----------------------cordic迭代过程的计算--------------------------
    always @(posedge sys_clk or negedge sys_rst_n) begin // 移位标志
        if(!sys_rst_n || IDLE == state)
            shift_flag <= 2'd0;
        else if(CORDICING == state && ~cordic_iter_end)begin
            shift_flag <= shift_flag + 1'b1;
        end
    end

    always @(posedge sys_clk or negedge sys_rst_n) begin // 先计算移位的结果
        if(!sys_rst_n || IDLE == state)begin
            sin_reg_rshift <= 0;
            cos_reg_rshift <= 0;
        end
        else if(CORDICING == state && ~cordic_iter_end )begin
            case (shift_flag)
                2'b00: begin    // 判断是不是负数，如果是负数，则先求补，相当于变成正数
                    sin_reg_rshift <= sin_reg[BIT_WIDTH-1] ? ( ((~sin_reg + 1) )) : sin_reg;
                    cos_reg_rshift <= cos_reg[BIT_WIDTH-1] ? ( ((~cos_reg + 1) )) : cos_reg;      
                end
                2'b01: begin    // 移位操作
                    sin_reg_rshift <= (sin_reg_rshift >> cnt_iter );
                    cos_reg_rshift <= (cos_reg_rshift >> cnt_iter );
                end
                2'b10: begin    // 恢复原来
                    sin_reg_rshift <= sin_reg[BIT_WIDTH-1] ? ( ((~sin_reg_rshift + 1) )) : sin_reg_rshift;
                    cos_reg_rshift <= cos_reg[BIT_WIDTH-1] ? ( ((~cos_reg_rshift + 1) )) : cos_reg_rshift;             
                end
                default: begin
                    sin_reg_rshift <= sin_reg_rshift;
                    cos_reg_rshift <= cos_reg_rshift;
                end
            endcase

        end
    end

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n || IDLE == state)begin
            theta_app   <= {BIT_WIDTH{1'd0}};
            sin_reg     <= 0;
            cos_reg     <= K;
            cnt_iter    <= 8'd0;
        end
        else if(CORDICING == state && ~cordic_iter_end && 2'b11 == shift_flag)begin
            theta_app   <= (theta_app > theta_reg) ? (theta_app + (~THETA_REFS[cnt_iter] + 1)) : ( theta_app + (THETA_REFS[cnt_iter]) );
            cnt_iter <= cnt_iter + 1;

            if(theta_app > theta_reg)begin // d = -1，反向旋转的情况
                // theta_app <= theta_app + (~THETA_REFS[cnt_iter] + 1);
                // 移位不能丢掉高位的符号位
                cos_reg <= cos_reg + (sin_reg_rshift) ;
                sin_reg <= sin_reg + (~(cos_reg_rshift) + 1'b1);
            end
            else begin // d = 1，正向旋转
                cos_reg <= cos_reg + (~(sin_reg_rshift) + 1);
                sin_reg <= sin_reg + ( cos_reg_rshift );
            end
            
        end

    end    


    //-----------------------输出 cos, sin 计算结果-------------------------------
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n)begin
            valid <=1'b0;
            sin         <= 0;   // 最终输出的 sin
            cos         <= 0;   // 最终输出的 cos            
        end
        else if(CORDIC_END == state)begin
            valid <= 1'b1;
            case (quad_idx)
                2'd0: begin // theta 位于第一象限
                    cos <= cos_reg;
                    sin <= sin_reg;
                end
                2'd1: begin // theta 位于第二象限
                    cos <= (~sin_reg + 1);
                    sin <= cos_reg;
                end
                2'd2: begin // theta 位于第三象限
                    cos <= (~cos_reg + 1);
                    sin <= (~sin_reg + 1);
                end
                2'd3: begin // theta 位于第四象限
                    cos <= (sin_reg);
                    sin <= (~cos_reg + 1);
                end
                default: begin
                    cos <= cos;
                    sin <= sin;
                end
            endcase            
        end
        else    // valid 信号只持续一个时钟
            valid <= 1'b0;
    end

endmodule