// ============================================================
// Simple parameterized RAM with two write ports and one read port
// Port A has priority if both ports write the same address
// CPU side should connect to port A
// Refill side should connect to port B
// READ_LATENCY = 0 creates combinational read data
// ============================================================

module RAM_2W1R #(
    parameter int D_WIDTH      = 32,
    parameter int DEPTH        = 256,
    parameter int READ_LATENCY = 1
)(
    input  logic                         clk,

    // ============================================================
    // Port A (CPU write-hit side)
    // Higher priority
    // ============================================================

    input  logic                         wen_a,
    input  logic [$clog2(DEPTH)-1:0]     waddr_a,
    input  logic [D_WIDTH-1:0]           wdata_a,

    // ============================================================
    // Port B (refill side)
    // Lower priority on same-address collision
    // ============================================================

    input  logic                         wen_b,
    input  logic [$clog2(DEPTH)-1:0]     waddr_b,
    input  logic [D_WIDTH-1:0]           wdata_b,

    // ============================================================
    // Read port
    // ============================================================

    input  logic [$clog2(DEPTH)-1:0]     raddr,
    output logic [D_WIDTH-1:0]           rdata
);

    logic [D_WIDTH-1:0] mem [DEPTH-1:0];

    logic [D_WIDTH-1:0] rdata_raw;

    // ============================================================
    // Dual write ports
    // Port A wins on same-address conflicts
    // ============================================================

    always_ff @(posedge clk) begin

        // Refill write
        if (wen_b) begin
            mem[waddr_b] <= wdata_b;
        end

        // CPU write-hit
        // Overrides refill if same address
        if (wen_a) begin
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