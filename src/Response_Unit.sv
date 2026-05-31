// ============================================================
// Response_Unit.sv
// Two response channels:
//   1. Hit response FIFO
//   2. Miss response FIFO
//
// Uses existing FIFO module exactly as provided.
// Miss FIFO has priority over hit FIFO.
// ============================================================

module Response_Unit #(
    parameter int DATA_WIDTH   = 32,
    parameter int CPU_ID_WIDTH = 4,
    parameter int FIFO_DEPTH   = 64
)(
    input  logic clk,
    input  logic rst,

    // Hit response input
    input  logic                    hit_valid,
    output logic                    hit_ready,
    input  logic [DATA_WIDTH-1:0]   hit_data,
    input  logic [CPU_ID_WIDTH-1:0] hit_id,

    // Miss response input
    input  logic                    miss_valid,
    output logic                    miss_ready,
    input  logic [DATA_WIDTH-1:0]   miss_data,
    input  logic [CPU_ID_WIDTH-1:0] miss_id,

    // CPU response output
    output logic                    cpu_resp_valid,
    input  logic                    cpu_resp_ready,
    output logic                    cpu_resp_hit,
    output logic [DATA_WIDTH-1:0]   cpu_resp_rdata,
    output logic [CPU_ID_WIDTH-1:0] cpu_resp_id
);

    localparam int RESP_WIDTH = 1 + CPU_ID_WIDTH + DATA_WIDTH;

    logic hit_fifo_full;
    logic hit_fifo_empty;
    logic hit_fifo_rd_en;
    logic hit_fifo_rd_valid;
    logic [RESP_WIDTH-1:0] hit_fifo_wr_data;
    logic [RESP_WIDTH-1:0] hit_fifo_rd_data;

    logic miss_fifo_full;
    logic miss_fifo_empty;
    logic miss_fifo_rd_en;
    logic miss_fifo_rd_valid;
    logic [RESP_WIDTH-1:0] miss_fifo_wr_data;
    logic [RESP_WIDTH-1:0] miss_fifo_rd_data;

    logic read_allowed;
    logic choose_miss;
    logic choose_hit;

    logic out_valid_r;
    logic out_hit_r;
    logic [DATA_WIDTH-1:0]   out_data_r;
    logic [CPU_ID_WIDTH-1:0] out_id_r;

    assign hit_ready  = !hit_fifo_full;
    assign miss_ready = !miss_fifo_full;

    assign hit_fifo_wr_data  = {1'b1, hit_id, hit_data};
    assign miss_fifo_wr_data = {1'b0, miss_id, miss_data};

    FIFO #(
        .WIDTH(RESP_WIDTH),
        .DEPTH(FIFO_DEPTH)
    ) HIT_FIFO (
        .clk     (clk),
        .rst     (rst),

        .full    (hit_fifo_full),
        .wr_en   (hit_valid && hit_ready),
        .wr_data (hit_fifo_wr_data),

        .empty   (hit_fifo_empty),
        .rd_en   (hit_fifo_rd_en),
        .rd_valid(hit_fifo_rd_valid),
        .rd_data (hit_fifo_rd_data)
    );

    FIFO #(
        .WIDTH(RESP_WIDTH),
        .DEPTH(FIFO_DEPTH)
    ) MISS_FIFO (
        .clk     (clk),
        .rst     (rst),

        .full    (miss_fifo_full),
        .wr_en   (miss_valid && miss_ready),
        .wr_data (miss_fifo_wr_data),

        .empty   (miss_fifo_empty),
        .rd_en   (miss_fifo_rd_en),
        .rd_valid(miss_fifo_rd_valid),
        .rd_data (miss_fifo_rd_data)
    );

    assign read_allowed = !out_valid_r || cpu_resp_ready;

    assign choose_miss = read_allowed && !miss_fifo_empty;
    assign choose_hit  = read_allowed &&  miss_fifo_empty && !hit_fifo_empty;

    assign miss_fifo_rd_en = choose_miss;
    assign hit_fifo_rd_en  = choose_hit;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            out_valid_r <= 1'b0;
            out_hit_r   <= 1'b0;
            out_data_r  <= '0;
            out_id_r    <= '0;
        end
        else begin
            if (cpu_resp_ready) begin
                out_valid_r <= 1'b0;
            end

            if (miss_fifo_rd_valid) begin
                out_valid_r <= 1'b1;
                out_hit_r   <= miss_fifo_rd_data[RESP_WIDTH-1];
                out_id_r    <= miss_fifo_rd_data[DATA_WIDTH +: CPU_ID_WIDTH];
                out_data_r  <= miss_fifo_rd_data[DATA_WIDTH-1:0];
            end
            else if (hit_fifo_rd_valid) begin
                out_valid_r <= 1'b1;
                out_hit_r   <= hit_fifo_rd_data[RESP_WIDTH-1];
                out_id_r    <= hit_fifo_rd_data[DATA_WIDTH +: CPU_ID_WIDTH];
                out_data_r  <= hit_fifo_rd_data[DATA_WIDTH-1:0];
            end
        end
    end

    assign cpu_resp_valid = out_valid_r;
    assign cpu_resp_hit   = out_hit_r;
    assign cpu_resp_rdata = out_data_r;
    assign cpu_resp_id    = out_id_r;

endmodule