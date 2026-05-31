// ============================================================
// Tree-based pseudo-LRU replacement policy
// ASSOC = 1 returns way 0
// ASSOC > 1 uses ASSOC-1 PLRU bits per set
//
// Includes invalid-way priority:
//   1. If any way is invalid, choose the first invalid way.
//   2. Otherwise choose the PLRU victim.
//
// Update occurs after:
//   - cache hit access
//   - refill/install access
// ============================================================

module Replacement #(
    parameter int ASSOC       = 4,
    parameter int NUM_SETS    = 64,

    parameter int WAY_INDEX_W = (ASSOC <= 1) ? 1 : $clog2(ASSOC),
    parameter int SET_INDEX_W = (NUM_SETS <= 1) ? 1 : $clog2(NUM_SETS)
)(
    input  logic clk,
    input  logic rst,

    // Victim lookup
    input  logic [SET_INDEX_W-1:0] lookup_set,
    input  logic [ASSOC-1:0]       valid_bits,
    output logic [WAY_INDEX_W-1:0] victim_way,

    // Replacement state update
    input  logic                   update_valid,
    input  logic [SET_INDEX_W-1:0] update_set,
    input  logic [WAY_INDEX_W-1:0] update_way
);

    generate
        if (ASSOC == 1) begin : GEN_DIRECT_MAPPED

            assign victim_way = '0;

        end else begin : GEN_TREE_PLRU

            localparam int PLRU_BITS = ASSOC - 1;
            localparam int LEVELS    = $clog2(ASSOC);

            logic [PLRU_BITS-1:0] plru_bits [NUM_SETS-1:0];
            logic [PLRU_BITS-1:0] curr_bits;
            logic [PLRU_BITS-1:0] next_bits;

            logic [WAY_INDEX_W-1:0] plru_victim_way;
            logic [WAY_INDEX_W-1:0] invalid_way;
            logic                   has_invalid;

            assign curr_bits = plru_bits[update_set];

            // ====================================================
            // First invalid way priority
            // ====================================================

            always_comb begin
                has_invalid = 1'b0;
                invalid_way = '0;

                for (int i = 0; i < ASSOC; i++) begin
                    if (!valid_bits[i] && !has_invalid) begin
                        has_invalid = 1'b1;
                        invalid_way = i[WAY_INDEX_W-1:0];
                    end
                end
            end

            // ====================================================
            // PLRU victim select
            // ====================================================

            always_comb begin
                int node;

                plru_victim_way = '0;
                node            = 0;

                for (int level = 0; level < LEVELS; level++) begin
                    if (plru_bits[lookup_set][node] == 1'b0) begin
                        plru_victim_way[LEVELS-1-level] = 1'b0;
                        node = (2 * node) + 1;
                    end
                    else begin
                        plru_victim_way[LEVELS-1-level] = 1'b1;
                        node = (2 * node) + 2;
                    end
                end
            end

            // ====================================================
            // Final victim select
            // ====================================================

            assign victim_way = has_invalid ? invalid_way : plru_victim_way;

            // ====================================================
            // PLRU update
            // On access, update bits along path to point away
            // from the accessed way.
            // ====================================================

            always_comb begin
                int node;

                next_bits = curr_bits;
                node      = 0;

                for (int level = 0; level < LEVELS; level++) begin
                    if (update_way[LEVELS-1-level] == 1'b0) begin
                        next_bits[node] = 1'b1;
                        node = (2 * node) + 1;
                    end
                    else begin
                        next_bits[node] = 1'b0;
                        node = (2 * node) + 2;
                    end
                end
            end

            // ====================================================
            // Replacement state array
            // ====================================================

            always_ff @(posedge clk) begin
                if (rst) begin
                    for (int i = 0; i < NUM_SETS; i++) begin
                        plru_bits[i] <= '0;
                    end
                end
                else if (update_valid) begin
                    plru_bits[update_set] <= next_bits;
                end
            end

        end
    endgenerate

endmodule