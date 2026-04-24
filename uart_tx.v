//============================================================================
// UART 发送模块
// 波特率可配置，8N1格式
//============================================================================

module uart_tx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       valid,
    output reg        tx,
    output wire       ready
);

localparam BIT_PERIOD = CLK_FREQ / BAUD_RATE;

// 状态定义
localparam IDLE  = 2'd0;
localparam START = 2'd1;
localparam DATA  = 2'd2;
localparam STOP  = 2'd3;

reg [1:0]  state;
reg [15:0] cnt;
reg [2:0]  bit_idx;
reg [7:0]  shift_reg;

assign ready = (state == IDLE);

// 发送状态机
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        cnt <= 16'd0;
        bit_idx <= 3'd0;
        shift_reg <= 8'd0;
        tx <= 1'b1;
    end else begin
        case (state)
            IDLE: begin
                tx <= 1'b1;
                if (valid) begin
                    shift_reg <= data;
                    state <= START;
                    cnt <= 16'd0;
                end
            end
            
            START: begin
                tx <= 1'b0;  // 起始位
                if (cnt == BIT_PERIOD - 1) begin
                    cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    state <= DATA;
                end else begin
                    cnt <= cnt + 1;
                end
            end
            
            DATA: begin
                tx <= shift_reg[bit_idx];
                if (cnt == BIT_PERIOD - 1) begin
                    cnt <= 16'd0;
                    if (bit_idx == 3'd7) begin
                        state <= STOP;
                    end else begin
                        bit_idx <= bit_idx + 1;
                    end
                end else begin
                    cnt <= cnt + 1;
                end
            end
            
            STOP: begin
                tx <= 1'b1;  // 停止位
                if (cnt == BIT_PERIOD - 1) begin
                    state <= IDLE;
                end else begin
                    cnt <= cnt + 1;
                end
            end
        endcase
    end
end

endmodule
