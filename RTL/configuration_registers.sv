import UART_pkg::*;
import registers_pkg::*;

module configuration_registers (
  input  logic        clk_i,    
  input  logic        rst_n_i,  
  input  logic        read_i,   
  input  logic        write_i,  
  input  logic [2:0]  address_i,
  inout  logic [7:0]  data_io,  
  input  logic        STR_en_i,

  /* STR */
  input  logic [1:0]  data_width_i,
  input  logic [1:0]  parity_mode_i,
  input  logic [1:0]  stop_bits_i,

  output logic        tx_dsm_o,
  output logic        rx_dsm_o,
  output logic [1:0]  data_width_o,
  output logic [1:0]  parity_mode_o,
  output logic [1:0]  stop_bits_o,

  /* DVR */
  output logic [15:0] divisor_o,

  /* FSR */
  input  logic        tx_fifo_full_i,
  input  logic        rx_fifo_empty_i,

  output logic [5:0]  rx_fifo_threshold_o,

  /* CTR */
  input  logic        config_done_i,

  output logic [1:0]  communication_mode_o,
  output logic        enable_config_o,
  output logic        ack_request_o,
  output logic        set_std_config_o,
  output logic        send_config_req_o,

  /* ISR */
  input  logic [2:0]  interrupt_id_i,
  input  logic        interrupt_id_en_i,

  output logic        rx_rdy_en_o,
  output logic        frame_error_en_o,
  output logic        parity_error_en_o,
  output logic        overrun_error_en_o,
  output logic        int_ackn_o,

  /* RXR */
  input  logic [7:0]  rx_data_i,
  output logic        rx_fifo_read_o,

  /* TXR */
  output logic [7:0]  tx_data_o,
  output logic        tx_fifo_write_o
); 

  /* Enable writing into registers */
  reg_enable_t enable;

  logic enable_config_req;

