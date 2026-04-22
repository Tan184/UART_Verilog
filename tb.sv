// ---------------------------------------------------------------------------
// UART Receiver (SystemVerilog)
// ---------------------------------------------------------------------------
module uart_rx #(
    parameter int CLKS_PER_BIT = 87
) (
    input  logic       i_Clock,
    input  logic       i_Rx_Serial,
    output logic       o_Rx_DV,
    output logic [7:0] o_Rx_Byte
);

    // SV Strongly Typed Enum for State Machine
    typedef enum logic [2:0] {
        IDLE,
        RX_START,
        RX_DATA,
        RX_STOP,
        CLEANUP
    } state_t;

    state_t r_SM_Main = IDLE;

    logic       r_Rx_Data_R = 1'b1;
    logic       r_Rx_Data   = 1'b1;
    int         r_Clock_Count = 0;
    logic [2:0] r_Bit_Index   = 0; 
    logic [7:0] r_Rx_Byte     = 0;
    logic       r_Rx_DV       = 0;

    // 2-Stage Synchronizer to prevent metastability
    always_ff @(posedge i_Clock) begin
        r_Rx_Data_R <= i_Rx_Serial;
        r_Rx_Data   <= r_Rx_Data_R;
    end

    // RX State Machine
    always_ff @(posedge i_Clock) begin
        case (r_SM_Main)
            IDLE: begin
                r_Rx_DV       <= 1'b0;
                r_Clock_Count <= 0;
                r_Bit_Index   <= 0;
                
                if (r_Rx_Data == 1'b0) r_SM_Main <= RX_START;
                else                   r_SM_Main <= IDLE;
            end
            
            RX_START: begin
                if (r_Clock_Count == (CLKS_PER_BIT-1)/2) begin
                    if (r_Rx_Data == 1'b0) begin
                        r_Clock_Count <= 0; 
                        r_SM_Main     <= RX_DATA;
                    end else begin
                        r_SM_Main <= IDLE;
                    end
                end else begin
                    r_Clock_Count <= r_Clock_Count + 1;
                    r_SM_Main     <= RX_START;
                end
            end
            
            RX_DATA: begin
                if (r_Clock_Count < CLKS_PER_BIT-1) begin
                    r_Clock_Count <= r_Clock_Count + 1;
                    r_SM_Main     <= RX_DATA;
                end else begin
                    r_Clock_Count          <= 0;
                    r_Rx_Byte[r_Bit_Index] <= r_Rx_Data;
                    
                    if (r_Bit_Index < 7) begin
                        r_Bit_Index <= r_Bit_Index + 1;
                        r_SM_Main   <= RX_DATA;
                    end else begin
                        r_Bit_Index <= 0;
                        r_SM_Main   <= RX_STOP;
                    end
                end
            end
            
            RX_STOP: begin
                if (r_Clock_Count < CLKS_PER_BIT-1) begin
                    r_Clock_Count <= r_Clock_Count + 1;
                    r_SM_Main     <= RX_STOP;
                end else begin
                    r_Rx_DV       <= 1'b1;
                    r_Clock_Count <= 0;
                    r_SM_Main     <= CLEANUP;
                end
            end
            
            CLEANUP: begin
                r_SM_Main <= IDLE;
                r_Rx_DV   <= 1'b0;
            end
            
            default: r_SM_Main <= IDLE;
        endcase
    end

    assign o_Rx_DV   = r_Rx_DV;
    assign o_Rx_Byte = r_Rx_Byte;

endmodule

// ---------------------------------------------------------------------------
// UART Transmitter (SystemVerilog)
// ---------------------------------------------------------------------------
module uart_tx #(
    parameter int CLKS_PER_BIT = 87
) (
    input  logic       i_Clock,
    input  logic       i_Tx_DV,
    input  logic [7:0] i_Tx_Byte, 
    output logic       o_Tx_Active,
    output logic       o_Tx_Serial,
    output logic       o_Tx_Done
);

    typedef enum logic [2:0] {
        IDLE,
        TX_START,
        TX_DATA,
        TX_STOP,
        CLEANUP
    } state_t;

    state_t r_SM_Main = IDLE;

    int         r_Clock_Count = 0;
    logic [2:0] r_Bit_Index   = 0;
    logic [7:0] r_Tx_Data     = 0;
    logic       r_Tx_Done     = 0;
    logic       r_Tx_Active   = 0;

    always_ff @(posedge i_Clock) begin
        case (r_SM_Main)
            IDLE: begin
                o_Tx_Serial   <= 1'b1;
                r_Tx_Done     <= 1'b0;
                r_Clock_Count <= 0;
                r_Bit_Index   <= 0;
                
                if (i_Tx_DV == 1'b1) begin
                    r_Tx_Active <= 1'b1;
                    r_Tx_Data   <= i_Tx_Byte;
                    r_SM_Main   <= TX_START;
                end else begin
                    r_SM_Main <= IDLE;
                end
            end
            
            TX_START: begin
                o_Tx_Serial <= 1'b0;
                if (r_Clock_Count < CLKS_PER_BIT-1) begin
                    r_Clock_Count <= r_Clock_Count + 1;
                    r_SM_Main     <= TX_START;
                end else begin
                    r_Clock_Count <= 0;
                    r_SM_Main     <= TX_DATA;
                end
            end
            
            TX_DATA: begin
                o_Tx_Serial <= r_Tx_Data[r_Bit_Index];
                if (r_Clock_Count < CLKS_PER_BIT-1) begin
                    r_Clock_Count <= r_Clock_Count + 1;
                    r_SM_Main     <= TX_DATA;
                end else begin
                    r_Clock_Count <= 0;
                    if (r_Bit_Index < 7) begin
                        r_Bit_Index <= r_Bit_Index + 1;
                        r_SM_Main   <= TX_DATA;
                    end else begin
                        r_Bit_Index <= 0;
                        r_SM_Main   <= TX_STOP;
                    end
                end
            end
            
            TX_STOP: begin
                o_Tx_Serial <= 1'b1;
                if (r_Clock_Count < CLKS_PER_BIT-1) begin
                    r_Clock_Count <= r_Clock_Count + 1;
                    r_SM_Main     <= TX_STOP;
                end else begin
                    r_Tx_Done     <= 1'b1;
                    r_Clock_Count <= 0;
                    r_SM_Main     <= CLEANUP;
                    r_Tx_Active   <= 1'b0;
                end
            end
            
            CLEANUP: begin
                r_Tx_Done <= 1'b1;
                r_SM_Main <= IDLE;
            end
            
            default: r_SM_Main <= IDLE;
        endcase
    end

    assign o_Tx_Active = r_Tx_Active;
    assign o_Tx_Done   = r_Tx_Done;

endmodule
