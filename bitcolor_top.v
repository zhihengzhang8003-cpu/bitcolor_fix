//============================================================================
// BitColor 图着色加速器 - 修复版
// 芯片: EP4CE10F17C8 (64顶点, 512边)
//============================================================================

module bitcolor_top (
    input  wire       sys_clk,
    input  wire       sys_rst_n,
    input  wire       uart_rx,
    output wire       uart_tx,
    input  wire       key_start,
    output wire [3:0] led
);

//============================================================================
// 参数
//============================================================================
parameter CLK_FREQ  = 50_000_000;
parameter BAUD_RATE = 115200;

//============================================================================
// Block RAM - offset存储 (65个元素)
//============================================================================
reg [8:0] offset_mem [0:64];
reg [8:0] offset_rd_data;
reg [5:0] offset_addr;
reg [8:0] offset_wr_data;
reg       offset_wr_en;

always @(posedge sys_clk) begin
    if (offset_wr_en)
        offset_mem[offset_addr] <= offset_wr_data;
    offset_rd_data <= offset_mem[offset_addr];
end

//============================================================================
// Block RAM - edge存储 (512个元素)
//============================================================================
reg [5:0] edge_mem [0:511];
reg [5:0] edge_rd_data;
reg [8:0] edge_addr;
reg [5:0] edge_wr_data;
reg       edge_wr_en;

always @(posedge sys_clk) begin
    if (edge_wr_en)
        edge_mem[edge_addr] <= edge_wr_data;
    edge_rd_data <= edge_mem[edge_addr];
end

//============================================================================
// Block RAM - color存储 (64个元素)
//============================================================================
reg [4:0] color_mem [0:63];
reg [4:0] color_rd_data;
reg [5:0] color_addr;
reg [4:0] color_wr_data;
reg       color_wr_en;

always @(posedge sys_clk) begin
    if (color_wr_en)
        color_mem[color_addr] <= color_wr_data;
    color_rd_data <= color_mem[color_addr];
end

//============================================================================
// 内部信号
//============================================================================
wire key_start_pulse;
wire [7:0] rx_data;
wire rx_valid;
wire tx_ready;
reg  [7:0] tx_data;
reg  tx_valid;

// 状态机
reg [3:0] state;
localparam S_IDLE      = 4'd0;
localparam S_LOAD      = 4'd1;
localparam S_RUN       = 4'd2;
localparam S_SEND      = 4'd3;
localparam S_DONE      = 4'd4;
localparam S_SEND_TIME = 4'd5;

// 图参数
reg [5:0] vertex_count;
reg [8:0] edge_count;

// 加载状态
reg [7:0] load_state;
reg [8:0] load_idx;
reg [7:0] high_byte;

// 发送状态
reg [5:0] send_idx;
reg [2:0] send_byte_idx;
reg       send_wait;

// 计时器
reg [31:0] cycle_counter;
reg [31:0] total_cycles;
reg timing_active;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n)
        cycle_counter <= 32'd0;
    else if (timing_active)
        cycle_counter <= cycle_counter + 1;
    else if (state == S_IDLE)
        cycle_counter <= 32'd0;
end

// 迭代控制
reg [15:0] iteration_count;
reg [15:0] current_iteration;
reg [5:0]  current_vertex;

//============================================================================
// 子模块
//============================================================================
key_debounce u_key (
    .clk(sys_clk), .rst_n(sys_rst_n),
    .key_in(key_start), .key_pulse(key_start_pulse)
);

uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_rx (
    .clk(sys_clk), .rst_n(sys_rst_n),
    .rx(uart_rx), .data(rx_data), .valid(rx_valid)
);

uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_tx (
    .clk(sys_clk), .rst_n(sys_rst_n),
    .data(tx_data), .valid(tx_valid), .tx(uart_tx), .ready(tx_ready)
);

//============================================================================
// BWPE - 位运算着色引擎
//============================================================================
reg [31:0] neighbor_colors;
reg [8:0]  neighbor_start;
reg [8:0]  neighbor_end;
reg [8:0]  neighbor_idx;
reg [3:0]  bwpe_state;
reg [5:0]  neighbor_vertex;
reg        bwpe_start;

localparam BWPE_IDLE    = 4'd0;
localparam BWPE_LOAD1   = 4'd1;
localparam BWPE_LOAD2   = 4'd2;
localparam BWPE_LOOP    = 4'd3;
localparam BWPE_READ1   = 4'd4;
localparam BWPE_READ2   = 4'd5;
localparam BWPE_COLLECT = 4'd6;
localparam BWPE_COLOR1  = 4'd7;
localparam BWPE_COLOR2  = 4'd8;
localparam BWPE_DONE    = 4'd9;

wire [31:0] available_colors = ~neighbor_colors;
wire [4:0] first_zero;

first_one_detect u_fod (
    .data_in(available_colors),
    .first_one(first_zero),
    .valid()
);

wire bwpe_done = (bwpe_state == BWPE_DONE);

