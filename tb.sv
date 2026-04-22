`timescale 1ns/10ps

module tb_uart;

    localparam int CLK_PERIOD_NS = 100;
    localparam int CLKS_PER_BIT  = 87;

    // TB Signals using SV logic type instead of reg/wire
    logic       clk = 0;
    logic       tx_dv = 0;
    logic [7:0] tx_byte = 0;
    logic       tx_active;
    logic       tx_serial;
    logic       tx_done;

    logic       rx_dv;
    logic [7:0] rx_byte;

    // Clock generation
    always #(CLK_PERIOD_NS/2) clk = ~clk;

    // Instantiate your original Verilog TX module
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut_tx (
        .i_Clock(clk),
        .i_Tx_DV(tx_dv),
        .i_Tx_Byte(tx_byte),
        .o_Tx_Active(tx_active),
        .o_Tx_Serial(tx_serial),
        .o_Tx_Done(tx_done)
    );

    // Instantiate your original Verilog RX module
    // LOOPBACK CONFIGURATION: tx_serial is routed directly into i_Rx_Serial
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut_rx (
        .i_Clock(clk),
        .i_Rx_Serial(tx_serial), 
        .o_Rx_DV(rx_dv),
        .o_Rx_Byte(rx_byte)
    );

    // SV Scoreboard: A dynamic queue to hold expected data
    logic [7:0] expected_data[$];

    // Main Test Sequence (Stimulus Generator)
    initial begin
        logic [7:0] rand_data;
        
        $display("----------------------------------------");
        $display("Starting SV Verification of Original RTL");
        $display("----------------------------------------");

        // Wait for system to stabilize
        repeat(5) @(posedge clk);

        // Generate and send 10 randomized bytes
        for (int i = 0; i < 10; i++) begin
            rand_data = $urandom_range(0, 255);
            
            // Push expected data to the back of the scoreboard queue
            expected_data.push_back(rand_data); 

            // Drive the TX module
            @(posedge clk);
            tx_dv   <= 1'b1;
            tx_byte <= rand_data;
            
            @(posedge clk);
            tx_dv   <= 1'b0;

            $display("[%0t] DRIVER: Sent Byte 0x%0h", $time, rand_data);

            // Wait for the TX module to assert done
            @(posedge tx_done);
            
            // Allow a brief gap between transmissions
            repeat(10) @(posedge clk); 
        end
    end

    // Monitor and Checker (Self-Checking Logic)
    always_ff @(posedge clk) begin
        // Whenever RX says data is valid, check it against the scoreboard
        if (rx_dv) begin
            logic [7:0] exp_byte;
            
            if (expected_data.size() == 0) begin
                $error("[%0t] SCOREBOARD FAIL: Unexpected data received (0x%0h)", $time, rx_byte);
            end else begin
                // Pop the oldest expected data from the front of the queue
                exp_byte = expected_data.pop_front();
                
                if (rx_byte === exp_byte) begin
                    $display("[%0t] SCOREBOARD PASS: Expected 0x%0h, Received 0x%0h", $time, exp_byte, rx_byte);
                end else begin
                    $error("[%0t] SCOREBOARD FAIL: Expected 0x%0h, Got 0x%0h", $time, exp_byte, rx_byte);
                end
            end
            
            // End simulation gracefully when all expected data is verified
            if (expected_data.size() == 0) begin
                $display("----------------------------------------");
                $display("Verification Complete: All Bytes Matched");
                $display("----------------------------------------");
                $finish;
            end
        end
    end

    // VCD Dump for waveform analysis
    initial begin
        $dumpfile("uart_waves.vcd");
        $dumpvars(0, tb_uart);
    end

endmodule
