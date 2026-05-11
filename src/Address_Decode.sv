module Address_Decode #(
    parameter int ADDR_WIDTH  = 32,
    parameter int TAG_BITS    = 20,
    parameter int INDEX_BITS  = 8,
    parameter int OFFSET_BITS = 4
)(
    input  logic [ADDR_WIDTH-1:0] addr,

    output logic [TAG_BITS-1:0]    tag,
    output logic [INDEX_BITS-1:0]  index,
    output logic [OFFSET_BITS-1:0] offset
);

    assign offset = addr[OFFSET_BITS-1:0];

    assign index = addr[
        OFFSET_BITS +: INDEX_BITS
    ];

    assign tag = addr[
        ADDR_WIDTH-1 -: TAG_BITS
    ];

endmodule