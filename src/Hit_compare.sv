// ============================================================
// Registered tag compare logic
// hit = valid bit is set and stored tag matches request tag
// ============================================================

module Hit_compare #(
    parameter int TAG_BITS = 20
)(
    input  logic                clk,
    input  logic                rst,

    input  logic [TAG_BITS-1:0] req_tag,
    input  logic [TAG_BITS-1:0] stored_tag,
    input  logic                valid,

    output logic                hit
);

    always_ff @(posedge clk) begin
        if (rst) begin
            hit <= 1'b0;
        end
        else begin
            hit <= valid && (stored_tag == req_tag);
        end
    end

endmodule