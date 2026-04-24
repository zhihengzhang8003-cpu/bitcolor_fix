//============================================================================
// UART 接收模块
// 波特率可配置，8N1格式
//============================================================================

module uart_rx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid
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

// 输入同步
reg [2:0] rx_sync;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        rx_sync <= 3'b111;
    else
        rx_sync <= {rx_sync[1:0], rx};
end

wire rx_falling = (rx_sync[2:1] == 2'b10);

// 接收状态机
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        cnt <= 16'd0;
        bit_idx <= 3'd0;
        shift_reg <= 8'd0;
        data <= 8'd0;
        valid <= 1'b0;
    end else begin
        valid <= 1'b0;
        
        case (state)
            IDLE: begin
                if (rx_falling) begin
                    state <= START;
                    cnt <= 16'd0;
                end
            end
            
            START: begin
                if (cnt == BIT_PERIOD/2 - 1) begin
                    if (rx_sync[2] == 1'b0) begin
                        state <= DATA;
                        cnt <= 16'd0;
                        bit_idx <= 3'd0;
                    end else begin
                        state <= IDLE;
                    end
                end else begin
                    cnt <= cnt + 1;
                end
            end
            
            DATA: begin
                if (cnt == BIT_PERIOD - 1) begin
                    cnt <= 16'd0;
                    shift_reg[bit_idx] <= rx_sync[2];
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
                if (cnt == BIT_PERIOD - 1) begin
                    data <= shift_reg;
                    valid <= 1'b1;
                    state <= IDLE;
                end else begin
                    cnt <= cnt + 1;
                end
            end
        endcase
    end
end

endmodule
