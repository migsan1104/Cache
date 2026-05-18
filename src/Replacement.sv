// ============================================================
// Tree-based pseudo-LRU replacement policy
// ASSOC = 1 returns way 0
// ASSOC > 1 uses ASSOC-1 PLRU bits per set
// Bits point toward the less-recently-used subtree
// ============================================================

module Replacement #(
    parameter int ASSOC    = 4,
    parameter int NUM_SETS = 64,

    parameter int WAY_W = (ASSOC <= 1) ? 1 : $clog2(ASSOC),
    parameter int SET_W = (NUM_SETS <= 1) ? 1 : $clog2(NUM_SETS)
)(
    input  logic clk,
    input  logic rst,

    // Update replacement state after a hit or after installing a fill
    input  logic             access_valid,
    input  logic [SET_W-1:0] access_set,
    input  logic [WAY_W-1:0] access_way,

    // Select victim for this set
    input  logic [SET_W-1:0] victim_set,
    output logic [WAY_W-1:0] victim_way
);

    // ============================================================
    // Direct mapped: no replacement state needed
    // ============================================================

    generate
        if (ASSOC == 1) begin : GEN_DIRECT_MAPPED

            assign victim_way = '0;

        end else begin : GEN_TREE_PLRU

            localparam int PLRU_BITS = ASSOC - 1;
            localparam int LEVELS    = $clog2(ASSOC);

            logic [PLRU_BITS-1:0] plru_bits [NUM_SETS-1:0];

            logic [PLRU_BITS-1:0] curr_bits;
            logic [PLRU_BITS-1:0] next_bits;

            assign curr_bits = plru_bits[access_set];

            // ====================================================
            // Victim select
            // Walk the tree using bits that point toward LRU side
            // ====================================================

            always_comb begin
                int node;

                victim_way = '0;
                node       = 0;

                for (int level = 0; level < LEVELS; level++) begin

                    if (plru_bits[victim_set][node] == 1'b0) begin
                        victim_way[LEVELS-1-level] = 1'b0;
                        node = (2 * node) + 1;
                    end else begin
                        victim_way[LEVELS-1-level] = 1'b1;
                        node = (2 * node) + 2;
                    end

                end
            end

            // ====================================================
            // PLRU update
            // On access, update bits along path to point away from accessed way
            // ====================================================

            always_comb begin
                int node;

                next_bits = curr_bits;
                node      = 0;

                for (int level = 0; level < LEVELS; level++) begin

                    if (access_way[LEVELS-1-level] == 1'b0) begin
                        next_bits[node] = 1'b1;
                        node = (2 * node) + 1;
                    end else begin
                        next_bits[node] = 1'b0;
                        node = (2 * node) + 2;
                    end

                end
            end

            // ====================================================
            // Replacement state array
            // Reset makes victim traversal initially prefer way 0
            // ====================================================

            always_ff @(posedge clk) begin
                if (rst) begin
                    for (int i = 0; i < NUM_SETS; i++) begin
                        plru_bits[i] <= '0;
                    end
                end else if (access_valid) begin
                    plru_bits[access_set] <= next_bits;
                end
            end

        end
    endgenerate

endmodule