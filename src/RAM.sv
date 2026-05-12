// ============================================================
// Simple parameterized RAM with variable read latency
// READ_LATENCY = 0 creates combinational read data
// ============================================================

module RAM #(
    parameter int D_WIDTH      = 32,
    parameter int DEPTH        = 256,
    parameter int READ_LATENCY = 1
)(
    input  logic                         clk,

    input  logic                         wen,
    input  logic [$clog2(DEPTH)-1:0]     waddr,
    input  logic [D_WIDTH-1:0]           wdata,

    input  logic [$clog2(DEPTH)-1:0]     raddr,
    output logic [D_WIDTH-1:0]           rdata
);

    // Internal memory storage
    logic [D_WIDTH-1:0] mem [DEPTH-1:0];

    // Raw combinational read data before optional output delay
    logic [D_WIDTH-1:0] rdata_raw;

    // Synchronous write port
    always_ff @(posedge clk) begin
        if (wen)
            mem[waddr] <= wdata;
    end

    // Combinational read port
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