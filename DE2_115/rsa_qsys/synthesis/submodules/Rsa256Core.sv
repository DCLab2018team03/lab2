// compute a^e mod n = m^d mod N in Lab2_tutorial
module Rsa256Core(
	input i_clk,
	input i_rst,
	input i_start,
	input [511:0] i_a, // m
	input [511:0] i_e, // d
	input [511:0] i_n, // N
	input i_key_size,  //0 for 256, 1 for 512
	output logic [511:0] o_a_pow_e,
	output logic o_finished
);
	parameter IDLE  = 3'd0;
	parameter CALCm = 3'd1;
	parameter CALCt = 3'd2;
	parameter DONE  = 3'd3;
	parameter WAITm = 3'd4;
	parameter WAITt = 3'd5;
	
	logic [2:0] state, n_state;
	logic [8:0] counter, n_counter;  //lg 512

	logic [511:0] m, n_m;
	logic [511:0] t, n_t;
	logic [511:0] d;
	logic [511:0] big_n;
	
	//parameter BIT_128  = 2'b00;
	parameter BIT_256  = 1'b0;
	parameter BIT_512  = 1'b1;
	//parameter BIT_1024 = 2'b11;	
	logic  RSA_SIZE;

	
	// for submodule
	logic MOP_start;
	logic [511:0] m_i_a; // a
	logic [511:0] m_i_b; // b
	logic [511:0] m_i_n; // N
	logic [511:0] a_b_mod_n;
	logic m_finished;

	always_ff @(posedge i_clk or posedge i_rst) begin
		if ( i_rst ) begin

			state <= IDLE;
			counter <= 0;		
			RSA_SIZE <= 0;

		end else begin
			
			state <= n_state;
			counter <= n_counter;

			if ( i_start ) begin
				m <= 1;
				t <= 0;
				d <= i_e;
				big_n <= i_n;
				RSA_SIZE <= i_key_size;
			end
			m <= n_m;
			t <= n_t;

		end
	end

	always_comb begin

		n_state = state;
		n_counter = counter;
		n_m = m;
		n_t = t;

		o_a_pow_e = 0;
		o_finished = 0;

		MOP_start = 0;
		m_i_a = 0;
		m_i_b = 0;
		m_i_n = 0;


		case( state )
			IDLE: begin
				if ( i_start ) begin
					n_state = CALCm;
				end else begin
					n_state = IDLE;
				end
				n_m = 1;
				n_counter = 0;
				n_t = i_a;
			end
			CALCm: begin
				if ( d[counter] == 1 ) begin
					n_state = WAITm;
					MOP_start = 1;
					m_i_a = m;
					m_i_b = t;
					m_i_n = big_n;
				end else begin
					n_state = CALCt;
				end
			end
			WAITm: begin
				if ( m_finished ) begin
					n_state = CALCt;
					n_m = a_b_mod_n;
				end else begin
					n_state = WAITm;
				end
				
			end
			CALCt: begin
				n_state = WAITt;
				MOP_start = 1; // MOP_start won't interupt the submodule
				case(RSA_SIZE)
					//BIT_128: begin
					//	if ( counter == 10'd127 ) begin
					//		n_state = DONE;
					//		MOP_start = 0;
					//	end
					//end
					BIT_256: begin
						if ( counter == 9'd255 ) begin
							n_state = DONE;
							MOP_start = 0;
						end
					end
					BIT_512: begin
						if ( counter == 9'd511 ) begin
							n_state = DONE;
							MOP_start = 0;
						end
					end
					//BIT_1024: begin
					//	if ( counter == 10'd1023 ) begin
					//		n_state = DONE;
					//		MOP_start = 0;
					//	end
					//end					
				endcase

				m_i_a = t;
				m_i_b = t;
				m_i_n = big_n;
				n_counter = counter + 1;
			end
			WAITt: begin
				if ( m_finished ) begin
					n_state = CALCm;
					n_t = a_b_mod_n;
				end else begin
					n_state = WAITt;
				end
			end
			DONE: begin
				o_a_pow_e = m;
				o_finished = 1;
				n_state = IDLE;
			end
			default: n_state = state;
		endcase
	end



	ModuloOfProduct mop(
		.i_clk(i_clk),
		.i_rst(i_rst),
		.i_start(MOP_start),
		.m_i_a(m_i_a),
		.m_i_b(m_i_b),
		.m_i_n(m_i_n),
		.i_key_size(RSA_SIZE), // key_size
		.a_b_mod_n(a_b_mod_n),
		.o_finished(m_finished)
	);


endmodule

module ModuloOfProduct(
	input i_clk,
	input i_rst,
	input i_start,
	input [511:0] m_i_a, // a
	input [511:0] m_i_b, // b
	input [511:0] m_i_n, // N
	input i_key_size,  //0 for 256, 1 for 512
	output logic [511:0] a_b_mod_n,
	output logic o_finished
);
	parameter IDLE = 2'd0;
	parameter CALC = 2'd1;
	parameter DONE = 2'd2;
	
	logic [1:0] state, n_state;
	logic [8:0] counter, n_counter; //lg 512

	logic [511:0] a;
	logic [512:0] t, n_t; // for t+t-big_n not to overflow
	logic [512:0] m, n_m; // for m+t-big_n not to overflow
	logic [512:0] t_tmp, m_tmp;
	logic [511:0] big_n;

	//parameter BIT_128  = 2'b00;
	parameter BIT_256  = 1'b0;
	parameter BIT_512  = 1'b1;
	//parameter BIT_1024 = 2'b11;	
	logic  RSA_SIZE;


	always_ff  @(posedge i_clk or posedge i_rst) begin
		if ( i_rst ) begin

			state <= IDLE;
			counter <= 0;
			RSA_SIZE <= 0;

		end else begin
			
			state <= n_state;
			counter <= n_counter;

			if ( i_start ) begin
				a <= m_i_a;
				t <= 0;
				m <= 0;
				big_n <= m_i_n;
				RSA_SIZE <= i_key_size;
			end
			t <= n_t;
			m <= n_m;

		end
	end


	always_comb begin

		n_state = state;
		n_counter = counter;
		n_t = t;
		n_m = m;
		a_b_mod_n = 0;
		o_finished = 0;

		t_tmp = 0;
		m_tmp = 0;

		case( state )
			IDLE: begin
				if ( i_start ) begin
					n_state = CALC;
				end else begin
					n_state = IDLE;
				end
				n_counter = 0;

				n_t = m_i_b;
				n_m = 0; // tutorial is wrong
			end
			CALC: begin
				n_state = CALC;
				case(RSA_SIZE)
					//BIT_128: begin
					//	m_tmp = m[127:0] + t[127:0];
					//	t_tmp = t[127:0] + t[127:0];						
					//	if ( counter == 10'd127 ) begin
					//		n_state = DONE;
					//	end
					//end
					BIT_256: begin
						m_tmp = m[255:0] + t[255:0];
						t_tmp = t[255:0] + t[255:0];
						if ( counter == 9'd255 ) begin
							n_state = DONE;
						end
					end
					BIT_512: begin
						m_tmp = m[511:0] + t[511:0];
						t_tmp = t[511:0] + t[511:0];
						if ( counter == 9'd511 ) begin
							n_state = DONE;
						end
					end
					//BIT_1024: begin
					//	m_tmp = m[1023:0] + t[1023:0];
					//	t_tmp = t[1023:0] + t[1023:0];
					//	if ( counter == 10'd1023 ) begin
					//		n_state = DONE;
					//	end
					//end					
				endcase

				if ( a[counter] == 1 ) begin
					if ( m_tmp > big_n ) begin
						n_m = m_tmp - big_n;
					end else begin
						n_m = m_tmp;
					end
					//n_m[512] should always be zero
				end else begin
					n_m = m;
				end

				if ( t_tmp > big_n ) begin // not sure if here is a problem
					n_t = t_tmp - big_n;
				end else begin
					n_t = t_tmp;
				end
				
				n_counter = counter + 1;
			end
			DONE: begin
				a_b_mod_n = m[512 - 1:0];
				o_finished = 1;
				n_state = IDLE;
			end
			default: begin
				n_state = state;
			end
		endcase
	end
	
  endmodule
