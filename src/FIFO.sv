module fifo #(
    parameter int WIDTH = 16,
    parameter int DEPTH = 32
) (
    input  logic             clk,
    input  logic             rst,

    output logic             full,
    input  logic             wr_en,
    input  logic [WIDTH-1:0] wr_data,

    output logic             empty,
    input  logic             rd_en,
    output logic             rd_valid,
    output logic [WIDTH-1:0] rd_data
);

    logic [WIDTH-1:0] ram [DEPTH];

    logic valid_wr;
    logic valid_rd;

    localparam int ADDR_WIDTH = $clog2(DEPTH) + 1;

    logic [ADDR_WIDTH-1:0] wr_addr_r;
    logic [ADDR_WIDTH-1:0] rd_addr_r;

    always_ff @(posedge clk) begin
        if (valid_wr) begin
            ram[wr_addr_r[ADDR_WIDTH-2:0]] <= wr_data;
        end

        rd_data <= ram[rd_addr_r[ADDR_WIDTH-2:0]];
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_addr_r <= '0;
            wr_addr_r <= '0;
            rd_valid  <= 1'b0;
        end
        else begin
            rd_valid <= valid_rd;

            if (valid_wr) begin
                wr_addr_r <= wr_addr_r + 1'b1;
            end

            if (valid_rd) begin
                rd_addr_r <= rd_addr_r + 1'b1;
            end
        end
    end

    assign valid_wr = wr_en && !full;
    assign valid_rd = rd_en && !empty;

    assign full  = (rd_addr_r[ADDR_WIDTH-2:0] == wr_addr_r[ADDR_WIDTH-2:0]) &&
                   (rd_addr_r[ADDR_WIDTH-1]   != wr_addr_r[ADDR_WIDTH-1]);

    assign empty = rd_addr_r == wr_addr_r;

endmodule