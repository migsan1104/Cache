// ============================================================
// Tag compare logic
// hit = valid bit is set and stored tag matches request tag
// ============================================================

module Tag #(
    parameter int TAG_BITS = 20
)(
    input  logic [TAG_BITS-1:0] req_tag,
    input  logic [TAG_BITS-1:0] stored_tag,
    input  logic                valid,

    output logic                hit
);

    assign hit = valid && (stored_tag == req_tag);

endmodule

