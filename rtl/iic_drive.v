`timescale 1ns / 1ns
//****************************************VSCODE PLUG-IN**********************************// 
//---------------------------------------------------------------------------------------- 
// IDE :                   VSCODE      
// VSCODE plug-in version: Verilog-Hdl-Format-2.4.20240526
// VSCODE plug-in author : Jiang Percy 
//---------------------------------------------------------------------------------------- 
//****************************************Copyright (c)***********************************// 
// Copyright(C)            xlx_fpga
// All rights reserved      
// File name:               
// Last modified Date:     2024/07/09 10:23:36 
// Last Version:           V1.0 
// Descriptions:            
//---------------------------------------------------------------------------------------- 
// Created by:             xlx_fpga
// Created date:           2024/07/09 10:23:36 
// Version:                V1.0 
// TEXT NAME:              iic_drive.v 
// PATH:                   E:\3.xlx_fpga\5.IIC\rtl\iic_drive.v 
// Descriptions:            
//                          
//---------------------------------------------------------------------------------------- 
//****************************************************************************************// 

module iic_drive#(
    parameter                                   DEVICE_ADDR        = 7'b101_0000,//IIC从机设备地址
    parameter                                   REG_ADDR_WIDTH     = 16    , //存储器地址位宽，支持8bit或者16bit
    parameter                                   CLK_FREQ           = 50_000_000, //模块clk时钟频率
    parameter                                   IIC_FREQ           = 100_000//标准模式100K,快速模式400k,高速模式3.4M	
)
(
    input                                       clk                 ,
    input                                       rst                 ,
    //***************************************************************************************
    // iic物理端信号                                                                                    
    //***************************************************************************************
    output reg                                  scl                 ,
    inout                                       sda                 ,
    //***************************************************************************************
    // iic用户端信号                                                                                    
    //***************************************************************************************
    input                                       iic_start_en        ,//iic使能信号
    input                                       iic_wr_rd           ,//iic读写控制信号，0为写，1为读
    input              [REG_ADDR_WIDTH-1: 0]    iic_reg_addr        ,//iic读写字地址
    input              [11: 0]                  iic_length          ,//支持一次读写一页
    input              [7: 0]                   iic_wr_data         ,//用户写数据
    output reg         [7: 0]                   iic_rd_data         ,//iic读数据
    output reg                                  iic_busy             //iic忙信号
);
    localparam                                  DIV_CNT_MAX        = CLK_FREQ / IIC_FREQ -1;

    reg                [$clog2(DIV_CNT_MAX)-1: 0]div_cnt            ;
    reg                [4: 0]                   bit_cnt             ;
    reg                [REG_ADDR_WIDTH-1: 0]    iic_reg_addr_d0     ;
    reg                [11: 0]                  iic_length_d0       ;
    reg                [12: 0]                  wr_length_cnt       ;
    reg                [12: 0]                  rd_length_cnt       ;
    reg                                         dout_en             ;//发送数据为1，接收响应为0
    reg                                         dout                ;
    //8位设备地址+16位字地址
    reg                [23: 0]                  wr_data             ;
    //定义中间时刻
    wire                                        scl_high_mid        ;
    wire                                        scl_low_mid         ;

    assign scl_high_mid = div_cnt == DIV_CNT_MAX / 2 -1;  //iic时钟scl信号高电平中间时刻
    assign scl_low_mid  = div_cnt == DIV_CNT_MAX - 1   ;  //iic时钟scl信号低电平中间时刻
    assign sda          = dout_en == 1'b1 ? dout : 1'bz;

    //***************************************************************************************
    // 锁存字地址和长度                                                                                    
    //***************************************************************************************
    always @(posedge clk )
        begin
            if(iic_start_en) begin
                iic_reg_addr_d0 <= iic_reg_addr;
                iic_length_d0 <= iic_length;
        end
            else begin
                iic_reg_addr_d0 <= iic_reg_addr_d0;
                iic_length_d0 <= iic_length_d0;
        end
        end
    //***************************************************************************************
    // busy信号                                                                                    
    //***************************************************************************************
    always @(posedge clk )
        begin
            if(rst) begin
                iic_busy <= 0;
        end
            else if(cur_state !=IIC_IDLE) begin
                iic_busy <= 1;
        end
            else begin
                iic_busy <= iic_busy;
        end
        end
    //***************************************************************************************
    // 分频计数器                                                                                  
    //***************************************************************************************
    always @(posedge clk )
        begin
            if(rst) begin
                div_cnt <= 0;
        end
            else if(div_cnt == DIV_CNT_MAX) begin
                div_cnt <= 0;
        end
            else if(cur_state ==IIC_IDLE) begin
                div_cnt <= 0;
        end
            else begin
                div_cnt <= div_cnt + 1;
        end
        end
    //***************************************************************************************
    // scl时钟产生                                                                                    
    //***************************************************************************************
    always @(posedge clk )
        begin
            if(rst) begin
                scl <= 1;
        end
            else if(cur_state == IIC_IDLE || cur_state == IIC_STOP) begin
                scl <= 1;
        end
            else begin
                scl <= (div_cnt>=DIV_CNT_MAX/4-1)&&(div_cnt<=DIV_CNT_MAX*2/4 -1)?1'b1:0;
        end
        end
    //***************************************************************************************
    // bit_cnt                                                                                    
    //***************************************************************************************
    always @(posedge clk )
        begin
            if(rst) begin
                bit_cnt <= 0;
        end
            else if(next_state != cur_state) begin
                bit_cnt <= 0;
        end
            else if(bit_cnt == 8 && div_cnt == DIV_CNT_MAX) begin
                bit_cnt <= 0;
        end
            else if(div_cnt == DIV_CNT_MAX) begin
                bit_cnt <= bit_cnt +1;
        end
            else begin
                bit_cnt <= bit_cnt;
        end
        end
    //***************************************************************************************
    // wr_length_cnt                                                                                    
    //***************************************************************************************
    always @(posedge clk )
        begin
            if(rst) begin
                wr_length_cnt <= 0;
                rd_length_cnt <= 0;
        end
            else if(next_state != cur_state) begin
                wr_length_cnt <= 0;
                rd_length_cnt <= 0;
        end
            else if(cur_state == IIC_WRITE && bit_cnt == 8 && div_cnt == DIV_CNT_MAX) begin
                wr_length_cnt <= wr_length_cnt +1;
        end
            else if(cur_state == IIC_XUXIE && bit_cnt == 8 && div_cnt == DIV_CNT_MAX) begin
                rd_length_cnt <= rd_length_cnt +1;
        end
            else if(cur_state == IIC_RD_DATA && bit_cnt == 8 && div_cnt == DIV_CNT_MAX) begin
                rd_length_cnt <= rd_length_cnt +1;
        end
            else begin
                wr_length_cnt <= wr_length_cnt;
                rd_length_cnt <= rd_length_cnt;
        end
        end
    //***************************************************************************************
    // 状态机                                                                                    
    //***************************************************************************************
    localparam                                  IIC_IDLE           = 7'h0  ;
    //发送起始信号
    localparam                                  IIC_START          = 7'h1  ;    
    //发送{设备地址，1'b0}+响应，内存地址+响应，写数据+响应
    localparam                                  IIC_WRITE          = 7'h2  ;
    //发送{设备地址，1'b0}+响应，内存地址+响应，第二次start
    localparam                                  IIC_XUXIE          = 7'h4  ;
    //发送{设备地址，1'b1}+响应，
    localparam                                  IIC_RD_DEV         = 7'h8  ;
    //读出数据，发送响应
    localparam                                  IIC_RD_DATA        = 7'h10 ;
    //停止信号
    localparam                                  IIC_STOP           = 7'h20 ;

                                                              
    reg                [6: 0]                   cur_state           ;
    reg                [6: 0]                   next_state          ;
    //同步时序描述状态转移
    always @(posedge clk )
        begin
            if(rst)
                cur_state <= IIC_IDLE;
            else 
                cur_state <= next_state;
        end
    //组合逻辑判断状态转移条件
    always @( * ) begin
            case(cur_state)
                IIC_IDLE:
        begin
            if(iic_start_en)
                next_state <= IIC_START;
            else 
                next_state <= IIC_IDLE;
        end
                IIC_START:
        begin

            if(bit_cnt == DIV_CNT_MAX && (~iic_wr_rd)) begin
                next_state <= IIC_WRITE;
        end
            else if(bit_cnt == DIV_CNT_MAX && iic_wr_rd) begin
                next_state <= IIC_XUXIE;
        end
            else 
                next_state <= cur_state;
        end
                IIC_WRITE:
        begin
                        //没有接收到应答
            if(sda && bit_cnt == 8 && scl_high_mid) begin
                next_state <= IIC_IDLE;
        end
                        //写阶段一共发送字节数
            else if(wr_length_cnt == iic_length_d0 + REG_ADDR_WIDTH / 8 && bit_cnt==8 && div_cnt == DIV_CNT_MAX) begin
                next_state <= IIC_STOP;
        end
            else 
                next_state <= cur_state;
        end
                IIC_XUXIE:
        begin
                        //没有接收到应答
            if(sda && bit_cnt == 8 && scl_high_mid) begin
                next_state <= IIC_IDLE;
        end
            else if(rd_length_cnt == REG_ADDR_WIDTH/8 +1 && bit_cnt == 0 && div_cnt ==DIV_CNT_MAX) begin
                next_state <= IIC_RD_DEV;
        end
            else 
                next_state <= cur_state;
        end
                IIC_RD_DEV:
        begin
            if(sda && bit_cnt == 8 && scl_high_mid) begin
                next_state <= IIC_IDLE;
        end
            else if(bit_cnt == 8 && div_cnt == DIV_CNT_MAX) begin
                next_state <= IIC_RD_DATA;
        end
            else 
                next_state <= cur_state;
        end
                IIC_RD_DATA:
        begin

            if(sda && bit_cnt == 8 && scl_high_mid) begin
                next_state <= IIC_IDLE;
        end
            else if(rd_length_cnt == iic_length_d0 -1 &&bit_cnt == 8 && div_cnt == DIV_CNT_MAX) begin
                next_state <= IIC_STOP;
        end
            else 
                next_state <= cur_state;
        end
            IIC_STOP:
        begin
            if(div_cnt == DIV_CNT_MAX) begin
                next_state <= IIC_IDLE;
        end
            else 
                next_state <= cur_state;
        end
                default: next_state <= IIC_IDLE;
        endcase
        end

    //***************************************************************************************
    // dout_en                                                                                    
    //***************************************************************************************
    always @(posedge clk )
        begin
            if(rst) begin
                dout_en <= 0;
        end
            else if((cur_state == IIC_WRITE || cur_state == IIC_XUXIE || cur_state ==IIC_RD_DEV) && bit_cnt==8) begin
                dout_en <= 0;
        end
            else if(cur_state == IIC_RD_DATA && bit_cnt <= 7) begin
                dout_en <= 0;
        end
            else begin
                    dout_en =1;
        end
        end
    //***************************************************************************************
    // dout                                                                                   
    //***************************************************************************************
    always @(posedge clk )
        begin
                    //发送start信号                                        
            if(cur_state == IIC_START) begin
                dout <= (div_cnt <= DIV_CNT_MAX/2 )? 1'b1:1'b0;
        end
                    //发送stop信号                                  
            else if(cur_state == IIC_STOP) begin
                dout <= (div_cnt <= DIV_CNT_MAX/2 )? 1'b0:1'b1;
        end
                    //发送虚写的start信号
            else if(cur_state == IIC_XUXIE && rd_length_cnt == REG_ADDR_WIDTH/8 + 1 &&bit_cnt == 0) begin
                dout <= (div_cnt <= DIV_CNT_MAX/2 )? 1'b1:1'b0;
        end
                    //给从机发送响应
            else if(cur_state == IIC_RD_DATA && bit_cnt ==8 && rd_length_cnt < iic_length_d0 -1) begin
                dout <= 0;
        end
            else begin
                dout <= wr_data[23];
        end
        end
    //***************************************************************************************
    // wr_data                                                                                   
    //***************************************************************************************
    generate
            if(REG_ADDR_WIDTH == 16) begin
    always @(posedge clk )
        begin
            if(cur_state == IIC_WRITE && wr_length_cnt == 0 && bit_cnt == 0&& div_cnt == 0) begin
                wr_data <= {{DEVICE_ADDR,1'b0},iic_reg_addr_d0};
        end
            else if(cur_state == IIC_WRITE && wr_length_cnt>REG_ADDR_WIDTH/8 && bit_cnt ==0 && div_cnt ==0) begin
                wr_data <= {iic_wr_data,16'b0};
        end
            else if(cur_state == IIC_XUXIE&& rd_length_cnt == 0 && bit_cnt == 0&& div_cnt == 0) begin
                wr_data <= {{DEVICE_ADDR,1'b0},iic_reg_addr_d0};
        end
            else if(cur_state == IIC_RD_DEV &&rd_length_cnt == 0 && bit_cnt == 0&& div_cnt == 0) begin
                wr_data <= {{DEVICE_ADDR,1'b1},16'b0};
        end
            else if(div_cnt ==DIV_CNT_MAX && bit_cnt <=7) begin
                wr_data <= wr_data<<1;
        end
            else begin
                wr_data <= wr_data;
        end
        end
        end
            else if(REG_ADDR_WIDTH == 8) begin
    always @(posedge clk )
        begin
            if(cur_state == IIC_WRITE && wr_length_cnt==0 && div_cnt ==0 && bit_cnt==0) begin
                wr_data <= {{DEVICE_ADDR,1'b0},iic_reg_addr_d0,8'b0};
        end
            else if(cur_state == IIC_WRITE && wr_length_cnt >REG_ADDR_WIDTH/8 && bit_cnt==0 &&div_cnt ==0) begin
                wr_data <= {iic_wr_data,16'b0};
        end
            else if(cur_state == IIC_XUXIE && rd_length_cnt ==0 &&bit_cnt==0 &&div_cnt ==0) begin
                wr_data <= {{DEVICE_ADDR,1'b0},iic_reg_addr_d0,8'b0};
        end
            else if(cur_state == IIC_RD_DEV && rd_length_cnt ==0 &&bit_cnt==0 &&div_cnt ==0) begin
                wr_data <= {{DEVICE_ADDR,1'b1},16'b0};
        end
            else if(div_cnt == DIV_CNT_MAX && bit_cnt <=7) begin
                wr_data <= wr_data <<1;
        end
            else begin
                wr_data <= wr_data;
        end
        end
        end
        endgenerate
    //***************************************************************************************
    // iic_rd_data                                                                                    
    //***************************************************************************************
    always @(posedge clk )
        begin
            if(cur_state == IIC_RD_DATA && bit_cnt <8 && scl_high_mid) begin
                iic_rd_data <= {iic_rd_data[6:0],sda};
        end
            else begin
                iic_rd_data <= iic_rd_data;
        end
        end

        endmodule