//----------------//
//  STR REGISTER  //
//----------------//

  STR_data_t STR_data;

      always_ff @(posedge clk_i) begin : STR_WR
        if (!rst_n_i) begin 
          STR_data <= {2'b0, STD_CONFIGURATION};
        /* The controller is writing */
        end else if (STR_en_i & enable_config_req) begin 
          STR_data.DWID <= data_width_i;
          STR_data.PMID <= parity_mode_i;
          STR_data.SBID <= stop_bits_i;
        /* The CPU is writing */
        end else if (enable.STR) begin 
          STR_data <= data_io;
        end
      end : STR_WR

  assign tx_dsm_o = STR_data.TDSM;
  assign rx_dsm_o = STR_data.RDSM;
  assign data_width_o = STR_data.DWID;
  assign parity_mode_o = STR_data.PMID;
  assign stop_bits_o = STR_data.SBID;


  logic change_config;
  assign change_config = ((STR_data.DWID != data_io[1:0]) | (STR_data.PMID != data_io[3:2]) | (STR_data.SBID != data_io[5:4]));

  assign send_config_req_o = change_config & (address_i == STR_ADDR) & write_i;


//----------------//
//  DVR REGISTER  //
//----------------//

  localparam LOWER = 0;
  localparam UPPER = 1;

  logic [UPPER:LOWER][7:0] DVR_data;

      always_ff @(posedge clk_i) begin : DVR_WR
        if (!rst_n_i) begin 
          DVR_data <= STD_DIVISOR;
        end else if (enable.LDVR) begin 
          DVR_data[LOWER] <= data_io;
        end else if (enable.UDVR) begin 
          DVR_data[UPPER] <= data_io;
        end
      end : DVR_WR

  assign divisor_o = DVR_data;


//----------------//
//  FSR REGISTER  //
//----------------//

  FSR_data_t FSR_data;

      always_ff @(posedge clk_i) begin : FSR_WR
        if (!rst_n_i) begin 
          FSR_data.RX_TRESHOLD <= 6'b0;
        end else if (enable.FSR) begin 
          FSR_data.RX_TRESHOLD <= data_io[5:0];
        end  
      end : FSR_WR

      always_ff @(posedge clk_i) begin : FSR_R
        if (!rst_n_i) begin
          FSR_data.TXF <= 1'b0;
          FSR_data.RXE <= 1'b1;
        end else begin 
          FSR_data.TXF <= tx_fifo_full_i;
          FSR_data.RXE <= rx_fifo_empty_i;
        end
      end : FSR_R

  assign rx_fifo_threshold_o = FSR_data.RX_TRESHOLD;


//----------------//
//  CTR REGISTER  //
//----------------//

  CTR_data_t CTR_data;

  logic akn_request, set_std_config, send_config_req;

      always_ff @(posedge clk_i) begin : CTR_WR
        if (!rst_n_i) begin 
          CTR_data.RESERVED <= 1'b0;
          CTR_data.COM   <= STD_COMM_MODE;
          CTR_data.ENREQ <= 1'b1;
          CTR_data.AKREQ <= 1'b0;
          CTR_data.STDC  <= 1'b0;
        end else if (enable.CTR) begin 
          CTR_data.COM   <= data_io[5:4];
          CTR_data.ENREQ <= data_io[3];
          CTR_data.AKREQ <= data_io[1];
          CTR_data.STDC  <= data_io[0];
        end 
      end : CTR_WR

      always_ff @(posedge clk_i) begin : CTR_R
        if (!rst_n_i) begin 
          CTR_data.CDONE <= 1'b1;
        end else begin 
          CTR_data.CDONE <= config_done_i;
        end
      end : CTR_R

  assign enable_config_req = CTR_data.ENREQ;

      always_comb begin 
        if (CTR_data.AKREQ) begin 
          akn_request = 1'b0;
        end

        if (CTR_data.STDC) begin 
          set_std_config = 1'b0;
        end
      end

  assign communication_mode_o = CTR_data.COM;
  assign enable_config_o = enable_config_req;
  assign ack_request_o = CTR_data.AKREQ;
  assign set_std_config_o = CTR_data.STDC;


//----------------//
//  ISR REGISTER  //
//----------------//

  ISR_data_t ISR_data;

      always_ff @(posedge clk_i) begin : ISR_WR
        if (!rst_n_i) begin 
          ISR_data.RXRDY <= 1'b1;
          ISR_data.FRM   <= 1'b1;
          ISR_data.PAR   <= 1'b1;
          ISR_data.OVR   <= 1'b1;
          ISR_data.IACK  <= 1'b0;
        end else if (enable.ISR) begin 
          ISR_data.RXRDY <= data_io[7];
          ISR_data.FRM   <= data_io[6];
          ISR_data.PAR   <= data_io[5];
          ISR_data.OVR   <= data_io[4];
          ISR_data.IACK  <= data_io[0];
        end
      end : ISR_WR

      always_ff @(posedge clk_i) begin : ISR_R
        if (!rst_n_i) begin 
          ISR_data.INTID <= 3'b0;
        end else if (interrupt_id_en_i) begin 
          ISR_data.INTID <= interrupt_id_i;
        end
      end : ISR_R

  assign int_ackn_o = ISR_data.IACK;
  assign overrun_error_en_o = ISR_data.OVR;
  assign parity_error_en_o = ISR_data.PAR;
  assign frame_error_en_o = ISR_data.FRM;
  assign rx_rdy_en_o = ISR_data.RXRDY;

//----------------//
//  RXR REGISTER  //
//----------------//

  logic [7:0] RXR_data;

      always_ff @(posedge clk_i) begin : RXR_WR
        if (!rst_n_i) begin
          RXR_data <= 8'b0;
        end else begin
          RXR_data <= rx_data_i;
        end
      end : RXR_WR

  /* Should be high for 1 clock cycle */
  assign rx_fifo_read_o = (read_i & (address_i == RXR_ADDR));


//----------------//
//  TXR REGISTER  //
//----------------//

  logic [7:0] TXR_data;

      always_ff @(posedge clk_i) begin 
        if (!rst_n_i) begin
          TXR_data <= 8'b0;
        end else if (enable.TXR) begin
          TXR_data <= data_io;
        end
      end

  assign tx_data_o = TXR_data;
  assign tx_fifo_write_o = (write_i & (address_i == TXR_ADDR));


//-----------//
//  DECODER  //
//-----------//
  
  /* Data stored into the registers */
  logic [7:0] data;

      always_comb begin : decoder
        enable = 8'b0;
        data = 8'b0;

        if (write_i) begin
          /* Enable register write */
          case (address_i)
            STR_ADDR:  enable.STR  = 1'b1;
            LDVR_ADDR: enable.LDVR = 1'b1;
            UDVR_ADDR: enable.UDVR = 1'b1;
            FSR_ADDR:  enable.FSR  = 1'b1;
            CTR_ADDR:  enable.CTR  = 1'b1;
            ISR_ADDR:  enable.ISR  = 1'b1;
            TXR_ADDR:  enable.TXR  = 1'b1;
            default:   enable = 8'b0;
          endcase
        end else if (read_i) begin 
          case (address_i)
            STR_ADDR:  data = STR_data;
            LDVR_ADDR: data = DVR_data[LOWER];
            UDVR_ADDR: data = DVR_data[UPPER];
            FSR_ADDR:  data = FSR_data;
            CTR_ADDR:  data = CTR_data;
            ISR_ADDR:  data = ISR_data;
            RXR_ADDR:  data = RXR_data;
            TXR_ADDR:  data = TXR_data;
            default:   data = 8'b0;
          endcase          
        end 
      end : decoder
      
  /* Bidirectional port logic */
  assign data_io = read_i ? data : 8'bZ;

endmodule : configuration_registers