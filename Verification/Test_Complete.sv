`timescale 1ns/1ps

module Test_Complete;

    localparam int ADDR_WIDTH        = 32;
    localparam int DATA_WIDTH        = 32;
    localparam int MAX_TEST_REQUESTS = 1000;
    localparam int CPU_ID_WIDTH      = $clog2(MAX_TEST_REQUESTS);
    localparam int MSHR_ID_WIDTH     = 2;

    localparam int CACHE_BYTES       = 1024;
    localparam int LINE_BYTES        = 16;
    localparam int ASSOC             = 4;

    localparam int WORDS_PER_LINE    = LINE_BYTES / (DATA_WIDTH / 8);
    localparam int CACHE_LINES       = CACHE_BYTES / LINE_BYTES;

    localparam int RAM_DEPTH_WORDS   = 1024;
    localparam int RAM_READ_LATENCY  = 20;

    localparam string RAM_INIT_FILE  = "downstream_init.hex";

    localparam int TEST1_NUM_WRITES  = 200;
    localparam int TEST1_NUM_READS   = 200;

    localparam int TEST2_NUM_WRITES  = 200;
    localparam int TEST2_NUM_READS   = 200;

    localparam int TEST3_NUM_REQS    = 200;

    localparam int TEST4_NUM_READS1 = 100;
    localparam int TEST4_NUM_WRITES = 100;
    localparam int TEST4_NUM_READS2 = 100;

    localparam int TEST1 = 1;
    localparam int TEST2 = 2;
    localparam int TEST3 = 3;
    localparam int TEST4 = 4;

    localparam bit TEST1_PRINT_CPU_REQS   = 1'b0;
    localparam bit TEST1_PRINT_CPU_RESPS  = 1'b0;
    localparam bit TEST1_PRINT_MEM_REQS   = 1'b0;
    localparam bit TEST1_PRINT_MEM_RESPS  = 1'b0;
    localparam bit TEST1_PRINT_CHECKS     = 1'b0;
    localparam bit TEST1_PRINT_REPORT     = 1'b0;

    localparam bit TEST2_PRINT_CPU_REQS   = 1'b0;
    localparam bit TEST2_PRINT_CPU_RESPS  = 1'b0;
    localparam bit TEST2_PRINT_MEM_REQS   = 1'b0;
    localparam bit TEST2_PRINT_MEM_RESPS  = 1'b0;
    localparam bit TEST2_PRINT_CHECKS     = 1'b0;
    localparam bit TEST2_PRINT_REPORT     = 1'b0;

    localparam bit TEST3_PRINT_CPU_REQS   = 1'b0;
    localparam bit TEST3_PRINT_CPU_RESPS  = 1'b0;
    localparam bit TEST3_PRINT_MEM_REQS   = 1'b0;
    localparam bit TEST3_PRINT_MEM_RESPS  = 1'b0;
    localparam bit TEST3_PRINT_CHECKS     = 1'b1;
    localparam bit TEST3_PRINT_REPORT     = 1'b1;

    localparam bit TEST4_PRINT_CPU_REQS   = 1'b0;
    localparam bit TEST4_PRINT_CPU_RESPS  = 1'b0;
    localparam bit TEST4_PRINT_MEM_REQS   = 1'b0;
    localparam bit TEST4_PRINT_MEM_RESPS  = 1'b0;
    localparam bit TEST4_PRINT_CHECKS     = 1'b0;
    localparam bit TEST4_PRINT_REPORT     = 1'b0;

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

    logic in_read_phase;
    int   active_test;
    int   active_num_writes;
    int   active_num_reads;

    bit test1_pass;
    bit test2_pass;
    bit test3_pass;
    bit test4_pass;

    int test3_write_count;
    int test3_read_count;

    int total_cpu_requests_sent;
    int total_cpu_responses;
    int total_write_responses;
    int total_read_responses;

    int hit_count;
    int miss_count;
    int write_miss_count;
    int read_miss_count;

    int mem_req_valid_cycles;
    int mem_read_req_cycles;
    int mem_write_req_cycles;
    int mem_resp_count;

    int mem_req_valid_pulses;
    logic mem_req_valid_d;

    int write_phase_mem_write_req_cycles;
    int read_phase_mem_write_req_cycles;
    int write_phase_mem_read_req_cycles;
    int read_phase_mem_read_req_cycles;

    logic [DATA_WIDTH-1:0] golden_mem [0:RAM_DEPTH_WORDS-1];

    logic [DATA_WIDTH-1:0] expected_by_id       [0:MAX_TEST_REQUESTS-1];
    logic                  expected_valid_by_id [0:MAX_TEST_REQUESTS-1];
    logic                  read_done_by_id      [0:MAX_TEST_REQUESTS-1];
    int                    expected_addr_by_id  [0:MAX_TEST_REQUESTS-1];

    logic                  expected_is_read_by_id  [0:MAX_TEST_REQUESTS-1];
    logic                  expected_is_write_by_id [0:MAX_TEST_REQUESTS-1];

    int data_check_count;
    int data_error_count;
    int duplicate_resp_errors;
    int unexpected_resp_errors;
    int missing_resp_errors;

    int cpu_resp_count [0:MAX_TEST_REQUESTS-1];

    int expected_total_line_allocations;
    int expected_replacements_after_full;
    int expected_refill_transactions;

    initial begin
        clk = 1'b0;
        $readmemh(RAM_INIT_FILE, golden_mem);
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
        .INIT_FILE    (RAM_INIT_FILE)
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

    function automatic string test_name(input int test_id);
        begin
            if (test_id == TEST1)
                test_name = "Test1";
            else if (test_id == TEST2)
                test_name = "Test2";
            else if (test_id == TEST3)
                test_name = "Test3";
            else
                test_name = "Test4";
        end
    endfunction

    function automatic bit print_cpu_reqs(input int test_id);
        begin
            if (test_id == TEST1)
                print_cpu_reqs = TEST1_PRINT_CPU_REQS;
            else if (test_id == TEST2)
                print_cpu_reqs = TEST2_PRINT_CPU_REQS;
            else if (test_id == TEST3)
                print_cpu_reqs = TEST3_PRINT_CPU_REQS;
            else
                print_cpu_reqs = TEST4_PRINT_CPU_REQS;
        end
    endfunction

    function automatic bit print_cpu_resps(input int test_id);
        begin
            if (test_id == TEST1)
                print_cpu_resps = TEST1_PRINT_CPU_RESPS;
            else if (test_id == TEST2)
                print_cpu_resps = TEST2_PRINT_CPU_RESPS;
            else if (test_id == TEST3)
                print_cpu_resps = TEST3_PRINT_CPU_RESPS;
            else
                print_cpu_resps = TEST4_PRINT_CPU_RESPS;
        end
    endfunction

    function automatic bit print_mem_reqs(input int test_id);
        begin
            if (test_id == TEST1)
                print_mem_reqs = TEST1_PRINT_MEM_REQS;
            else if (test_id == TEST2)
                print_mem_reqs = TEST2_PRINT_MEM_REQS;
            else if (test_id == TEST3)
                print_mem_reqs = TEST3_PRINT_MEM_REQS;
            else
                print_mem_reqs = TEST4_PRINT_MEM_REQS;
        end
    endfunction

    function automatic bit print_mem_resps(input int test_id);
        begin
            if (test_id == TEST1)
                print_mem_resps = TEST1_PRINT_MEM_RESPS;
            else if (test_id == TEST2)
                print_mem_resps = TEST2_PRINT_MEM_RESPS;
            else if (test_id == TEST3)
                print_mem_resps = TEST3_PRINT_MEM_RESPS;
            else
                print_mem_resps = TEST4_PRINT_MEM_RESPS;
        end
    endfunction

    function automatic bit print_checks(input int test_id);
        begin
            if (test_id == TEST1)
                print_checks = TEST1_PRINT_CHECKS;
            else if (test_id == TEST2)
                print_checks = TEST2_PRINT_CHECKS;
            else if (test_id == TEST3)
                print_checks = TEST3_PRINT_CHECKS;
            else
                print_checks = TEST4_PRINT_CHECKS;
        end
    endfunction

    function automatic bit print_report_en(input int test_id);
        begin
            if (test_id == TEST1)
                print_report_en = TEST1_PRINT_REPORT;
            else if (test_id == TEST2)
                print_report_en = TEST2_PRINT_REPORT;
            else if (test_id == TEST3)
                print_report_en = TEST3_PRINT_REPORT;
            else
                print_report_en = TEST4_PRINT_REPORT;
        end
    endfunction

    // CPU address is WORD-addressed.
    // cpu_addr[1:0] is the word offset inside the 4-word line.
    function automatic [ADDR_WIDTH-1:0] make_addr(input int test_id, input int i);
        begin
            if ((test_id == TEST1) || (test_id == TEST4)) begin
                make_addr = ADDR_WIDTH'(i);
            end
            else begin
                // Test2 intentionally touches word offset 2 of each unique line:
                // word addresses 2, 6, 10, 14, ...
                make_addr = ADDR_WIDTH'((i * WORDS_PER_LINE) + 2);
            end
        end
    endfunction

    function automatic [DATA_WIDTH-1:0] make_wdata(input int test_id, input int i);
        begin
            if ((test_id == TEST1) || (test_id == TEST4))
                make_wdata = DATA_WIDTH'(i + 1);
            else
                make_wdata = DATA_WIDTH'(32'hA000_0000 + i);
        end
    endfunction

    task automatic drive_idle;
        begin
            cpu_req_valid <= 1'b0;
            cpu_req_write <= 1'b0;
            cpu_req_addr  <= '0;
            cpu_req_wdata <= '0;
            cpu_req_id    <= '0;
        end
    endtask

    task automatic reset_dut_and_scoreboard(input int test_id,
                                            input int num_writes,
                                            input int num_reads);
        begin
            active_test       <= test_id;
            active_num_writes <= num_writes;
            active_num_reads  <= num_reads;
            in_read_phase     <= 1'b0;
            missing_resp_errors = 0;

            $readmemh(RAM_INIT_FILE, golden_mem);

            drive_idle();

            rst <= 1'b1;
            repeat (5) @(posedge clk);
            rst <= 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic send_writes_back_to_back_base(input int test_id,
                                                 input int num_writes,
                                                 input int id_base);
        int i;
        begin
            i = 0;

            while (i < num_writes) begin
                cpu_req_valid <= 1'b1;
                cpu_req_write <= 1'b1;
                cpu_req_addr  <= make_addr(test_id, i);
                cpu_req_wdata <= make_wdata(test_id, i);
                cpu_req_id    <= CPU_ID_WIDTH'(id_base + i);

                @(posedge clk);

                if (cpu_req_ready)
                    i++;
            end

            drive_idle();
        end
    endtask

    task automatic send_writes_back_to_back(input int test_id,
                                            input int num_writes);
        begin
            send_writes_back_to_back_base(test_id, num_writes, 0);
        end
    endtask

    task automatic send_reads_back_to_back_base(input int test_id,
                                                input int num_reads,
                                                input int id_base);
        int i;
        begin
            i = 0;

            while (i < num_reads) begin
                cpu_req_valid <= 1'b1;
                cpu_req_write <= 1'b0;
                cpu_req_addr  <= make_addr(test_id, i);
                cpu_req_wdata <= '0;
                cpu_req_id    <= CPU_ID_WIDTH'(id_base + i);

                @(posedge clk);

                if (cpu_req_ready)
                    i++;
            end

            drive_idle();
        end
    endtask

    task automatic send_reads_back_to_back(input int test_id,
                                           input int num_writes,
                                           input int num_reads);
        begin
            send_reads_back_to_back_base(test_id, num_reads, num_writes);
        end
    endtask

    task automatic send_random_requests(input int num_reqs);
        int i;
        bit rand_write;
        int rand_word_addr;
        logic [DATA_WIDTH-1:0] rand_wdata;
        begin
            i = 0;
            test3_write_count = 0;
            test3_read_count  = 0;

            while (i < num_reqs) begin
                rand_write     = bit'($urandom_range(0, 1));
                rand_word_addr = $urandom_range(0, RAM_DEPTH_WORDS - 1);
                rand_wdata     = DATA_WIDTH'($urandom);

                cpu_req_valid <= 1'b1;
                cpu_req_write <= rand_write;
                cpu_req_addr  <= ADDR_WIDTH'(rand_word_addr);
                cpu_req_wdata <= rand_wdata;
                cpu_req_id    <= CPU_ID_WIDTH'(i);

                do begin
                    @(posedge clk);
                end while (!cpu_req_ready);

                if (rand_write)
                    test3_write_count++;
                else
                    test3_read_count++;

                i++;
            end

            drive_idle();
        end
    endtask

    task automatic wait_for_responses(input int expected_responses,
                                      input string name);
        int timeout_cycles;
        begin
            timeout_cycles = 0;

            while ((total_cpu_responses < expected_responses) &&
                   (timeout_cycles < 200000)) begin
                @(posedge clk);
                timeout_cycles++;
            end

            if (total_cpu_responses < expected_responses) begin
                $error("%s timed out waiting for responses. Expected=%0d got=%0d",
                       name,
                       expected_responses,
                       total_cpu_responses);
            end
        end
    endtask

    task automatic calculate_expected_mem_counts;
        begin
            expected_total_line_allocations = write_miss_count + read_miss_count;

            expected_replacements_after_full = expected_total_line_allocations - CACHE_LINES;
            if (expected_replacements_after_full < 0)
                expected_replacements_after_full = 0;

            expected_refill_transactions = (write_miss_count * (WORDS_PER_LINE - 1)) +
                                           (read_miss_count  * WORDS_PER_LINE);
        end
    endtask

    task automatic print_report(input int test_id);
        begin
            calculate_expected_mem_counts();

            if (print_report_en(test_id)) begin
                $display("==================================================");
                $display("%s Simulation Report", test_name(test_id));
                $display("Total CPU requests sent              = %0d", total_cpu_requests_sent);
                $display("Total CPU responses                  = %0d", total_cpu_responses);
                $display("Write responses                      = %0d", total_write_responses);
                $display("Read responses                       = %0d", total_read_responses);
                $display("CPU hit responses                    = %0d", hit_count);
                $display("CPU miss responses                   = %0d", miss_count);
                $display("Write miss responses                 = %0d", write_miss_count);
                $display("Read miss responses                  = %0d", read_miss_count);
                $display("Data checks performed                = %0d", data_check_count);
                $display("Data errors                          = %0d", data_error_count);
                $display("Duplicate response errors            = %0d", duplicate_resp_errors);
                $display("Unexpected response errors           = %0d", unexpected_resp_errors);
                $display("Missing response errors              = %0d", missing_resp_errors);
                $display("Cache lines                          = %0d", CACHE_LINES);
                $display("Words per line                       = %0d", WORDS_PER_LINE);
                $display("Expected line allocations            = %0d", expected_total_line_allocations);
                $display("Expected replacements after full     = %0d", expected_replacements_after_full);
                $display("Expected refill transactions         = %0d", expected_refill_transactions);
                $display("mem_req_valid accepted cycles        = %0d", mem_req_valid_cycles);
                $display("mem read request cycles              = %0d", mem_read_req_cycles);
                $display("mem writeback request cycles         = %0d", mem_write_req_cycles);
                $display("write-phase read request cycles      = %0d", write_phase_mem_read_req_cycles);
                $display("read-phase read request cycles       = %0d", read_phase_mem_read_req_cycles);
                $display("write-phase writeback cycles         = %0d", write_phase_mem_write_req_cycles);
                $display("read-phase writeback cycles          = %0d", read_phase_mem_write_req_cycles);
                $display("write-phase dirty evictions observed = %0d", write_phase_mem_write_req_cycles / WORDS_PER_LINE);
                $display("read-phase dirty evictions observed  = %0d", read_phase_mem_write_req_cycles / WORDS_PER_LINE);
                $display("total dirty evictions observed       = %0d", mem_write_req_cycles / WORDS_PER_LINE);
                $display("mem_resp_valid accepted cycles       = %0d", mem_resp_count);
                $display("mem_req_valid pulse count            = %0d", mem_req_valid_pulses);
                $display("==================================================");
            end
        end
    endtask

    task automatic check_results(input int test_id,
                                 input int num_writes,
                                 input int num_reads,
                                 output bit pass);
        int expected_total;
        begin
            expected_total = num_writes + num_reads;
            pass = 1'b1;
            missing_resp_errors = 0;

            if (expected_total > MAX_TEST_REQUESTS) begin
                pass = 1'b0;
                $error("%s has too many requests. Max=%0d requested=%0d",
                       test_name(test_id),
                       MAX_TEST_REQUESTS,
                       expected_total);
            end

            if (total_cpu_requests_sent !== expected_total) begin
                pass = 1'b0;
                $error("%s expected %0d CPU requests sent, got %0d",
                       test_name(test_id), expected_total, total_cpu_requests_sent);
            end

            if (total_cpu_responses !== expected_total) begin
                pass = 1'b0;
                $error("%s expected %0d total CPU responses, got %0d",
                       test_name(test_id), expected_total, total_cpu_responses);
            end

            if (total_write_responses !== num_writes) begin
                pass = 1'b0;
                $error("%s expected %0d write responses, got %0d",
                       test_name(test_id), num_writes, total_write_responses);
            end

            if (total_read_responses !== num_reads) begin
                pass = 1'b0;
                $error("%s expected %0d read responses, got %0d",
                       test_name(test_id), num_reads, total_read_responses);
            end

            if (data_check_count !== num_reads) begin
                pass = 1'b0;
                $error("%s expected %0d data checks, got %0d",
                       test_name(test_id), num_reads, data_check_count);
            end

            if (data_error_count !== 0) begin
                pass = 1'b0;
                $error("%s failed with %0d data mismatches",
                       test_name(test_id), data_error_count);
            end

            if (duplicate_resp_errors !== 0) begin
                pass = 1'b0;
                $error("%s failed with %0d duplicate response errors",
                       test_name(test_id), duplicate_resp_errors);
            end

            if (unexpected_resp_errors !== 0) begin
                pass = 1'b0;
                $error("%s failed with %0d unexpected response errors",
                       test_name(test_id), unexpected_resp_errors);
            end

            for (int i = 0; i < MAX_TEST_REQUESTS; i++) begin
                if (expected_is_read_by_id[i] &&
                    expected_valid_by_id[i] &&
                    !read_done_by_id[i]) begin
                    pass = 1'b0;
                    missing_resp_errors++;
                    $error("%s missing read response for id=%0d addr_word=%0d expected=%h",
                           test_name(test_id),
                           i,
                           expected_addr_by_id[i],
                           expected_by_id[i]);
                end
            end

            calculate_expected_mem_counts();

            if (mem_read_req_cycles !== expected_refill_transactions) begin
                pass = 1'b0;
                $error("%s expected %0d memory read/refill request cycles, got %0d",
                       test_name(test_id),
                       expected_refill_transactions,
                       mem_read_req_cycles);
            end

            if (mem_resp_count !== expected_refill_transactions) begin
                pass = 1'b0;
                $error("%s expected %0d mem responses, got %0d",
                       test_name(test_id),
                       expected_refill_transactions,
                       mem_resp_count);
            end
        end
    endtask

    task automatic run_one_test(input int test_id,
                                input int num_writes,
                                input int num_reads);
        bit pass;
        begin
            reset_dut_and_scoreboard(test_id, num_writes, num_reads);

            $display("==================================================");
            $display("Starting %s", test_name(test_id));

            if (test_id == TEST1) begin
                $display("Test1: sequential word addresses 0..%0d", num_writes - 1);
            end
            else if (test_id == TEST2) begin
                $display("Test2: overflow cache with %0d unique lines", num_writes);
                $display("Test2: accesses word offset 2 of each line: word addresses 2, 6, 10, ...");
            end

            $display("==================================================");

            in_read_phase <= 1'b0;
            $display("%s: Starting %0d back-to-back writes", test_name(test_id), num_writes);
            send_writes_back_to_back(test_id, num_writes);

            wait_for_responses(num_writes, test_name(test_id));
            repeat (10) @(posedge clk);

            in_read_phase <= 1'b1;
            $display("%s: Starting %0d back-to-back reads", test_name(test_id), num_reads);
            send_reads_back_to_back(test_id, num_writes, num_reads);

            wait_for_responses(num_writes + num_reads, test_name(test_id));
            repeat (300) @(posedge clk);

            check_results(test_id, num_writes, num_reads, pass);
            print_report(test_id);

            if (test_id == TEST1)
                test1_pass = pass;
            else if (test_id == TEST2)
                test2_pass = pass;

            if (pass)
                $display("%s PASSED: all %0d reads returned correct data.", test_name(test_id), num_reads);
            else
                $display("%s FAILED.", test_name(test_id));

            $display("%s complete.", test_name(test_id));
            $display("==================================================");
            repeat (20) @(posedge clk);
        end
    endtask

    task automatic run_test3(input int num_reqs);
        bit pass;
        begin
            reset_dut_and_scoreboard(TEST3, 0, 0);

            $display("==================================================");
            $display("Starting Test3");
            $display("Test3: %0d random mixed read/write requests", num_reqs);
            $display("==================================================");

            in_read_phase <= 1'b0;
            send_random_requests(num_reqs);

            wait_for_responses(num_reqs, "Test3");
            repeat (300) @(posedge clk);

            check_results(TEST3, test3_write_count, test3_read_count, pass);
            print_report(TEST3);

            test3_pass = pass;

            if (pass)
                $display("Test3 PASSED: all %0d reads returned correct data.", test3_read_count);
            else
                $display("Test3 FAILED.");

            $display("Test3 complete.");
            $display("==================================================");
            repeat (20) @(posedge clk);
        end
    endtask

    task automatic run_test4(input int num_reads1,
                             input int num_writes,
                             input int num_reads2);
        bit pass;
        int expected_total;
        begin
            expected_total = num_reads1 + num_writes + num_reads2;

            reset_dut_and_scoreboard(TEST4, num_writes, num_reads1 + num_reads2);

            $display("==================================================");
            $display("Starting Test4");
            $display("Test4: read addresses first, then write same addresses, then read again");
            $display("Test4: sequential word addresses 0..%0d", num_writes - 1);
            $display("==================================================");

            in_read_phase <= 1'b1;
            $display("Test4: Starting first %0d reads", num_reads1);
            send_reads_back_to_back_base(TEST4, num_reads1, 0);

            wait_for_responses(num_reads1, "Test4 first reads");
            repeat (10) @(posedge clk);

            in_read_phase <= 1'b0;
            $display("Test4: Starting %0d writes", num_writes);
            send_writes_back_to_back_base(TEST4, num_writes, num_reads1);

            wait_for_responses(num_reads1 + num_writes, "Test4 writes");
            repeat (10) @(posedge clk);

            in_read_phase <= 1'b1;
            $display("Test4: Starting second %0d reads", num_reads2);
            send_reads_back_to_back_base(TEST4, num_reads2, num_reads1 + num_writes);

            wait_for_responses(expected_total, "Test4 second reads");
            repeat (300) @(posedge clk);

            check_results(TEST4, num_writes, num_reads1 + num_reads2, pass);
            print_report(TEST4);

            test4_pass = pass;

            if (pass)
                $display("Test4 PASSED: first reads returned old data and second reads returned written data.");
            else
                $display("Test4 FAILED.");

            $display("Test4 complete.");
            $display("==================================================");
            repeat (20) @(posedge clk);
        end
    endtask

    always_ff @(posedge clk) begin
        if (rst) begin
            total_cpu_requests_sent <= 0;

            for (int i = 0; i < MAX_TEST_REQUESTS; i++) begin
                expected_by_id[i]          <= '0;
                expected_valid_by_id[i]    <= 1'b0;
                expected_addr_by_id[i]     <= 0;
                expected_is_read_by_id[i]  <= 1'b0;
                expected_is_write_by_id[i] <= 1'b0;
            end
        end
        else if (cpu_req_valid && cpu_req_ready) begin
            total_cpu_requests_sent <= total_cpu_requests_sent + 1;

            if (cpu_req_write) begin
                golden_mem[cpu_req_addr] <= cpu_req_wdata;

                expected_is_write_by_id[cpu_req_id] <= 1'b1;
                expected_is_read_by_id[cpu_req_id]  <= 1'b0;
            end
            else begin
                expected_by_id[cpu_req_id]       <= golden_mem[cpu_req_addr];
                expected_valid_by_id[cpu_req_id] <= 1'b1;
                expected_addr_by_id[cpu_req_id]  <= int'(cpu_req_addr);

                expected_is_read_by_id[cpu_req_id]  <= 1'b1;
                expected_is_write_by_id[cpu_req_id] <= 1'b0;
            end

            if (print_cpu_reqs(active_test)) begin
                $display("[%0t] CPU_REQ_SEND: test=%s phase=%s write=%0b addr=%h word_addr=%0d wdata=%h cpu_id=%0d total_now=%0d",
                         $time,
                         test_name(active_test),
                         (active_test == TEST3) ? "MIXED_PHASE" : (in_read_phase ? "READ_PHASE" : "WRITE_PHASE"),
                         cpu_req_write,
                         cpu_req_addr,
                         cpu_req_addr,
                         cpu_req_wdata,
                         cpu_req_id,
                         total_cpu_requests_sent + 1);
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            total_cpu_responses    <= 0;
            total_write_responses  <= 0;
            total_read_responses   <= 0;
            hit_count              <= 0;
            miss_count             <= 0;
            write_miss_count       <= 0;
            read_miss_count        <= 0;
            data_check_count       <= 0;
            data_error_count       <= 0;
            duplicate_resp_errors  <= 0;
            unexpected_resp_errors <= 0;

            for (int i = 0; i < MAX_TEST_REQUESTS; i++) begin
                cpu_resp_count[i] <= 0;
                read_done_by_id[i] <= 1'b0;
            end
        end
        else if (cpu_resp_valid && cpu_resp_ready) begin
            total_cpu_responses <= total_cpu_responses + 1;
            cpu_resp_count[cpu_resp_id] <= cpu_resp_count[cpu_resp_id] + 1;

            if (cpu_resp_count[cpu_resp_id] != 0) begin
                duplicate_resp_errors <= duplicate_resp_errors + 1;
                $error("DUPLICATE CPU RESPONSE: test=%s id=%0d count_before=%0d",
                       test_name(active_test),
                       cpu_resp_id,
                       cpu_resp_count[cpu_resp_id]);
            end

            if (cpu_resp_hit)
                hit_count <= hit_count + 1;
            else
                miss_count <= miss_count + 1;

            if (print_cpu_resps(active_test)) begin
                $display("[%0t] CPU_RESP: test=%s phase=%s id=%0d hit=%0b rdata=%h total_now=%0d",
                         $time,
                         test_name(active_test),
                         (active_test == TEST3) ? "MIXED_PHASE" : (in_read_phase ? "READ_PHASE" : "WRITE_PHASE"),
                         cpu_resp_id,
                         cpu_resp_hit,
                         cpu_resp_rdata,
                         total_cpu_responses + 1);
            end

            if (expected_is_read_by_id[cpu_resp_id]) begin
                total_read_responses <= total_read_responses + 1;

                if (!cpu_resp_hit)
                    read_miss_count <= read_miss_count + 1;

                if (!expected_valid_by_id[cpu_resp_id] || read_done_by_id[cpu_resp_id]) begin
                    unexpected_resp_errors <= unexpected_resp_errors + 1;
                    $error("UNEXPECTED READ RESPONSE: test=%s id=%0d rdata=%h expected_valid=%0b read_done=%0b",
                           test_name(active_test),
                           cpu_resp_id,
                           cpu_resp_rdata,
                           expected_valid_by_id[cpu_resp_id],
                           read_done_by_id[cpu_resp_id]);
                end
                else begin
                    data_check_count <= data_check_count + 1;

                    if (cpu_resp_rdata !== expected_by_id[cpu_resp_id]) begin
                        data_error_count <= data_error_count + 1;
                        $error("DATA MISMATCH: test=%s id=%0d addr_word=%0d expected=%h got=%h hit=%0b",
                               test_name(active_test),
                               cpu_resp_id,
                               expected_addr_by_id[cpu_resp_id],
                               expected_by_id[cpu_resp_id],
                               cpu_resp_rdata,
                               cpu_resp_hit);
                    end
                    else if (print_checks(active_test)) begin
                        $display("[%0t] DATA CHECK PASS: test=%s id=%0d addr_word=%0d expected=%h got=%h hit=%0b",
                                 $time,
                                 test_name(active_test),
                                 cpu_resp_id,
                                 expected_addr_by_id[cpu_resp_id],
                                 expected_by_id[cpu_resp_id],
                                 cpu_resp_rdata,
                                 cpu_resp_hit);
                    end

                    read_done_by_id[cpu_resp_id] <= 1'b1;
                end
            end
            else if (expected_is_write_by_id[cpu_resp_id]) begin
                total_write_responses <= total_write_responses + 1;

                if (!cpu_resp_hit)
                    write_miss_count <= write_miss_count + 1;
            end
            else begin
                unexpected_resp_errors <= unexpected_resp_errors + 1;
                $error("UNEXPECTED CPU RESPONSE: test=%s id=%0d hit=%0b rdata=%h",
                       test_name(active_test),
                       cpu_resp_id,
                       cpu_resp_hit,
                       cpu_resp_rdata);
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            mem_req_valid_cycles             <= 0;
            mem_read_req_cycles              <= 0;
            mem_write_req_cycles             <= 0;
            write_phase_mem_write_req_cycles <= 0;
            read_phase_mem_write_req_cycles  <= 0;
            write_phase_mem_read_req_cycles  <= 0;
            read_phase_mem_read_req_cycles   <= 0;
            mem_req_valid_pulses             <= 0;
            mem_req_valid_d                  <= 1'b0;
        end
        else begin
            mem_req_valid_d <= mem_req_valid;

            if (mem_req_valid && mem_req_ready) begin
                mem_req_valid_cycles <= mem_req_valid_cycles + 1;

                if (print_mem_reqs(active_test)) begin
                    $display("[%0t] MEM_REQ: test=%s phase=%s write=%0b addr=%h word_addr=%0d wdata=%h mshr_id=%0d count_now=%0d",
                             $time,
                             test_name(active_test),
                             (active_test == TEST3) ? "MIXED_PHASE" : (in_read_phase ? "READ_PHASE" : "WRITE_PHASE"),
                             mem_req_write,
                             mem_req_addr,
                             mem_req_addr,
                             mem_req_wdata,
                             mem_req_id,
                             mem_req_valid_cycles + 1);
                end

                if (mem_req_write) begin
                    mem_write_req_cycles <= mem_write_req_cycles + 1;

                    if (in_read_phase)
                        read_phase_mem_write_req_cycles <= read_phase_mem_write_req_cycles + 1;
                    else
                        write_phase_mem_write_req_cycles <= write_phase_mem_write_req_cycles + 1;
                end
                else begin
                    mem_read_req_cycles <= mem_read_req_cycles + 1;

                    if (in_read_phase)
                        read_phase_mem_read_req_cycles <= read_phase_mem_read_req_cycles + 1;
                    else
                        write_phase_mem_read_req_cycles <= write_phase_mem_read_req_cycles + 1;
                end
            end

            if (mem_req_valid && !mem_req_valid_d)
                mem_req_valid_pulses <= mem_req_valid_pulses + 1;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            mem_resp_count <= 0;
        end
        else if (mem_resp_valid && mem_resp_ready) begin
            mem_resp_count <= mem_resp_count + 1;

            if (print_mem_resps(active_test)) begin
                $display("[%0t] MEM_RESP: test=%s phase=%s rdata=%h mshr_id=%0d count_now=%0d",
                         $time,
                         test_name(active_test),
                         (active_test == TEST3) ? "MIXED_PHASE" : (in_read_phase ? "READ_PHASE" : "WRITE_PHASE"),
                         mem_resp_rdata,
                         mem_resp_id,
                         mem_resp_count + 1);
            end
        end
    end

    initial begin
        rst               <= 1'b1;
        active_test       <= TEST1;
        active_num_writes <= TEST1_NUM_WRITES;
        active_num_reads  <= TEST1_NUM_READS;
        in_read_phase     <= 1'b0;
        missing_resp_errors = 0;

        test1_pass = 1'b0;
        test2_pass = 1'b0;
        test3_pass = 1'b0;
        test4_pass = 1'b0;

        drive_idle();

        run_one_test(TEST1, TEST1_NUM_WRITES, TEST1_NUM_READS);
        run_one_test(TEST2, TEST2_NUM_WRITES, TEST2_NUM_READS);
        run_test3(TEST3_NUM_REQS);
        run_test4(TEST4_NUM_READS1, TEST4_NUM_WRITES, TEST4_NUM_READS2);

        $display("==================================================");
        $display("FINAL TEST SUMMARY");
        $display("Test1 %s", test1_pass ? "PASSED" : "FAILED");
        $display("Test2 %s", test2_pass ? "PASSED" : "FAILED");
        $display("Test3 %s", test3_pass ? "PASSED" : "FAILED");
        $display("Test4 %s", test4_pass ? "PASSED" : "FAILED");

        if (test1_pass && test2_pass && test3_pass && test4_pass)
            $display("Congrats all tests passed");
        else
            $display("One or more tests failed");

        $display("==================================================");

        repeat (20000) @(posedge clk);
        $finish;
    end

endmodule