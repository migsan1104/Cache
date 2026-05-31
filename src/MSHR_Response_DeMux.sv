// ============================================================
// MSHR response valid demux
// Broadcasts response data to all MSHRs
// Routes only the valid pulse by response ID
// ============================================================

module MSHR_Response_DeMux #(
    parameter int MSHR_COUNT    = 4,
    parameter int DATA_WIDTH    = 32,
    parameter int MSHR_ID_WIDTH = 2
)(
    input  logic clk,
    input  logic rst,

    input  logic                     mem_resp_valid,
    input  logic [MSHR_ID_WIDTH-1:0] mem_resp_id,
    input  logic [DATA_WIDTH-1:0]    mem_resp_rdata,

    output logic [MSHR_COUNT-1:0]    mshr_resp_valid,
    output logic [DATA_WIDTH-1:0]    mshr_resp_data
);

    assign mshr_resp_data = mem_resp_rdata;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mshr_resp_valid <= '0;
        end
        else begin
            mshr_resp_valid <= '0;

            if (mem_resp_valid) begin
                mshr_resp_valid[mem_resp_id] <= 1'b1;
            end
        end
    end

endmodule