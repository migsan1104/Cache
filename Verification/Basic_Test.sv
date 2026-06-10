`timescale 1ns/1ps

module Basic_Test;

    localparam int ADDR_WIDTH       = 32;
    localparam int DATA_WIDTH       = 32;
    localparam int CPU_ID_WIDTH     = 3;
    localparam int MSHR_ID_WIDTH    = 2;

    localparam int CACHE_BYTES      = 1024;
    localparam int LINE_BYTES       = 16;
    localparam int ASSOC            = 4;

    localparam int RAM_DEPTH_WORDS  = 1024;
    localparam int RAM_READ_LATENCY = 20;

    localparam int NUM_REQS         = 10;

    localparam int EXPECTED_MEM_REQ_VALID_CYCLES = 30;
    localparam int EXPECTED_MEM_REQ_VALID_PULSES = 3;

    logic clk;
    logic rst;

    logic                    cpu_req_valid;
    logic                    cpu_req_write;
    logic [ADDR_WIDTH-1:0]   cpu_req_addr;
    logic [DATA_WIDTH-1:0]   cpu_req_wdata;
    logic [CPU_ID_WIDTH-1:0] cpu_req_id;
    logic                    cpu_req_ready;

    logic                    cpu_resp_valid;
    logic                    cpu_resp_ready;
    logic                    cpu_resp_hit;
    logic [DATA_WIDTH-1:0]   cpu_resp_rdata;
    logic [CPU_ID_WIDTH-1:0] cpu_resp_id;

    logic                     mem_req_valid;
    logic                     mem_req_ready;
    logic                     mem_req_write;
    logic [ADDR_WIDTH-1:0]    mem_req_addr;
    logic [DATA_WIDTH-1:0]    mem_req_wdata;
    logic [MSHR_ID_WIDTH-1:0] mem_req_id;

    logic                     mem_resp_valid;
    logic                     mem_resp_ready;
    logic [DATA_WIDTH-1:0]    mem_resp_rdata;
    logic [MSHR_ID_WIDTH-1:0] mem_resp_id;

    int cpu_resp_count [0:7];
    int total_cpu_responses;
    int expected_count [0:7];
    int cpu_id_seq [0:NUM_REQS-1];

    int mem_req_valid_cycles;
    int mem_req_valid_pulses;
    logic mem_req_valid_d;

    initial begin
        expected_count[0] = 2;
        expected_count[1] = 2;
        expected_count[2] = 1;
        expected_count[3] = 1;
        expected_count[4] = 1;
        expected_count[5] = 1;
        expected_count[6] = 1;
        expected_count[7] = 1;

        cpu_id_seq[0] = 0;
        cpu_id_seq[1] = 1;
        cpu_id_seq[2] = 2;
        cpu_id_seq[3] = 3;
        cpu_id_seq[4] = 4;
        cpu_id_seq[5] = 5;
        cpu_id_seq[6] = 6;
        cpu_id_seq[7] = 7;
        cpu_id_seq[8] = 0;
        cpu_id_seq[9] = 1;
    end

    initial begin
        clk = 1'b0;
    end

    always #5 clk = ~clk;

    Cache #(
        .ADDR_WIDTH    (ADDR_WIDTH),
        .DATA_WIDTH    (DATA_WIDTH),
        .CACHE_BYTES   (CACHE_BYTES),
        .LINE_BYTES    (LINE_BYTES),
        .ASSOC         (ASSOC),
        .CPU_ID_WIDTH  (CPU_ID_WIDTH),
        .MSHR_ID_WIDTH (MSHR_ID_WIDTH)
    ) DUT (
        .clk            (clk),
        .rst            (rst),

        .cpu_req_valid  (cpu_req_valid),
        .cpu_req_ready  (cpu_req_ready),
        .cpu_req_write  (cpu_req_write),
        .cpu_req_addr   (cpu_req_addr),
        .cpu_req_wdata  (cpu_req_wdata),
        .cpu_req_id     (cpu_req_id),

        .cpu_resp_valid (cpu_resp_valid),
        .cpu_resp_ready (cpu_resp_ready),
        .cpu_resp_hit   (cpu_resp_hit),
        .cpu_resp_rdata (cpu_resp_rdata),
        .cpu_resp_id    (cpu_resp_id),

        .mem_req_valid  (mem_req_valid),
        .mem_req_ready  (mem_req_ready),
        .mem_req_write  (mem_req_write),
        .mem_req_addr   (mem_req_addr),
        .mem_req_wdata  (mem_req_wdata),
        .mem_req_id     (mem_req_id),

        .mem_resp_valid (mem_resp_valid),
        .mem_resp_ready (mem_resp_ready),
        .mem_resp_id    (mem_resp_id),
        .mem_resp_rdata (mem_resp_rdata)
    );

    RAM_ID #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .D_WIDTH      (DATA_WIDTH),
        .DEPTH        (RAM_DEPTH_WORDS),
        .ID_WIDTH     (MSHR_ID_WIDTH),
        .READ_LATENCY (RAM_READ_LATENCY),
        .INIT_FILE    ("downstream_init.hex")
    ) MEM (
        .clk          (clk),
        .rst          (rst),

        .req_valid    (mem_req_valid),
        .req_ready    (mem_req_ready),
        .req_write    (mem_req_write),
        .req_addr     (mem_req_addr),
        .req_wdata    (mem_req_wdata),
        .req_id       (mem_req_id),

        .resp_valid   (mem_resp_valid),
        .resp_ready   (mem_resp_ready),
        .resp_rdata   (mem_resp_rdata),
        .resp_id      (mem_resp_id)
    );

    assign cpu_resp_ready = 1'b1;

    task automatic send_write_miss(
        input int word_addr,
        input logic [DATA_WIDTH-1:0] data,
        input logic [CPU_ID_WIDTH-1:0] id
    );
        begin
            @(posedge clk);

            while (!cpu_req_ready) begin
                cpu_req_valid <= 1'b0;
                cpu_req_write <= 1'b0;
                cpu_req_addr  <= '0;
                cpu_req_wdata <= '0;
                cpu_req_id    <= '0;
                @(posedge clk);
            end

            cpu_req_valid <= 1'b1;
            cpu_req_write <= 1'b1;
            cpu_req_addr  <= word_addr << 2;
            cpu_req_wdata <= data;
            cpu_req_id    <= id;

            @(posedge clk);

            cpu_req_valid <= 1'b0;
            cpu_req_write <= 1'b0;
            cpu_req_addr  <= '0;
            cpu_req_wdata <= '0;
            cpu_req_id    <= '0;
        end
    endtask

    always_ff @(posedge clk) begin
        if (rst) begin
            total_cpu_responses <= 0;

            for (int i = 0; i < 8; i++) begin
                cpu_resp_count[i] <= 0;
            end
        end else if (cpu_resp_valid && cpu_resp_ready) begin
            cpu_resp_count[cpu_resp_id] <= cpu_resp_count[cpu_resp_id] + 1;
            total_cpu_responses         <= total_cpu_responses + 1;

            $display("[%0t] CPU RESP: cpu_id=%0d count_now=%0d hit=%0b rdata=%h",
                     $time,
                     cpu_resp_id,
                     cpu_resp_count[cpu_resp_id] + 1,
                     cpu_resp_hit,
                     cpu_resp_rdata);
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            mem_req_valid_cycles <= 0;
            mem_req_valid_pulses <= 0;
            mem_req_valid_d      <= 1'b0;
        end else begin
            mem_req_valid_d <= mem_req_valid;

            if (mem_req_valid && mem_req_ready) begin
                mem_req_valid_cycles <= mem_req_valid_cycles + 1;

                $display("[%0t] CACHE IS SENDING: write=%0b addr=%h mshr_id=%0d wdata=%h",
                         $time,
                         mem_req_write,
                         mem_req_addr,
                         mem_req_id,
                         mem_req_wdata);
            end

            if (mem_req_valid && !mem_req_valid_d) begin
                mem_req_valid_pulses <= mem_req_valid_pulses + 1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst && mem_resp_valid && mem_resp_ready) begin
            $display("[%0t] MEM RESP: mshr_id=%0d rdata=%h",
                     $time,
                     mem_resp_id,
                     mem_resp_rdata);
        end
    end

    initial begin
        rst           <= 1'b1;
        cpu_req_valid <= 1'b0;
        cpu_req_write <= 1'b0;
        cpu_req_addr  <= '0;
        cpu_req_wdata <= '0;
        cpu_req_id    <= '0;

        repeat (5) @(posedge clk);
        rst <= 1'b0;
        repeat (2) @(posedge clk);

        for (int i = 0; i < NUM_REQS; i++) begin
            send_write_miss(
                2 + (i * 4),
                32'hA000_0000 + i,
                cpu_id_seq[i][CPU_ID_WIDTH-1:0]
            );
        end

        repeat (500) @(posedge clk);

        $display("==================================================");
        $display("Basic_Test Simulation Report");
        $display("Total CPU responses              = %0d", total_cpu_responses);
        $display("mem_req_valid accepted cycles    = %0d", mem_req_valid_cycles);
        $display("mem_req_valid pulse count        = %0d", mem_req_valid_pulses);
        $display("==================================================");

        for (int i = 0; i < 8; i++) begin
            if (cpu_resp_count[i] !== expected_count[i]) begin
                $error("CPU id %0d expected %0d responses, got %0d",
                       i,
                       expected_count[i],
                       cpu_resp_count[i]);
            end
        end

        if (total_cpu_responses !== NUM_REQS) begin
            $error("Expected %0d total CPU responses, got %0d",
                   NUM_REQS,
                   total_cpu_responses);
        end

        if (mem_req_valid_cycles !== EXPECTED_MEM_REQ_VALID_CYCLES) begin
            $error("Expected mem_req_valid for %0d accepted cycles, got %0d",
                   EXPECTED_MEM_REQ_VALID_CYCLES,
                   mem_req_valid_cycles);
        end

        if (mem_req_valid_pulses !== EXPECTED_MEM_REQ_VALID_PULSES) begin
            $error("Expected mem_req_valid to pulse %0d time(s), got %0d",
                   EXPECTED_MEM_REQ_VALID_PULSES,
                   mem_req_valid_pulses);
        end

        $display("Basic_Test complete.");
        $finish;
    end

endmodule