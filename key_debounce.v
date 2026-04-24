//============================================================================
// 按键消抖模块
//============================================================================

module key_debounce (
    input  wire clk,
    input  wire rst_n,
    input  wire key_in,
    output reg  key_pulse
);

parameter DEBOUNCE_TIME = 20'd1_000_000;  // 20ms @ 50MHz

reg [19:0] cnt;
reg key_reg;
reg key_reg_d;

// 同步输入
reg [1:0] key_sync;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        key_sync <= 2'b11;
    else
        key_sync <= {key_sync[0], key_in};
end

// 消抖计数
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cnt <= 20'd0;
        key_reg <= 1'b1;
    end else begin
        if (key_sync[1] != key_reg) begin
            if (cnt >= DEBOUNCE_TIME - 1) begin
                cnt <= 20'd0;
                key_reg <= key_sync[1];
            end else begin
                cnt <= cnt + 1;
            end
        end else begin
            cnt <= 20'd0;
        end
    end
end

// 边沿检测 - 下降沿产生脉冲
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        key_reg_d <= 1'b1;
        key_pulse <= 1'b0;
    end else begin
        key_reg_d <= key_reg;
        key_pulse <= key_reg_d & ~key_reg;  // 下降沿
    end
end

endmodule