//============================================================================
// 主状态机
//============================================================================
reg [5:0] max_color_used;
reg engine_running;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        state <= S_IDLE;
        bwpe_state <= BWPE_IDLE;
        
        vertex_count <= 6'd7;
        edge_count <= 9'd14;
        iteration_count <= 16'd1;
        current_iteration <= 16'd0;
        current_vertex <= 6'd0;
        max_color_used <= 6'd0;
        engine_running <= 1'b0;
        timing_active <= 1'b0;
        total_cycles <= 32'd0;
        
        bwpe_start <= 1'b0;
        neighbor_colors <= 32'd0;
        neighbor_idx <= 9'd0;
        
        tx_valid <= 1'b0;
        load_state <= 8'd0;
        load_idx <= 9'd0;
        send_idx <= 6'd0;
        send_byte_idx <= 3'd0;
        send_wait <= 1'b0;
        high_byte <= 8'd0;
        
        offset_wr_en <= 1'b0;
        edge_wr_en <= 1'b0;
        color_wr_en <= 1'b0;
        offset_addr <= 6'd0;
        edge_addr <= 9'd0;
        color_addr <= 6'd0;
        
    end else begin
        // 默认关闭写使能和发送
        bwpe_start <= 1'b0;
        tx_valid <= 1'b0;
        offset_wr_en <= 1'b0;
        edge_wr_en <= 1'b0;
        color_wr_en <= 1'b0;
        
        //================================================================
        // BWPE 状态机
        //================================================================
        case (bwpe_state)
            BWPE_IDLE: begin
                if (bwpe_start) begin
                    neighbor_colors <= 32'd0;
                    offset_addr <= current_vertex;
                    bwpe_state <= BWPE_LOAD1;
                end
            end
            
            BWPE_LOAD1: begin
                offset_addr <= current_vertex + 1;
                bwpe_state <= BWPE_LOAD2;
            end
            
            BWPE_LOAD2: begin
                neighbor_start <= offset_rd_data;
                neighbor_idx <= offset_rd_data;
                bwpe_state <= BWPE_LOOP;
            end
            
            BWPE_LOOP: begin
                neighbor_end <= offset_rd_data;
                if (neighbor_idx >= offset_rd_data) begin
                    bwpe_state <= BWPE_DONE;
                end else begin
                    edge_addr <= neighbor_idx;
                    bwpe_state <= BWPE_READ1;
                end
            end
            
            BWPE_READ1: begin
                bwpe_state <= BWPE_READ2;
            end
            
            BWPE_READ2: begin
                neighbor_vertex <= edge_rd_data;
                if (edge_rd_data < current_vertex) begin
                    color_addr <= edge_rd_data;
                    bwpe_state <= BWPE_COLOR1;
                end else begin
                    neighbor_idx <= neighbor_idx + 1;
                    bwpe_state <= BWPE_LOOP;
                end
            end
            
            BWPE_COLOR1: begin
                bwpe_state <= BWPE_COLOR2;
            end
            
            BWPE_COLOR2: begin
                neighbor_colors <= neighbor_colors | (32'd1 << color_rd_data);
                neighbor_idx <= neighbor_idx + 1;
                bwpe_state <= BWPE_LOOP;
            end
            
            BWPE_DONE: begin
                bwpe_state <= BWPE_IDLE;
            end
        endcase
        
        //================================================================
        // 主状态机
        //================================================================
        case (state)
            //------------------------------------------------------------
            S_IDLE: begin
                engine_running <= 1'b0;
                timing_active <= 1'b0;
                
                if (key_start_pulse) begin
                    state <= S_RUN;
                    current_vertex <= 6'd0;
                    current_iteration <= 16'd0;
                    max_color_used <= 6'd0;
                    engine_running <= 1'b1;
                    timing_active <= 1'b1;
                end
                
                if (rx_valid) begin
                    case (rx_data)
                        8'h01: begin 
                            state <= S_LOAD; 
                            load_state <= 8'd0; 
                            load_idx <= 9'd0; 
                        end
                        8'h02: begin
                            state <= S_RUN;
                            current_vertex <= 6'd0;
                            current_iteration <= 16'd0;
                            max_color_used <= 6'd0;
                            engine_running <= 1'b1;
                            timing_active <= 1'b1;
                        end
                        8'h03: begin 
                            state <= S_SEND; 
                            send_idx <= 6'd0;
                            send_wait <= 1'b0;
                        end
                        8'h04: load_state <= 8'd100;
                        8'h05: begin 
                            state <= S_SEND_TIME; 
                            send_byte_idx <= 3'd0; 
                        end
                    endcase
                end
                
                // 迭代次数设置
                if (load_state == 8'd100 && rx_valid) begin
                    high_byte <= rx_data;
                    load_state <= 8'd101;
                end else if (load_state == 8'd101 && rx_valid) begin
                    iteration_count <= {high_byte, rx_data};
                    load_state <= 8'd0;
                    tx_data <= 8'hBB;
                    tx_valid <= 1'b1;
                end
            end
            
            //------------------------------------------------------------
            S_LOAD: begin
                if (rx_valid) begin
                    case (load_state)
                        8'd0: begin 
                            vertex_count <= rx_data[5:0]; 
                            load_state <= 8'd1; 
                        end
                        8'd1: begin 
                            high_byte <= rx_data; 
                            load_state <= 8'd2; 
                        end
                        8'd2: begin 
                            edge_count <= {high_byte[0], rx_data}; 
                            load_state <= 8'd3; 
                            load_idx <= 9'd0; 
                        end
                        8'd3: begin 
                            high_byte <= rx_data; 
                            load_state <= 8'd4; 
                        end
                        8'd4: begin
                            offset_addr <= load_idx[5:0];
                            offset_wr_data <= {high_byte[0], rx_data};
                            offset_wr_en <= 1'b1;
                            if (load_idx >= vertex_count) begin
                                load_state <= 8'd5;
                                load_idx <= 9'd0;
                            end else begin
                                load_idx <= load_idx + 1;
                                load_state <= 8'd3;
                            end
                        end
                        8'd5: begin
                            edge_addr <= load_idx;
                            edge_wr_data <= rx_data[5:0];
                            edge_wr_en <= 1'b1;
                            if (load_idx >= edge_count - 1) begin
                                state <= S_IDLE;
                                tx_data <= 8'hAA;
                                tx_valid <= 1'b1;
                            end else begin
                                load_idx <= load_idx + 1;
                            end
                        end
                    endcase
                end
            end
            
            //------------------------------------------------------------
            S_RUN: begin
                if (current_vertex >= vertex_count) begin
                    current_iteration <= current_iteration + 1;
                    if (current_iteration + 1 >= iteration_count) begin
                        state <= S_DONE;
                        engine_running <= 1'b0;
                        timing_active <= 1'b0;
                        total_cycles <= cycle_counter;
                    end else begin
                        current_vertex <= 6'd0;
                        max_color_used <= 6'd0;
                    end
                end else if (bwpe_done) begin
                    color_addr <= current_vertex;
                    color_wr_data <= first_zero;
                    color_wr_en <= 1'b1;
                    if (first_zero >= max_color_used)
                        max_color_used <= first_zero + 1;
                    current_vertex <= current_vertex + 1;
                    bwpe_start <= 1'b1;
                end else if (bwpe_state == BWPE_IDLE && !bwpe_start) begin
                    bwpe_start <= 1'b1;
                end
            end
            
            //------------------------------------------------------------
            S_SEND: begin
                if (send_wait) begin
                    send_wait <= 1'b0;
                end else if (tx_ready && !tx_valid) begin
                    if (send_idx == 0) begin
                        tx_data <= {2'b00, max_color_used};
                        tx_valid <= 1'b1;
                        send_idx <= send_idx + 1;
                    end else if (send_idx <= vertex_count) begin
                        color_addr <= send_idx - 1;
                        send_wait <= 1'b1;
                        // 下一周期读取并发送
                        if (!send_wait) begin
                            tx_data <= {3'b000, color_rd_data};
                            tx_valid <= 1'b1;
                            send_idx <= send_idx + 1;
                        end
                    end else begin
                        state <= S_DONE;
                    end
                end
            end
            
            //------------------------------------------------------------
            S_SEND_TIME: begin
                if (tx_ready && !tx_valid) begin
                    case (send_byte_idx)
                        3'd0: begin tx_data <= total_cycles[31:24]; tx_valid <= 1'b1; send_byte_idx <= 3'd1; end
                        3'd1: begin tx_data <= total_cycles[23:16]; tx_valid <= 1'b1; send_byte_idx <= 3'd2; end
                        3'd2: begin tx_data <= total_cycles[15:8];  tx_valid <= 1'b1; send_byte_idx <= 3'd3; end
                        3'd3: begin tx_data <= total_cycles[7:0];   tx_valid <= 1'b1; send_byte_idx <= 3'd4; end
                        3'd4: state <= S_DONE;
                    endcase
                end
            end
            
            //------------------------------------------------------------
            S_DONE: begin
                if (key_start_pulse || (rx_valid && rx_data == 8'h00)) 
                    state <= S_IDLE;
                else if (rx_valid && rx_data == 8'h03) begin 
                    state <= S_SEND; 
                    send_idx <= 6'd0;
                    send_wait <= 1'b0;
                end
                else if (rx_valid && rx_data == 8'h05) begin 
                    state <= S_SEND_TIME; 
                    send_byte_idx <= 3'd0; 
                end
            end
        endcase
    end
end

//============================================================================
// LED
//============================================================================
reg [23:0] hb_cnt;
always @(posedge sys_clk) hb_cnt <= hb_cnt + 1;

assign led[0] = ~hb_cnt[23];
assign led[1] = ~engine_running;
assign led[2] = ~(state == S_DONE);
assign led[3] = ~timing_active;

endmodule
