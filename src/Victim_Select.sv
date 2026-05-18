// ============================================================
// Victim selection logic
// Uses an invalid way first; otherwise uses replacement policy
// ============================================================

module Victim_Select #(
    parameter int ASSOC = 4,

    parameter int WAY_W = (ASSOC <= 1) ? 1 : $clog2(ASSOC)
)(
    input  logic [ASSOC-1:0] valid_vec,
    input  logic [ASSOC-1:0] dirty_vec,

    input  logic [WAY_W-1:0] replacement_way,

    output logic [WAY_W-1:0] victim_way,
    output logic             victim_dirty,
    output logic             invalid_found
);

    always_comb begin
        victim_way    = replacement_way;
        invalid_found = 1'b0;

        // Pick first invalid way if the set is not full
        for (int i = 0; i < ASSOC; i++) begin
            if (!valid_vec[i] && !invalid_found) begin
                victim_way    = WAY_W'(i);
                invalid_found = 1'b1;
            end
        end
    end

    assign victim_dirty = dirty_vec[victim_way];

endmodule