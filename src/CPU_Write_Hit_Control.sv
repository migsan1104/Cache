module CPU_Write_Hit_Control #(
    parameter int ASSOC         = 4,
    parameter int DATA_WIDTH    = 32,
    parameter int LINE_WIDTH    = 128,
    parameter int TAG_WIDTH     = 16,
    parameter int FLAG_BITS     = 4,
    parameter int WAY_INDEX_W   = 2,
    parameter int WORD_OFFSET_W = 2
)(
    input  logic                       valid,
    input  logic                       hit,
    input  logic                       write,
    input  logic [WAY_INDEX_W-1:0]     hit_way,
    input  logic [WORD_OFFSET_W-1:0]   word_id,
    input  logic [DATA_WIDTH-1:0]      wdata,
    input  logic [TAG_WIDTH-1:0]       tag,
    input  logic [LINE_WIDTH-1:0]      old_line [ASSOC],

    output logic [ASSOC-1:0]           data_wen,
    output logic [ASSOC-1:0]           tag_wen,
    output logic [ASSOC-1:0]           flag_wen,
    output logic [LINE_WIDTH-1:0]      data_wline [ASSOC],
    output logic [TAG_WIDTH-1:0]       tag_wdata  [ASSOC],
    output logic [FLAG_BITS-1:0]       flag_wdata [ASSOC]
);

    always_comb begin
        data_wen = '0;
        tag_wen  = '0;
        flag_wen = '0;

        for (int i = 0; i < ASSOC; i++) begin
            data_wline[i] = old_line[i];
            tag_wdata[i]  = tag;
            flag_wdata[i] = 4'b0011; // valid=1, dirty=1
        end

        if (valid && hit && write) begin
            data_wen[hit_way] = 1'b1;
            flag_wen[hit_way] = 1'b1;

            data_wline[hit_way] = old_line[hit_way];
            data_wline[hit_way][word_id * DATA_WIDTH +: DATA_WIDTH] = wdata;
        end
    end

endmodule