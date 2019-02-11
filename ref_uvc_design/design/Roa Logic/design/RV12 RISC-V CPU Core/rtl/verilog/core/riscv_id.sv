/////////////////////////////////////////////////////////////////
//                                                             //
//    ██████╗  ██████╗  █████╗                                 //
//    ██╔══██╗██╔═══██╗██╔══██╗                                //
//    ██████╔╝██║   ██║███████║                                //
//    ██╔══██╗██║   ██║██╔══██║                                //
//    ██║  ██║╚██████╔╝██║  ██║                                //
//    ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝                                //
//          ██╗      ██████╗  ██████╗ ██╗ ██████╗              //
//          ██║     ██╔═══██╗██╔════╝ ██║██╔════╝              //
//          ██║     ██║   ██║██║  ███╗██║██║                   //
//          ██║     ██║   ██║██║   ██║██║██║                   //
//          ███████╗╚██████╔╝╚██████╔╝██║╚██████╗              //
//          ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝ ╚═════╝              //
//                                                             //
//    RISC-V                                                   //
//    Instruction Decoder                                      //
//                                                             //
/////////////////////////////////////////////////////////////////
//                                                             //
//             Copyright (C) 2014-2017 ROA Logic BV            //
//             www.roalogic.com                                //
//                                                             //
//    Unless specifically agreed in writing, this software is  //
//  licensed under the RoaLogic Non-Commercial License         //
//  version-1.0 (the "License"), a copy of which is included   //
//  with this file or may be found on the RoaLogic website     //
//  http://www.roalogic.com. You may not use the file except   //
//  in compliance with the License.                            //
//                                                             //
//    THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY        //
//  EXPRESS OF IMPLIED WARRANTIES OF ANY KIND.                 //
//  See the License for permissions and limitations under the  //
//  License.                                                   //
//                                                             //
/////////////////////////////////////////////////////////////////

/*
  Changelog: 2017-02-28
             2017-03-01: Updates for 1.9.1 priv.spec
*/

