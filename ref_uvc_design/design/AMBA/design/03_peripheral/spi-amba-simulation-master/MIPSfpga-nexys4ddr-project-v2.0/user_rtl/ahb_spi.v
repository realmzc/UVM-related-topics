`timescale 100ps/1ps

module ahb_spi
(
    input               HCLK,
    input               HRESETn,
    input      [ 31: 0] HADDR,
    input      [ 31: 0] HWDATA,
    input               HWRITE,
    input               HSEL,
    output reg [ 31: 0] HRDATA,

    input               SPI_MISO,
    output              SPI_MOSI,
    output              SPI_SCLK,
    output reg          SPI_SS
);

    localparam START_REG_ADDR = 8'h0;
    localparam SS_REG_ADDR    = 8'h4;
    localparam READY_REG_ADDR = 8'h8;
    localparam DATA_REG_ADDR  = 8'h12;
    
    reg  [ 7:0] data_buf_w;
    wire [ 7:0] data_buf_r;
    reg         ss_flag;
    reg         start_flag;
    wire        ready_flag;
        
    spi_master_driver spi(
        .clk_i(HCLK),
        .rst_i(~HRESETn),
        
        .start_i(start_flag),
        .data_in_bi(data_buf_w),
        .busy_o(ready_flag),
        .data_out_bo(data_buf_r),
        
        .spi_miso_i(SPI_MISO),
        .spi_mosi_o(SPI_MOSI),
        .spi_sclk_o(SPI_SCLK),
        .spi_cs_i(ss_flag)
    );
    
    // AHB bus adapter
    reg  [ 11:0] HADDR_dly;
    reg          HWRITE_dly;
    reg          HSEL_dly;
    
    always @(posedge HCLK) begin
        HADDR_dly <= HADDR[11:0];
        HWRITE_dly <= HWRITE;
        HSEL_dly <= HSEL;
    end
    
    wire [ 11:0] reg_addr = HADDR_dly;

    always @(posedge HCLK or negedge HRESETn) begin
        if (~HRESETn) begin
            data_buf_w <= 8'b0;
            start_flag <= 1'b0;
            ss_flag    <= 1'b1;
        end
        else begin
            if (HSEL_dly) begin
                // Bus interface logic, write operation
                if (HWRITE_dly) begin
                    case (reg_addr)
                    DATA_REG_ADDR:  data_buf_w <= HWDATA[7:0];
                    START_REG_ADDR: start_flag <= HWDATA[0];
                    SS_REG_ADDR:    ss_flag    <= HWDATA[0];
                    default:; /* READY_REG_ADDR: do nothing */
                    endcase
                end
                // Reset start flag automatically after one tick
                if (!(HWRITE_dly && reg_addr == START_REG_ADDR)) begin
                    start_flag <= 1'b0;
                end
            end
        end
    end
    
    // Bus interface logic, data for read operation
    always @(*) begin
        SPI_SS = ss_flag;
        case (reg_addr)
            READY_REG_ADDR: HRDATA = ~ready_flag;
            DATA_REG_ADDR:  HRDATA = data_buf_r;
            default:        HRDATA = 32'b0;
        endcase
    end
    
endmodule
