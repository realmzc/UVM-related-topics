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
//    Arithmetic & Logical Unit (ALU)                          //
//                                                             //
/////////////////////////////////////////////////////////////////
//                                                             //
//             Copyright (C) 2017 ROA Logic BV                 //
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

module riscv_alu #(
  parameter            XLEN           = 32,
  parameter            INSTR_SIZE     = 32,
  parameter            HAS_RVC        = 0
)
(
  input                           rstn,
  input                           clk,

  input                           ex_stall,

  //Program counter
  input      [XLEN          -1:0] id_pc,

  //Instruction
  input                           id_bubble,
  input      [INSTR_SIZE    -1:0] id_instr,

  //from ID
  input      [XLEN          -1:0] opA,
                                  opB,

  //to WB
  output reg                      alu_bubble,
  output reg [XLEN          -1:0] alu_r,


  //To State
  output reg [              11:0] ex_csr_reg,
  output reg [XLEN          -1:0] ex_csr_wval,
  output reg                      ex_csr_we,

  //From State
  input      [XLEN          -1:0] st_csr_rval
);


  ////////////////////////////////////////////////////////////////
  //
  // functions
  //
  function [XLEN-1:0] sext32;
    input [31:0] operand;
    logic sign;
  begin
    sign   = operand[31];
    sext32 = { {XLEN-31{sign}}, operand[30:0]};
  end
  endfunction


  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  localparam SBITS=$clog2(XLEN);

  logic [             6:2] opcode;
  logic [             2:0] func3;
  logic [             6:0] func7;
  logic [             4:0] rs1;
  logic                    is_rv64;
  logic                    has_rvc;

  //Operand generation
  logic [            31:0] opA32;
  logic [            31:0] opB32;
  logic [SBITS       -1:0] shamt;
  logic [             4:0] shamt32;

  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //
  import riscv_pkg::*;
  import riscv_state_pkg::*;


  /*
   * Instruction
   */
  assign func7  = id_instr[31:25];
  assign func3  = id_instr[14:12];
  assign opcode = id_instr[ 6: 2];

  assign is_rv64 = (XLEN    == 64);
  assign has_rvc = (HAS_RVC !=  0);

  /*
   *
   */
  assign opA32   = opA[     31:0];
  assign opB32   = opB[     31:0];
  assign shamt   = opB[SBITS-1:0];
  assign shamt32 = opB[      4:0];
  

  /*
   * ALU operations
   */
  always @(posedge clk, negedge rstn)
    if      (!rstn    ) alu_r <= 'h0;
    else if (!ex_stall)
      casex ( {is_rv64,func7,func3,opcode} )
        {1'b?,LUI   }: alu_r <= opA + opB; //actually just opB, but simplify encoding
        {1'b?,AUIPC }: alu_r <= opA + opB;
        {1'b?,JAL   }: alu_r <= id_pc + 'h4;
        {1'b?,JALR  }: alu_r <= id_pc + 'h4;

        //logical operators
        {1'b?,ADDI  }: alu_r <= opA + opB;
        {1'b?,ADD   }: alu_r <= opA + opB;
        {1'b1,ADDIW }: alu_r <= sext32(opA32 + opB32);    //RV64
        {1'b1,ADDW  }: alu_r <= sext32(opA32 + opB32);    //RV64
        {1'b?,SUB   }: alu_r <= opA - opB;
        {1'b1,SUBW  }: alu_r <= sext32(opA32 - opB32);    //RV64
        {1'b?,XORI  }: alu_r <= opA ^ opB;
        {1'b?,XOR   }: alu_r <= opA ^ opB;
        {1'b?,ORI   }: alu_r <= opA | opB;
        {1'b?,OR    }: alu_r <= opA | opB;
        {1'b?,ANDI  }: alu_r <= opA & opB;
        {1'b?,AND   }: alu_r <= opA & opB;
        {1'b?,SLLI  }: alu_r <= opA << shamt;
        {1'b?,SLL   }: alu_r <= opA << shamt;
        {1'b1,SLLIW }: alu_r <= sext32(opA32 << shamt32); //RV64
        {1'b1,SLLW  }: alu_r <= sext32(opA32 << shamt32); //RV64
        {1'b?,SLTI  }: alu_r <= {~opA[XLEN-1],opA[XLEN-2:0]} < {~opB[XLEN-1],opB[XLEN-2:0]} ? 'h1 : 'h0;
        {1'b?,SLT   }: alu_r <= {~opA[XLEN-1],opA[XLEN-2:0]} < {~opB[XLEN-1],opB[XLEN-2:0]} ? 'h1 : 'h0;
        {1'b?,SLTIU }: alu_r <= opA < opB ? 'h1 : 'h0;
        {1'b?,SLTU  }: alu_r <= opA < opB ? 'h1 : 'h0;
        {1'b?,SRLI  }: alu_r <= opA >> shamt;
        {1'b?,SRL   }: alu_r <= opA >> shamt;
        {1'b1,SRLIW }: alu_r <= sext32(opA32 >> shamt32); //RV64
        {1'b1,SRLW  }: alu_r <= sext32(opA32 >> shamt32); //RV64
        {1'b?,SRAI  }: alu_r <= $signed(opA) >>> shamt;
        {1'b?,SRA   }: alu_r <= $signed(opA) >>> shamt;
        {1'b1,SRAIW }: alu_r <= sext32($signed(opA32) >>> shamt32);
        {1'b?,SRAW  }: alu_r <= sext32($signed(opA32) >>> shamt32);

        //CSR access
        {1'b?,CSRRW }: alu_r <= {XLEN{1'b0}} | st_csr_rval;
        {1'b?,CSRRWI}: alu_r <= {XLEN{1'b0}} | st_csr_rval;
        {1'b?,CSRRS }: alu_r <= {XLEN{1'b0}} | st_csr_rval;
        {1'b?,CSRRSI}: alu_r <= {XLEN{1'b0}} | st_csr_rval;
        {1'b?,CSRRC }: alu_r <= {XLEN{1'b0}} | st_csr_rval;
        {1'b?,CSRRCI}: alu_r <= {XLEN{1'b0}} | st_csr_rval;

        default      : alu_r <= 'hx;
      endcase


  always @(posedge clk, negedge rstn)
    if (!rstn) alu_bubble <= 1'b1;
    else if (!ex_stall)
    casex ( {is_rv64,func7,func3,opcode} )
      {1'b?,LUI   }: alu_bubble <= id_bubble;
      {1'b?,AUIPC }: alu_bubble <= id_bubble;
      {1'b?,JAL   }: alu_bubble <= id_bubble;
      {1'b?,JALR  }: alu_bubble <= id_bubble;

      //logical operators
      {1'b?,ADDI  }: alu_bubble <= id_bubble;
      {1'b?,ADD   }: alu_bubble <= id_bubble;
      {1'b1,ADDIW }: alu_bubble <= id_bubble;
      {1'b1,ADDW  }: alu_bubble <= id_bubble;
      {1'b?,SUB   }: alu_bubble <= id_bubble;
      {1'b1,SUBW  }: alu_bubble <= id_bubble;
      {1'b?,XORI  }: alu_bubble <= id_bubble;
      {1'b?,XOR   }: alu_bubble <= id_bubble;
      {1'b?,ORI   }: alu_bubble <= id_bubble;
      {1'b?,OR    }: alu_bubble <= id_bubble;
      {1'b?,ANDI  }: alu_bubble <= id_bubble;
      {1'b?,AND   }: alu_bubble <= id_bubble;
      {1'b?,SLLI  }: alu_bubble <= id_bubble;
      {1'b?,SLL   }: alu_bubble <= id_bubble;
      {1'b1,SLLIW }: alu_bubble <= id_bubble;
      {1'b1,SLLW  }: alu_bubble <= id_bubble;
      {1'b?,SLTI  }: alu_bubble <= id_bubble;
      {1'b?,SLT   }: alu_bubble <= id_bubble;
      {1'b?,SLTIU }: alu_bubble <= id_bubble;
      {1'b?,SLTU  }: alu_bubble <= id_bubble;
      {1'b?,SRLI  }: alu_bubble <= id_bubble;
      {1'b?,SRL   }: alu_bubble <= id_bubble;
      {1'b1,SRLIW }: alu_bubble <= id_bubble;
      {1'b1,SRLW  }: alu_bubble <= id_bubble;
      {1'b?,SRAI  }: alu_bubble <= id_bubble;
      {1'b?,SRA   }: alu_bubble <= id_bubble;
      {1'b1,SRAIW }: alu_bubble <= id_bubble;
      {1'b?,SRAW  }: alu_bubble <= id_bubble;

      //CSR access
      {1'b?,CSRRW }: alu_bubble <= id_bubble;
      {1'b?,CSRRWI}: alu_bubble <= id_bubble;
      {1'b?,CSRRS }: alu_bubble <= id_bubble;
      {1'b?,CSRRSI}: alu_bubble <= id_bubble;
      {1'b?,CSRRC }: alu_bubble <= id_bubble;
      {1'b?,CSRRCI}: alu_bubble <= id_bubble;

      default      : alu_bubble <= 1'b1;
    endcase


  /*
   * CSR
   */
  assign ex_csr_reg = id_instr[31:20];

  always_comb
    casex ( {id_bubble,func7,func3,opcode} )
      {1'b0,CSRRW } : begin
                          ex_csr_we   = 'b1;
                          ex_csr_wval = opA32;
                      end
      {1'b0,CSRRWI} : begin
                          ex_csr_we   = |opB32;
                          ex_csr_wval = opB32;
                      end
      {1'b0,CSRRS } : begin
                          ex_csr_we   = |opA32;
                          ex_csr_wval = st_csr_rval | opA32;
                      end
      {1'b0,CSRRSI} : begin
                          ex_csr_we   = |opB32;
                          ex_csr_wval = st_csr_rval | opB32;
                      end
      {1'b0,CSRRC } : begin
                          ex_csr_we   = |opA32;
                          ex_csr_wval = st_csr_rval & ~opA32;
                      end
      {1'b0,CSRRCI} : begin
                          ex_csr_we   = |opB32;
                          ex_csr_wval = st_csr_rval & ~opB32;
                      end
      default       : begin
                          ex_csr_we   = 'b0;
                          ex_csr_wval = 'hx;
                      end
    endcase

endmodule 