module riscv_id #(
  parameter            XLEN           = 32,
  parameter [XLEN-1:0] PC_INIT        = 'h200,
  parameter            INSTR_SIZE     = 32,
  parameter            EXCEPTION_SIZE = 12,
  parameter            HAS_HYPER      = 0,
  parameter            HAS_SUPER      = 0,
  parameter            HAS_USER       = 0,
  parameter            HAS_FPU        = 0,
  parameter            HAS_MULDIV     = 0,
  parameter            HAS_AMO        = 0
)
(
  input                           rstn,
  input                           clk,
  output reg                      id_stall,

  input                           bu_flush,
                                  st_flush,
                                  du_flush,
  input      [XLEN          -1:0] bu_nxt_pc,
                                  st_nxt_pc,
                                  du_dato,
  input                           ex_stall,
                                  du_stall,

  //Program counter
  input      [XLEN          -1:0] if_pc,
  output reg [XLEN          -1:0] id_pc,
  input      [               1:0] if_bp_predict,
  output reg [               1:0] id_bp_predict,


  //Instruction
  input      [INSTR_SIZE    -1:0] if_instr,
  input                           if_bubble,
  output reg [INSTR_SIZE    -1:0] id_instr,
  output reg                      id_bubble,
  input      [INSTR_SIZE    -1:0] ex_instr,
  input                           ex_bubble,
  input      [INSTR_SIZE    -1:0] wb_instr,
  input                           wb_bubble,

  //Exceptions
  input      [EXCEPTION_SIZE-1:0] if_exception,
                                  ex_exception,
                                  wb_exception,
  output reg [EXCEPTION_SIZE-1:0] id_exception,

  //From State
  input      [               1:0] st_prv,

  //To RF
  output     [               4:0] id_src1,
                                  id_src2,

  //To execution units
  output reg [XLEN          -1:0] id_opA,
                                  id_opB,

  output reg                      id_userf_opA,
                                  id_userf_opB,
                                  id_bypex_opA,
                                  id_bypex_opB,
                                  id_bypwb_opA,
                                  id_bypwb_opB,

  //from WB
  input      [XLEN          -1:0] wb_r
);


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic                      id_bubble_r;

  logic                      stall;


  //Immediates
  logic [XLEN          -1:0] immI,
                             immU;

  //Opcodes
  logic [               6:2] if_opcode,
                             id_opcode,
                             ex_opcode,
                             wb_opcode;

  logic [               2:0] if_func3;
  logic [               6:0] if_func7;

  logic                      is_rv64,
                             has_fp,
                             has_muldiv,
                             has_amo,
                             has_user,
                             has_super,
                             has_hyper;

  logic [               4:0] if_src1,
                             if_src2,
                             id_dst,
                             ex_dst,
                             wb_dst;

  logic                      can_bypex,
                             can_bypwb,
                             can_ldwb;

  logic                      illegal_instr,
                             illegal_alu_instr,
                             illegal_lsu_instr,
                             illegal_muldiv_instr,
                             illegal_csr_rd,
                             illegal_csr_wr;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //
  import riscv_pkg::*;
  import riscv_state_pkg::*;


  /*
   * Program Counter
   */
  always @(posedge clk,negedge rstn)
    if      (!rstn                 ) id_pc <= PC_INIT;
    else if ( st_flush             ) id_pc <= st_nxt_pc;
    else if ( bu_flush ||  du_flush) id_pc <= bu_nxt_pc; //Is this required?! 
    else if (!stall    && !id_stall) id_pc <= if_pc;

  /*
   * Instruction
   */
  always @(posedge clk,negedge rstn)
    if      (!rstn ) id_instr <= INSTR_NOP;
    else if (!stall) id_instr <= if_instr;


  always @(posedge clk,negedge rstn)
    if      (!rstn                            ) id_bubble_r <= 1'b1;
    else if ( bu_flush || st_flush || du_flush) id_bubble_r <= 1'b1;
    else if (!stall                           )
      if  (id_stall) id_bubble_r <= 1'b1;
      else           id_bubble_r <= if_bubble;

  //local stall
  assign stall = ex_stall | (du_stall & (~id_bubble_r | |id_exception));
  assign id_bubble = stall | bu_flush | st_flush | |ex_exception | |wb_exception | id_bubble_r;


  assign if_opcode  = if_instr[ 6: 2];
  assign if_func7   = if_instr[31:25];
  assign if_func3   = if_instr[14:12];

  assign id_opcode  = id_instr [ 6:2];
  assign ex_opcode  = ex_instr [ 6:2];
  assign wb_opcode  = wb_instr [ 6:2];
  assign id_dst     = id_instr [11:7];
  assign ex_dst     = ex_instr [11:7];
  assign wb_dst     = wb_instr [11:7];

  assign is_rv64    = (XLEN       == 64);
  assign has_fp     = (HAS_FPU    !=  0);
  assign has_muldiv = (HAS_MULDIV !=  0);
  assign has_amo    = (HAS_AMO    !=  0);
  assign has_user   = (HAS_USER   !=  0);
  assign has_super  = (HAS_SUPER  !=  0);
  assign has_hyper  = (HAS_HYPER  !=  0);


  always @(posedge clk)
    if (!stall && !id_stall) id_bp_predict <= if_bp_predict;

  /*
   * Exceptions
   */
  always @(posedge clk, negedge rstn)
    if      (!rstn                ) id_exception <= 'h0;
    else if ( bu_flush || st_flush) id_exception <= 'h0;
    else if (!stall               )
        if ( id_stall) id_exception <= 'h0;
        else 
        begin
            id_exception                            <= if_exception;
            id_exception[CAUSE_ILLEGAL_INSTRUCTION] <= ~if_bubble & illegal_instr;
            id_exception[CAUSE_BREAKPOINT         ] <= ~if_bubble & (if_instr == EBREAK);
            id_exception[CAUSE_UMODE_ECALL        ] <= ~if_bubble & (if_instr == ECALL ) & (st_prv == PRV_U) & has_user;
            id_exception[CAUSE_SMODE_ECALL        ] <= ~if_bubble & (if_instr == ECALL ) & (st_prv == PRV_S) & has_super;
            id_exception[CAUSE_HMODE_ECALL        ] <= ~if_bubble & (if_instr == ECALL ) & (st_prv == PRV_H) & has_hyper;
            id_exception[CAUSE_MMODE_ECALL        ] <= ~if_bubble & (if_instr == ECALL ) & (st_prv == PRV_M);
        end

  /*
   * To Register File
   */
  //address into register file. Gets registered in memory
  //Should the hold be handled by the memory?!
  assign id_src1 = ~(du_stall || ex_stall) ? if_instr[19:15] : id_instr[19:15];
  assign id_src2 = ~(du_stall || ex_stall) ? if_instr[24:20] : id_instr[24:20];

  assign if_src1 = if_instr[19:15];
  assign if_src2 = if_instr[24:20];


  /*
   * Decode Immediates
   *
   *                                 31    30          12           11  10           5  4            1            0
   */
  assign immI = { {XLEN-11{if_instr[31]}},                             if_instr[30:25],if_instr[24:21],if_instr[20] };
  assign immU = { {XLEN-31{if_instr[31]}},if_instr[30:12],                                                    12'b0 };


  /*
   * Create ALU operands
   */
  //generate Load-WB-result
  //result might fall inbetween wb_r and data available in Register File
  always_comb
    (* synthesis,parallel_case *)
    casex (wb_opcode)
       OPC_LOAD    : can_ldwb = ~wb_bubble;
       OPC_OP_IMM  : can_ldwb = ~wb_bubble;
       OPC_AUIPC   : can_ldwb = ~wb_bubble;
       OPC_OP_IMM32: can_ldwb = ~wb_bubble;
       OPC_AMO     : can_ldwb = ~wb_bubble;
       OPC_OP      : can_ldwb = ~wb_bubble;
       OPC_LUI     : can_ldwb = ~wb_bubble;
       OPC_OP32    : can_ldwb = ~wb_bubble;
       OPC_JALR    : can_ldwb = ~wb_bubble;
       OPC_JAL     : can_ldwb = ~wb_bubble;
       OPC_SYSTEM  : can_ldwb = ~wb_bubble; //TODO not ALL SYSTEM
       default     : can_ldwb = 'b0;
    endcase


  always @(posedge clk)
    if (!stall)
    begin
    casex (if_opcode)
      OPC_OP_IMM  : begin
                        id_userf_opA <= ~( (if_src1 == wb_dst) & |wb_dst & can_ldwb );
                        id_userf_opB <= 'b0;
                    end
      OPC_AUIPC   : begin
                        id_userf_opA <= 'b0;
                        id_userf_opB <= 'b0;
                    end
      OPC_OP_IMM32: begin
                        id_userf_opA <= ~( (if_src1 == wb_dst) & |wb_dst & can_ldwb );
                        id_userf_opB <= 'b0;
                    end
      OPC_OP      : begin
                        id_userf_opA <= ~( (if_src1 == wb_dst) & |wb_dst & can_ldwb );
                        id_userf_opB <= ~( (if_src2 == wb_dst) & |wb_dst & can_ldwb );
                    end
      OPC_LUI     : begin
                        id_userf_opA <= 'b0;
                        id_userf_opB <= 'b0;
                    end
      OPC_OP32    : begin
                        id_userf_opA <= ~( (if_src1 == wb_dst) & |wb_dst & can_ldwb );
                        id_userf_opB <= ~( (if_src2 == wb_dst) & |wb_dst & can_ldwb );
                    end
      OPC_BRANCH  : begin
                        id_userf_opA <= ~( (if_src1 == wb_dst) & |wb_dst & can_ldwb );
                        id_userf_opB <= ~( (if_src2 == wb_dst) & |wb_dst & can_ldwb );
                    end
      OPC_JALR    : begin
                        id_userf_opA <= ~( (if_src1 == wb_dst) & |wb_dst & can_ldwb );
                        id_userf_opB <= 'b0;
                    end
      OPC_LOAD    : begin
                        id_userf_opA <= ~( (if_src1 == wb_dst) & |wb_dst & can_ldwb );
                        id_userf_opB <= 'b0;
                     end
      OPC_STORE   : begin
                        id_userf_opA <= ~( (if_src1 == wb_dst) & |wb_dst & can_ldwb );
                        id_userf_opB <= ~( (if_src2 == wb_dst) & |wb_dst & can_ldwb );
                    end
      OPC_SYSTEM  : begin
                        id_userf_opA <= ~( (if_src1 == wb_dst) & |wb_dst & can_ldwb );
                        id_userf_opB <= 'b0;
                    end
      default     : begin
                        id_userf_opA <= 'b1;
                        id_userf_opB <= 'b1;
                    end
    endcase
    end


  always @(posedge clk)
    if (!stall)
    (* synthesis,parallel_case *)
    casex (if_opcode)
      OPC_LOAD_FP : ;
      OPC_MISC_MEM: ;
      OPC_OP_IMM  : begin
                        id_opA <= wb_r;
                        id_opB <= immI;
                    end
      OPC_AUIPC   : begin
                        id_opA <= if_pc;
                        id_opB <= immU;
                    end
      OPC_OP_IMM32: begin
                        id_opA <= wb_r;
                        id_opB <= immI;
                    end
      OPC_LOAD    : begin
                        id_opA <= wb_r;
                        id_opB <= immI;
                    end
      OPC_STORE   : begin
                        id_opA <= wb_r;
                        id_opB <= wb_r;
                    end
      OPC_STORE_FP: ;
      OPC_AMO     : ; 
      OPC_OP      : begin
                        id_opA <= wb_r;
                        id_opB <= wb_r;
                    end
      OPC_LUI     : begin
                        id_opA <= 0;
                        id_opB <= immU;
                    end
      OPC_OP32    : begin
                        id_opA <= wb_r;
                        id_opB <= wb_r;
                    end
      OPC_MADD    : ;
      OPC_MSUB    : ;
      OPC_NMSUB   : ;
      OPC_NMADD   : ;
      OPC_OP_FP   : ;
      OPC_BRANCH  : begin
                        id_opA <= wb_r;
                        id_opB <= wb_r;
                    end
      OPC_JALR    : begin
                        id_opA <= wb_r;
                        id_opB <= immI;
                    end
      OPC_SYSTEM  : begin
                        id_opA <= wb_r;                        //for CSRxx
                        id_opB <= { {XLEN-5{1'b0}},if_src1 };  //for CSRxxI
                    end
      default     : begin
                        id_opA <= 'hx;
                        id_opB <= 'hx;
                    end
    endcase


  /*
   * Bypasses
   */
  //Check for each stage if the result should be used
  always_comb
    (* synthesis,parallel_case *)
    casex (id_opcode)
       OPC_LOAD    : can_bypex = ~id_bubble;
       OPC_OP_IMM  : can_bypex = ~id_bubble;
       OPC_AUIPC   : can_bypex = ~id_bubble;
       OPC_OP_IMM32: can_bypex = ~id_bubble;
       OPC_AMO     : can_bypex = ~id_bubble;
       OPC_OP      : can_bypex = ~id_bubble;
       OPC_LUI     : can_bypex = ~id_bubble;
       OPC_OP32    : can_bypex = ~id_bubble;
       OPC_JALR    : can_bypex = ~id_bubble;
       OPC_JAL     : can_bypex = ~id_bubble;
       OPC_SYSTEM  : can_bypex = ~id_bubble; //TODO not ALL SYSTEM
       default     : can_bypex = 'b0;
    endcase

  always_comb
    (* synthesis,parallel_case *)
    casex (ex_opcode)
       OPC_LOAD    : can_bypwb = ~ex_bubble;
       OPC_OP_IMM  : can_bypwb = ~ex_bubble;
       OPC_AUIPC   : can_bypwb = ~ex_bubble;
       OPC_OP_IMM32: can_bypwb = ~ex_bubble;
       OPC_AMO     : can_bypwb = ~ex_bubble;
       OPC_OP      : can_bypwb = ~ex_bubble;
       OPC_LUI     : can_bypwb = ~ex_bubble;
       OPC_OP32    : can_bypwb = ~ex_bubble;
       OPC_JALR    : can_bypwb = ~ex_bubble;
       OPC_JAL     : can_bypwb = ~ex_bubble;
       OPC_SYSTEM  : can_bypwb = ~ex_bubble; //TODO not ALL SYSTEM
       default     : can_bypwb = 'b0;
    endcase


  /*
   set bypass switches.
   'x0' is used as a black hole. It should always be zero, but may contain other values in the pipeline
   therefore we check if dst is non-zero
  */
  always @(posedge clk)
    if (!stall)
    (* synthesis,parallel_case *)
    casex (if_opcode)
      OPC_OP_IMM  : begin
                        id_bypex_opA <= (if_src1 == id_dst) & |id_dst & can_bypex;
                        id_bypex_opB <= 'b0;

                        id_bypwb_opA <= (if_src1 == ex_dst) & |ex_dst & can_bypwb;
                        id_bypwb_opB <= 'b0;
                    end
      OPC_OP_IMM32: begin
                        id_bypex_opA <= (if_src1 == id_dst) & |id_dst & can_bypex;
                        id_bypex_opB <= 'b0;

                        id_bypwb_opA <= (if_src1 == ex_dst ) & |ex_dst & can_bypwb;
                        id_bypwb_opB <= 'b0;
                    end
      OPC_OP      : begin
                        id_bypex_opA <= (if_src1 == id_dst) & |id_dst & can_bypex;
                        id_bypex_opB <= (if_src2 == id_dst) & |id_dst & can_bypex;

                        id_bypwb_opA <= (if_src1 == ex_dst) & |ex_dst & can_bypwb;
                        id_bypwb_opB <= (if_src2 == ex_dst) & |ex_dst & can_bypwb;
                    end
      OPC_OP32    : begin
                        id_bypex_opA <= (if_src1 == id_dst ) & |id_dst & can_bypex;
                        id_bypex_opB <= (if_src2 == id_dst ) & |id_dst & can_bypex;

                        id_bypwb_opA <= (if_src1 == ex_dst ) & |ex_dst & can_bypwb;
                        id_bypwb_opB <= (if_src2 == ex_dst ) & |ex_dst & can_bypwb;
                    end
      OPC_BRANCH  : begin
                        id_bypex_opA <= (if_src1 == id_dst ) & |id_dst & can_bypex;
                        id_bypex_opB <= (if_src2 == id_dst ) & |id_dst & can_bypex;

                        id_bypwb_opA <= (if_src1 == ex_dst ) & |ex_dst & can_bypwb;
                        id_bypwb_opB <= (if_src2 == ex_dst ) & |ex_dst & can_bypwb;
                    end
      OPC_JALR    : begin
                        id_bypex_opA <= (if_src1 == id_dst ) & |id_dst & can_bypex;
                        id_bypex_opB <= 'b0;

                        id_bypwb_opA <= (if_src1 == ex_dst ) & |ex_dst & can_bypwb;
                        id_bypwb_opB <= 'b0;
                    end
     OPC_LOAD     : begin
                        id_bypex_opA <= (if_src1 == id_dst ) & |id_dst & can_bypex;
                        id_bypex_opB <= 'b0;

                        id_bypwb_opA <= (if_src1 == ex_dst ) & |ex_dst & can_bypwb;
                        id_bypwb_opB <= 'b0;
                    end
     OPC_STORE    : begin
                        id_bypex_opA <= (if_src1 == id_dst ) & |id_dst & can_bypex;
                        id_bypex_opB <= (if_src2 == id_dst ) & |id_dst & can_bypex;

                        id_bypwb_opA <= (if_src1 == ex_dst ) & |ex_dst & can_bypwb;
                        id_bypwb_opB <= (if_src2 == ex_dst ) & |ex_dst & can_bypwb;
                    end
     OPC_SYSTEM   : begin
                        id_bypex_opA <= (if_src1 == id_dst ) & |id_dst & can_bypex;
                        id_bypex_opB <= 'b0;

                        id_bypwb_opA <= (if_src1 == ex_dst ) & |ex_dst & can_bypwb;
                        id_bypwb_opB <= 'b0;
                    end
      default     : begin
                        id_bypex_opA <= 'b0;
                        id_bypex_opB <= 'b0;

                        id_bypwb_opA <= 'b0;
                        id_bypwb_opB <= 'b0;
                    end
    endcase


  /*
   * Generate STALL
   */
  always_comb
    if      (bu_flush || st_flush || du_flush) id_stall = 'b0;        //flush overrules stall
    else if (stall                           ) id_stall = ~if_bubble; //ignore NOPs e.g. after flush or IF-stall
/*
    else if (id_opcode == OPC_LOAD)
      casex (if_opcode)
        OPC_OP_IMM  : id_stall = (if_src1 == id_dst);
        OPC_OP_IMM32: id_stall = (if_src1 == id_dst);
        OPC_OP      : id_stall = (if_src1 == id_dst) | (if_src2 == id_dst);
        OPC_OP32    : id_stall = (if_src1 == id_dst) | (if_src2 == id_dst);
        OPC_BRANCH  : id_stall = (if_src1 == id_dst) | (if_src2 == id_dst);
        OPC_JALR    : id_stall = (if_src1 == id_dst);
        OPC_LOAD    : id_stall = (if_src1 == id_dst);
        OPC_STORE   : id_stall = (if_src1 == id_dst) | (if_src2 == id_dst);
        OPC_SYSTEM  : id_stall = (if_src1 == id_dst);
        default     : id_stall = 'b0;
      endcase
*/
   else id_stall = 'b0;


  /*
   * Generate Illegal Instruction
   */

  always_comb
    casex (if_opcode)
      OPC_LOAD  : illegal_instr = illegal_lsu_instr;
      OPC_STORE : illegal_instr = illegal_lsu_instr;
      default   : illegal_instr = illegal_alu_instr & (has_muldiv ? illegal_muldiv_instr : 1'b1);
    endcase


  //ALU
  always_comb
    casex (if_instr)
       FENCE  : illegal_alu_instr = 1'b0;
       FENCE_I: illegal_alu_instr = 1'b0;
       ECALL  : illegal_alu_instr = 1'b0;
       EBREAK : illegal_alu_instr = 1'b0;
       URET   : illegal_alu_instr = has_user  ? 1'b0            : 1'b1;
       SRET   : illegal_alu_instr = has_super ? st_prv <  PRV_S : 1'b1;
       HRET   : illegal_alu_instr = has_hyper ? st_prv <  PRV_H : 1'b1;
       MRET   : illegal_alu_instr = st_prv != PRV_M;
       default:
            (* synthesis,parallel_case *)
            casex ( {is_rv64,if_func7,if_func3,if_opcode} )
              {1'b?,LUI   }: illegal_alu_instr = 1'b0;
              {1'b?,AUIPC }: illegal_alu_instr = 1'b0;
              {1'b?,JAL   }: illegal_alu_instr = 1'b0;
              {1'b?,JALR  }: illegal_alu_instr = 1'b0;
              {1'b?,BEQ   }: illegal_alu_instr = 1'b0;
              {1'b?,BNE   }: illegal_alu_instr = 1'b0;
              {1'b?,BLT   }: illegal_alu_instr = 1'b0;
              {1'b?,BGE   }: illegal_alu_instr = 1'b0;
              {1'b?,BLTU  }: illegal_alu_instr = 1'b0;
              {1'b?,BGEU  }: illegal_alu_instr = 1'b0;
              {1'b?,ADDI  }: illegal_alu_instr = 1'b0;
              {1'b?,ADD   }: illegal_alu_instr = 1'b0;
              {1'b1,ADDIW }: illegal_alu_instr = 1'b0;                   //RV64
              {1'b1,ADDW  }: illegal_alu_instr = 1'b0;                   //RV64
              {1'b?,SUB   }: illegal_alu_instr = 1'b0;
              {1'b1,SUBW  }: illegal_alu_instr = 1'b0;                   //RV64
              {1'b?,XORI  }: illegal_alu_instr = 1'b0;
              {1'b?,XOR   }: illegal_alu_instr = 1'b0;
              {1'b?,ORI   }: illegal_alu_instr = 1'b0;
              {1'b?,OR    }: illegal_alu_instr = 1'b0;
              {1'b?,ANDI  }: illegal_alu_instr = 1'b0;
              {1'b?,AND   }: illegal_alu_instr = 1'b0;
              {1'b?,SLLI  }: illegal_alu_instr = ~is_rv64 & if_func7[0]; //shamt[5] illegal for RV32
              {1'b?,SLL   }: illegal_alu_instr = 1'b0;
              {1'b1,SLLIW }: illegal_alu_instr = 1'b0;                   //RV64
              {1'b1,SLLW  }: illegal_alu_instr = 1'b0;                   //RV64
              {1'b?,SLTI  }: illegal_alu_instr = 1'b0;
              {1'b?,SLT   }: illegal_alu_instr = 1'b0;
              {1'b?,SLTIU }: illegal_alu_instr = 1'b0;
              {1'b?,SLTU  }: illegal_alu_instr = 1'b0;
              {1'b?,SRLI  }: illegal_alu_instr = ~is_rv64 & if_func7[0]; //shamt[5] illegal for RV32
              {1'b?,SRL   }: illegal_alu_instr = 1'b0;
              {1'b1,SRLIW }: illegal_alu_instr = 1'b0;                   //RV64
              {1'b1,SRLW  }: illegal_alu_instr = 1'b0;                   //RV64
              {1'b?,SRAI  }: illegal_alu_instr = ~is_rv64 & if_func7[0]; //shamt[5] illegal for RV32
              {1'b?,SRA   }: illegal_alu_instr = 1'b0;
              {1'b1,SRAIW }: illegal_alu_instr = 1'b0;
              {1'b?,SRAW  }: illegal_alu_instr = 1'b0;
  
              //system
              {1'b?,CSRRW }: illegal_alu_instr = illegal_csr_rd |             illegal_csr_wr ;
              {1'b?,CSRRS }: illegal_alu_instr = illegal_csr_rd | (|if_src1 & illegal_csr_wr);
              {1'b?,CSRRC }: illegal_alu_instr = illegal_csr_rd | (|if_src1 & illegal_csr_wr);
              {1'b?,CSRRWI}: illegal_alu_instr = illegal_csr_rd | (|if_src1 & illegal_csr_wr);
              {1'b?,CSRRSI}: illegal_alu_instr = illegal_csr_rd | (|if_src1 & illegal_csr_wr);
              {1'b?,CSRRCI}: illegal_alu_instr = illegal_csr_rd | (|if_src1 & illegal_csr_wr);

              default: illegal_alu_instr = 1'b1;
            endcase
        endcase

  //LSU
  always_comb
    casex ( {is_rv64,has_amo,if_func7,if_func3,if_opcode} )
      {1'b?,1'b?,LB    }: illegal_lsu_instr = 1'b0;
      {1'b?,1'b?,LH    }: illegal_lsu_instr = 1'b0;
      {1'b?,1'b?,LW    }: illegal_lsu_instr = 1'b0;
      {1'b1,1'b?,LD    }: illegal_lsu_instr = 1'b0;  //RV64
      {1'b?,1'b?,LBU   }: illegal_lsu_instr = 1'b0;
      {1'b?,1'b?,LHU   }: illegal_lsu_instr = 1'b0;
      {1'b1,1'b?,LWU   }: illegal_lsu_instr = 1'b0;  //RV64
      {1'b?,1'b?,SB    }: illegal_lsu_instr = 1'b0;
      {1'b?,1'b?,SH    }: illegal_lsu_instr = 1'b0;
      {1'b?,1'b?,SW    }: illegal_lsu_instr = 1'b0;
      {1'b1,1'b?,SD    }: illegal_lsu_instr = 1'b0;  //RV64

      //AMO
      default           : illegal_lsu_instr = 1'b1;
    endcase


  //MULDIV
  always_comb
    casex ( {is_rv64,if_func7,if_func3,if_opcode} )
      {1'b?,MUL    }: illegal_muldiv_instr = 1'b0;
      {1'b?,MULH   }: illegal_muldiv_instr = 1'b0;
      {1'b1,MULW   }: illegal_muldiv_instr = 1'b0;  //RV64
      {1'b?,MULHSU }: illegal_muldiv_instr = 1'b0;
      {1'b?,MULHU  }: illegal_muldiv_instr = 1'b0;
      {1'b?,DIV    }: illegal_muldiv_instr = 1'b0;
      {1'b1,DIVW   }: illegal_muldiv_instr = 1'b0;  //RV64
      {1'b?,DIVU   }: illegal_muldiv_instr = 1'b0;
      {1'b1,DIVUW  }: illegal_muldiv_instr = 1'b0;  //RV64
      {1'b?,REM    }: illegal_muldiv_instr = 1'b0;
      {1'b1,REMW   }: illegal_muldiv_instr = 1'b0;  //RV64
      {1'b?,REMU   }: illegal_muldiv_instr = 1'b0;
      {1'b1,REMUW  }: illegal_muldiv_instr = 1'b0;
      default       : illegal_muldiv_instr = 1'b1;
    endcase

  /*
   * Check CSR accesses
   */
  always_comb
    case (if_instr[31:20])
      //User
      USTATUS   : illegal_csr_rd = (HAS_USER  == 0);
      UIE       : illegal_csr_rd = (HAS_USER  == 0);
      UTVEC     : illegal_csr_rd = (HAS_USER  == 0);
      USCRATCH  : illegal_csr_rd = (HAS_USER  == 0);
      UEPC      : illegal_csr_rd = (HAS_USER  == 0);
      UCAUSE    : illegal_csr_rd = (HAS_USER  == 0);
      UBADADDR  : illegal_csr_rd = (HAS_USER  == 0);
      UIP       : illegal_csr_rd = (HAS_USER  == 0);
      FFLAGS    : illegal_csr_rd = (HAS_FPU   == 0);
      FRM       : illegal_csr_rd = (HAS_FPU   == 0);
      FCSR      : illegal_csr_rd = (HAS_FPU   == 0);
      CYCLE     : illegal_csr_rd = (HAS_USER  == 0);
      TIME      : illegal_csr_rd = (HAS_USER  == 0);
      INSTRET   : illegal_csr_rd = (HAS_USER  == 0);
      //TODO: hpmcounters
      CYCLEH    : illegal_csr_rd =                    (XLEN > 32);
      TIMEH     : illegal_csr_rd =                    (XLEN > 32);
      INSTRETH  : illegal_csr_rd =                    (XLEN > 32);
      //Supervisor
      SSTATUS   : illegal_csr_rd = (HAS_SUPER == 0)               | (st_prv < PRV_S);
      SEDELEG   : illegal_csr_rd = (HAS_SUPER == 0)               | (st_prv < PRV_S);
      SIDELEG   : illegal_csr_rd = (HAS_SUPER == 0)               | (st_prv < PRV_S);
      SIE       : illegal_csr_rd = (HAS_SUPER == 0)               | (st_prv < PRV_S);
      STVEC     : illegal_csr_rd = (HAS_SUPER == 0)               | (st_prv < PRV_S);
      SSCRATCH  : illegal_csr_rd = (HAS_SUPER == 0)               | (st_prv < PRV_S);
      SEPC      : illegal_csr_rd = (HAS_SUPER == 0)               | (st_prv < PRV_S);
      SCAUSE    : illegal_csr_rd = (HAS_SUPER == 0)               | (st_prv < PRV_S);
      SBADADDR  : illegal_csr_rd = (HAS_SUPER == 0)               | (st_prv < PRV_S);
      SIP       : illegal_csr_rd = (HAS_SUPER == 0)               | (st_prv < PRV_S);
      SPTBR     : illegal_csr_rd = (HAS_SUPER == 0)               | (st_prv < PRV_S);
      //Hypervisor
      HSTATUS   : illegal_csr_rd = (HAS_HYPER == 0)               | (st_prv < PRV_H);
      HEDELEG   : illegal_csr_rd = (HAS_HYPER == 0)               | (st_prv < PRV_H);
      HIDELEG   : illegal_csr_rd = (HAS_HYPER == 0)               | (st_prv < PRV_H);
      HIE       : illegal_csr_rd = (HAS_HYPER == 0)               | (st_prv < PRV_H);
      HTVEC     : illegal_csr_rd = (HAS_HYPER == 0)               | (st_prv < PRV_H);
      HSCRATCH  : illegal_csr_rd = (HAS_HYPER == 0)               | (st_prv < PRV_H);
      HEPC      : illegal_csr_rd = (HAS_HYPER == 0)               | (st_prv < PRV_H);
      HCAUSE    : illegal_csr_rd = (HAS_HYPER == 0)               | (st_prv < PRV_H);
      HBADADDR  : illegal_csr_rd = (HAS_HYPER == 0)               | (st_prv < PRV_H);
      HIP       : illegal_csr_rd = (HAS_HYPER == 0)               | (st_prv < PRV_H);
      //Machine
      MVENDORID : illegal_csr_rd =                                  (st_prv < PRV_M);
      MARCHID   : illegal_csr_rd =                                  (st_prv < PRV_M);
      MIMPID    : illegal_csr_rd =                                  (st_prv < PRV_M);
      MHARTID   : illegal_csr_rd =                                  (st_prv < PRV_M);
      MSTATUS   : illegal_csr_rd =                                  (st_prv < PRV_M);
      MISA      : illegal_csr_rd =                                  (st_prv < PRV_M);
      MEDELEG   : illegal_csr_rd =                                  (st_prv < PRV_M);
      MIDELEG   : illegal_csr_rd =                                  (st_prv < PRV_M);
      MIE       : illegal_csr_rd =                                  (st_prv < PRV_M);
      MTVEC     : illegal_csr_rd =                                  (st_prv < PRV_M);
      MSCRATCH  : illegal_csr_rd =                                  (st_prv < PRV_M);
      MEPC      : illegal_csr_rd =                                  (st_prv < PRV_M);
      MCAUSE    : illegal_csr_rd =                                  (st_prv < PRV_M);
      MBADADDR  : illegal_csr_rd =                                  (st_prv < PRV_M);
      MIP       : illegal_csr_rd =                                  (st_prv < PRV_M);
      MBASE     : illegal_csr_rd =                                  (st_prv < PRV_M);
      MBOUND    : illegal_csr_rd =                                  (st_prv < PRV_M);
      MIBASE    : illegal_csr_rd =                                  (st_prv < PRV_M);
      MIBOUND   : illegal_csr_rd =                                  (st_prv < PRV_M);
      MDBASE    : illegal_csr_rd =                                  (st_prv < PRV_M);
      MDBOUND   : illegal_csr_rd =                                  (st_prv < PRV_M);

      default   : illegal_csr_rd = 1'b1;
    endcase

  always_comb
    case (if_instr[31:20])
      USTATUS   : illegal_csr_wr = (HAS_USER  == 0);
      UIE       : illegal_csr_wr = (HAS_USER  == 0);
      UTVEC     : illegal_csr_wr = (HAS_USER  == 0);
      USCRATCH  : illegal_csr_wr = (HAS_USER  == 0);
      UEPC      : illegal_csr_wr = (HAS_USER  == 0);
      UCAUSE    : illegal_csr_wr = (HAS_USER  == 0);
      UBADADDR  : illegal_csr_wr = (HAS_USER  == 0);
      UIP       : illegal_csr_wr = (HAS_USER  == 0);
      FFLAGS    : illegal_csr_wr = (HAS_FPU   == 0);
      FRM       : illegal_csr_wr = (HAS_FPU   == 0);
      FCSR      : illegal_csr_wr = (HAS_FPU   == 0);
      CYCLE     : illegal_csr_wr = 1'b1; 
      TIME      : illegal_csr_wr = 1'b1;
      INSTRET   : illegal_csr_wr = 1'b1;
      //TODO:hpmcounters
      CYCLEH    : illegal_csr_wr = 1'b1;
      TIMEH     : illegal_csr_wr = 1'b1;
      INSTRETH  : illegal_csr_wr = 1'b1;
      //Supervisor
      SSTATUS   : illegal_csr_wr = (HAS_SUPER == 0)               | (st_prv < PRV_S);
      SEDELEG   : illegal_csr_wr = (HAS_SUPER == 0)               | (st_prv < PRV_S);
      SIDELEG   : illegal_csr_wr = (HAS_SUPER == 0)               | (st_prv < PRV_S);
      SIE       : illegal_csr_wr = (HAS_SUPER == 0)               | (st_prv < PRV_S);
      STVEC     : illegal_csr_wr = (HAS_SUPER == 0)               | (st_prv < PRV_S);
      SSCRATCH  : illegal_csr_wr = (HAS_SUPER == 0)               | (st_prv < PRV_S);
      SEPC      : illegal_csr_wr = (HAS_SUPER == 0)               | (st_prv < PRV_S);
      SCAUSE    : illegal_csr_wr = (HAS_SUPER == 0)               | (st_prv < PRV_S);
      SBADADDR  : illegal_csr_wr = (HAS_SUPER == 0)               | (st_prv < PRV_S);
      SIP       : illegal_csr_wr = (HAS_SUPER == 0)               | (st_prv < PRV_S);
      SPTBR     : illegal_csr_wr = (HAS_SUPER == 0)               | (st_prv < PRV_S);
     //Hypervisor
      HSTATUS   : illegal_csr_wr = (HAS_HYPER == 0)               | (st_prv < PRV_H);
      HEDELEG   : illegal_csr_wr = (HAS_HYPER == 0)               | (st_prv < PRV_H);
      HIDELEG   : illegal_csr_wr = (HAS_HYPER == 0)               | (st_prv < PRV_H);
      HIE       : illegal_csr_wr = (HAS_HYPER == 0)               | (st_prv < PRV_H);
      HTVEC     : illegal_csr_wr = (HAS_HYPER == 0)               | (st_prv < PRV_H);
      HSCRATCH  : illegal_csr_wr = (HAS_HYPER == 0)               | (st_prv < PRV_H);
      HEPC      : illegal_csr_wr = (HAS_HYPER == 0)               | (st_prv < PRV_H);
      HCAUSE    : illegal_csr_wr = (HAS_HYPER == 0)               | (st_prv < PRV_H);
      HBADADDR  : illegal_csr_wr = (HAS_HYPER == 0)               | (st_prv < PRV_H);
      HIP       : illegal_csr_wr = (HAS_HYPER == 0)               | (st_prv < PRV_H);
      //Machine
      MVENDORID : illegal_csr_wr = 1'b1;
      MARCHID   : illegal_csr_wr = 1'b1;
      MIMPID    : illegal_csr_wr = 1'b1;
      MHARTID   : illegal_csr_wr = 1'b1;
      MSTATUS   : illegal_csr_wr =                                  (st_prv < PRV_M);
      MISA      : illegal_csr_wr =                                  (st_prv < PRV_M);
      MEDELEG   : illegal_csr_wr =                                  (st_prv < PRV_M);
      MIDELEG   : illegal_csr_wr =                                  (st_prv < PRV_M);
      MIE       : illegal_csr_wr =                                  (st_prv < PRV_M);
      MTVEC     : illegal_csr_wr =                                  (st_prv < PRV_M);
      MNMIVEC   : illegal_csr_wr =                                  (st_prv < PRV_M);
      MSCRATCH  : illegal_csr_wr =                                  (st_prv < PRV_M);
      MEPC      : illegal_csr_wr =                                  (st_prv < PRV_M);
      MCAUSE    : illegal_csr_wr =                                  (st_prv < PRV_M);
      MBADADDR  : illegal_csr_wr =                                  (st_prv < PRV_M);
      MIP       : illegal_csr_wr =                                  (st_prv < PRV_M);
      MBASE     : illegal_csr_wr =                                  (st_prv < PRV_M);
      MBOUND    : illegal_csr_wr =                                  (st_prv < PRV_M);
      MIBASE    : illegal_csr_wr =                                  (st_prv < PRV_M);
      MIBOUND   : illegal_csr_wr =                                  (st_prv < PRV_M);
      MDBASE    : illegal_csr_wr =                                  (st_prv < PRV_M);
      MDBOUND   : illegal_csr_wr =                                  (st_prv < PRV_M);
      MCYCLE    : illegal_csr_wr =                                  (st_prv < PRV_M); 
      MINSTRET  : illegal_csr_wr =                                  (st_prv < PRV_M);
     //TODO: performance counters
      MCYCLEH   : illegal_csr_wr =                    (XLEN > 32) | (st_prv < PRV_M);
      MINSTRETH : illegal_csr_wr =                    (XLEN > 32) | (st_prv < PRV_M);

      default   : illegal_csr_wr = 1'b1;
    endcase

endmodule


