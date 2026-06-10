// ============================================================
// Simple parameterized RAM with two write ports and one read port
// Port A has priority if both ports write the same address
// CPU side should connect to port A
// Refill side should connect to port B
// Reset clears entire RAM contents
// ============================================================

module RAM_2W1R_Reset #(
    parameter int D_WIDTH      = 32,
    parameter int DEPTH        = 256,
    parameter int READ_LATENCY = 1
)(
    input  logic                         clk,
    input  logic                         rst,

    // Port A (CPU)
    input  logic                         wen_a,
    input  logic [$clog2(DEPTH)-1:0]     waddr_a,
    input  logic [D_WIDTH-1:0]           wdata_a,

    // Port B (Refill)
    input  logic                         wen_b,
    input  logic [$clog2(DEPTH)-1:0]     waddr_b,
    input  logic [D_WIDTH-1:0]           wdata_b,

    // Read
    input  logic [$clog2(DEPTH)-1:0]     raddr,
    output logic [D_WIDTH-1:0]           rdata
);

    logic [D_WIDTH-1:0] mem [DEPTH-1:0];

    logic [D_WIDTH-1:0] rdata_raw;

    // ============================================================
    // RAM storage
    // ============================================================

    always @(posedge clk) begin

        if (rst) begin
            for (int i = 0; i < DEPTH; i++) begin
                mem[i] <= '0;
            end
        end
        else begin

            // Port B write
            if (wen_b)
                mem[waddr_b] <= wdata_b;

            // Port A write (higher priority)
            if (wen_a)
                mem[waddr_a] <= wdata_a;

        end

    end

    // ============================================================
    // Read port
    // ============================================================

    assign rdata_raw = mem[raddr];

    Delay #(
        .D_WIDTH(D_WIDTH),
        .DELAY  (READ_LATENCY)
    ) READ_DELAY (
        .clk (clk),
        .din (rdata_raw),
        .dout(rdata)
    );

endmodule