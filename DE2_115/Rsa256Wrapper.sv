module Rsa256Wrapper(
    input avm_rst,
    input avm_clk,
    output [4:0] avm_address,
    output avm_read,
    input [31:0] avm_readdata,
    output avm_write,
    output [31:0] avm_writedata,
    input avm_waitrequest
);
    localparam RX_BASE     = 0*4;
    localparam TX_BASE     = 1*4;
    localparam STATUS_BASE = 2*4;
    localparam TX_OK_BIT = 6;
    localparam RX_OK_BIT = 7;

    // Feel free to design your own FSM!    
	localparam QUERY_RX      = 0;
	localparam READ          = 1;
	localparam CALC          = 2;
	localparam QUERY_TX      = 3;
	localparam WRITE         = 4;
	
	localparam READ_HEADER   = 0;
    localparam READ_N        = 1;
	localparam READ_E        = 2;
	localparam READ_DATA     = 3;
	
    logic [511:0] n_r, n_w, e_r, e_w, enc_r, enc_w, dec_r, dec_w;
    logic [2:0] state_r, state_w;
    logic [1:0] data_state_r, data_state_w; 
    // needs 64 cycles at most
    logic [5:0] bytes_counter_r, bytes_counter_w;
    logic [4:0] avm_address_r, avm_address_w;
    logic avm_read_r, avm_read_w, avm_write_r, avm_write_w;

    logic rsa_start_r, rsa_start_w;
    logic rsa_finished;
    logic [511:0] rsa_dec;
    
    logic [5:0] cycle; // cycle may be 31 for 256, 63 for 512
    logic [7:0] header_w, header_r;
	logic [7:0] writedata;
    logic [6:0] enc_cycle; // at most 128 cycles (0~127)
    logic [6:0] enc_counter_r, enc_counter_w;

    assign avm_address = avm_address_r;
    assign avm_read = avm_read_r;
    assign avm_write = avm_write_r;
    assign avm_writedata = writedata;
	
    Rsa256Core rsa256_core(
        .i_clk(avm_clk),
        .i_rst(avm_rst),
        .i_start(rsa_start_r),
        .i_a(enc_r),
        .i_e(e_r),
        .i_n(n_r),
        .i_key_size(header_r[7]),
        .o_a_pow_e(rsa_dec),
        .o_finished(rsa_finished)
    );
    task Wait;
        begin
            avm_read_w = 0;
            avm_write_w = 0;
        end
    endtask
    task StartRead;
        input [4:0] addr;
        begin
            avm_read_w = 1;
            avm_write_w = 0;
            avm_address_w = addr;
        end
    endtask
    task StartWrite;
        input [4:0] addr;
        begin
            avm_read_w = 0;
            avm_write_w = 1;
            avm_address_w = addr;
        end
    endtask

    always @(*) begin
        // TODO
        n_w = n_r;
        e_w = e_r;
        enc_w = enc_r;
        dec_w = dec_r;
        avm_address_w = avm_address_r;
        avm_read_w = avm_read_r;
        avm_write_w = avm_write_r;
        state_w = state_r;
        data_state_w = data_state_r;
        bytes_counter_w = bytes_counter_r;
        rsa_start_w = rsa_start_r;      
        enc_counter_w = enc_counter_r;
        header_w = header_r;
		case(state_r)		
			QUERY_RX: begin
				if(!avm_waitrequest && avm_read_r) begin
                    if(avm_readdata[RX_OK_BIT]) begin
					    StartRead(RX_BASE);
                        state_w = READ;
                    end
				end 
                else begin
                    StartRead(STATUS_BASE);
                    state_w = QUERY_RX;
                end
			end		
			READ: begin
			    if(!avm_waitrequest && avm_read_r) begin
                    Wait();
                    bytes_counter_w = bytes_counter_r + 1;
                    state_w = QUERY_RX;				
					case(data_state_r)
                        READ_HEADER: begin
                            header_w = avm_readdata[7:0];
                            data_state_w = READ_N;
                            bytes_counter_w = 0;
                        end
						READ_N: begin
							n_w = n_r << 8;
                            n_w[7:0] = avm_readdata[7:0];
                            if (bytes_counter_r == cycle) begin
			                	data_state_w = READ_E;
                                bytes_counter_w = 0;					
			                end 
						end
						READ_E: begin
							e_w = e_r << 8;
                            e_w[7:0] = avm_readdata[7:0];
                            if (bytes_counter_r == cycle) begin
			                	data_state_w = READ_DATA;
                                bytes_counter_w = 0;					
			                end                            
						end
						READ_DATA: begin
							enc_w = enc_r << 8;
						    enc_w[7:0] = avm_readdata[7:0];
                            if (bytes_counter_r == cycle) begin
			                	rsa_start_w = 1'b1;
                                bytes_counter_w = 0;
                                state_w = CALC;					
			                end                            							
						end
					endcase
                end
			end						
			CALC: begin
				rsa_start_w = 1'b0;
				if (rsa_finished) begin
				    dec_w = rsa_dec;
				    state_w = QUERY_TX;
				end
			end			
			QUERY_TX: begin				
				if(!avm_waitrequest && avm_read_r) begin
                    if(avm_readdata[TX_OK_BIT]) begin
					    StartWrite(TX_BASE);
                        state_w = WRITE;
                    end
				end 
                else begin
					StartRead(STATUS_BASE);
                    state_w = QUERY_TX;
				end			
			end
			WRITE: begin
				if(!avm_waitrequest && avm_write_r) begin
                    Wait();
                    if (bytes_counter_r == cycle-1) begin
                        bytes_counter_w = 0;
                        state_w = QUERY_RX;
                        dec_w = 0;
                        if (enc_counter_r == enc_cycle) begin // same as reset

                            n_w = 0;
                            e_w = 0;
                            enc_w = 0;
                            dec_w = 0;
                            avm_address_w <= STATUS_BASE;
                            avm_read_w <= 1;
                            avm_write_w <= 0;
                            state_w <= QUERY_RX;
                            data_state_w <= READ_HEADER;
                            bytes_counter_w <= 0;
                            rsa_start_w <= 0;
                            enc_counter_w <= 0;
                            header_w <= 8'b01111111;

                        end
                        else begin 
                            data_state_w = READ_DATA;
                            enc_counter_w = enc_counter_r + 1;
                        end
                    end
                    else begin
                        bytes_counter_w = bytes_counter_r + 1;
                        state_w = QUERY_TX;
                        dec_w = dec_r << 8;
                    end                   	
				end 
			end	
		endcase
    end
 
    always_comb begin
        case (header_r[7])
            1'b0: begin
                writedata = dec_r[247-:8];
                cycle = 31;
            end
            1'b1: begin 
                writedata = dec_r[503-:8];
                cycle = 63;
            end
        endcase
        enc_cycle = header_r[6:0];
    end

    always_ff @(posedge avm_clk or posedge avm_rst) begin
		if (avm_rst) begin
            n_r <= 0;
            e_r <= 0;
            enc_r <= 0;
            dec_r <= 0;
            avm_address_r <= STATUS_BASE;
            avm_read_r <= 1;
            avm_write_r <= 0;
            state_r <= QUERY_RX;
            data_state_r <= READ_HEADER;
            bytes_counter_r <= 0;
            rsa_start_r <= 0;
            enc_counter_r <= 0;
            header_r <= 8'b01111111;
        end else begin
            n_r <= n_w;
            e_r <= e_w;
            enc_r <= enc_w;
            dec_r <= dec_w;
            avm_address_r <= avm_address_w;
            avm_read_r <= avm_read_w;
            avm_write_r <= avm_write_w;
            state_r <= state_w;
            data_state_r <= data_state_w;
            bytes_counter_r <= bytes_counter_w;
            rsa_start_r <= rsa_start_w;
            enc_counter_r <= enc_counter_w;
            header_r <= header_w;
        end
    end

endmodule
