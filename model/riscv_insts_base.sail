/* ****************************************************************** */
/* This file specifies the instructions in the base integer set.      */


/* ****************************************************************** */
union clause ast = UTYPE : (bits(20), regbits, uop)

mapping encdec_uop : uop <-> bits(7) = {
  RISCV_LUI   <-> 0b0110111,
  RISCV_AUIPC <-> 0b0010111
}

mapping clause encdec = UTYPE(imm, rd, op)
  <-> imm @ rd @ encdec_uop(op)

function clause execute UTYPE(imm, rd, op) = {
  let off : xlenbits = EXTS(imm @ 0x000);
  let ret : xlenbits = match op {
    RISCV_LUI   => off,
    RISCV_AUIPC => PC + off
  };
  X(rd) = ret;
  true
}

mapping utype_mnemonic : uop <-> string = {
  RISCV_LUI   <-> "lui",
  RISCV_AUIPC <-> "auipc"
}

mapping clause assembly = UTYPE(imm, rd, op)
  <-> utype_mnemonic(op) ^ spc() ^ reg_name(rd) ^ sep() ^ hex_bits_20(imm)

/* ****************************************************************** */
union clause ast = RISCV_JAL : (bits(21), regbits)

mapping clause encdec = RISCV_JAL(imm_19 @ imm_7_0 @ imm_8 @ imm_18_13 @ imm_12_9 @ 0b0, rd)
  <-> imm_19 : bits(1) @ imm_18_13 : bits(6) @ imm_12_9 : bits(4) @ imm_8 : bits(1) @ imm_7_0 : bits(8) @ rd @ 0b1101111

/*
ideally we want some syntax like

mapping clause encdec = RISCV_JAL(imm @ 0b0, rd) <-> imm[19] @ imm[9..0] @ imm[10] @ imm[18..11] @ rd @ 0b1101111

match bv {
  imm[19] @ imm[9..0] @ imm[10] @ imm[18..11] -> imm @ 0b0
}

but this is difficult
*/

function clause execute (RISCV_JAL(imm, rd)) = {
  let pc : xlenbits = PC;
  let newPC : xlenbits = pc + EXTS(imm);
  if newPC[1] & (~ (haveRVC())) then {
    handle_mem_exception(newPC, E_Fetch_Addr_Align);
    false
  } else {
    X(rd) = nextPC;  /* compatible with JAL and C.JAL */
    nextPC = newPC;
    true
  }
}

/* TODO: handle 2-byte-alignment in mappings */

mapping clause assembly = RISCV_JAL(imm, rd)
  <-> "jal" ^ spc() ^ reg_name(rd) ^ sep() ^ hex_bits_21(imm)

/* ****************************************************************** */
union clause ast = RISCV_JALR : (bits(12), regbits, regbits)

mapping clause encdec = RISCV_JALR(imm, rs1, rd)
  <-> imm @ rs1 @ 0b000 @ rd @ 0b1100111

mapping clause assembly = RISCV_JALR(imm, rs1, rd)
  <-> "jalr" ^ spc() ^ reg_name(rd) ^ sep() ^ reg_name(rs1) ^ sep() ^ hex_bits_12(imm)

/* see riscv_jalr_seq.sail or riscv_jalr_rmem.sail for the execute clause. */

/* ****************************************************************** */
union clause ast = BTYPE : (bits(13), regbits, regbits, bop)

mapping encdec_bop : bop <-> bits(3) = {
  RISCV_BEQ  <-> 0b000,
  RISCV_BNE  <-> 0b001,
  RISCV_BLT  <-> 0b100,
  RISCV_BGE  <-> 0b101,
  RISCV_BLTU <-> 0b110,
  RISCV_BGEU <-> 0b111
}

mapping clause encdec = BTYPE(imm7_6 @ imm5_0 @ imm7_5_0 @ imm5_4_1 @ 0b0, rs2, rs1, op)
  <-> imm7_6 : bits(1) @ imm7_5_0 : bits(6) @ rs2 @ rs1 @ encdec_bop(op) @ imm5_4_1 : bits(4) @ imm5_0 : bits(1) @ 0b1100011

function clause execute (BTYPE(imm, rs2, rs1, op)) = {
  let rs1_val = X(rs1);
  let rs2_val = X(rs2);
  let taken : bool = match op {
    RISCV_BEQ  => rs1_val == rs2_val,
    RISCV_BNE  => rs1_val != rs2_val,
    RISCV_BLT  => rs1_val <_s rs2_val,
    RISCV_BGE  => rs1_val >=_s rs2_val,
    RISCV_BLTU => rs1_val <_u rs2_val,
    RISCV_BGEU => rs1_val >=_u rs2_val
  };
  let newPC = PC + EXTS(imm);
  if taken then {
    if newPC[1] & (~ (haveRVC())) then {
      handle_mem_exception(newPC, E_Fetch_Addr_Align);
      false;
    } else {
      nextPC = newPC;
      true
    }
  } else true
}

mapping btype_mnemonic : bop <-> string = {
  RISCV_BEQ  <-> "beq",
  RISCV_BNE  <-> "bne",
  RISCV_BLT  <-> "blt",
  RISCV_BGE  <-> "bge",
  RISCV_BLTU <-> "bltu",
  RISCV_BGEU <-> "bgeu"
}

mapping clause assembly = BTYPE(imm, rs2, rs1, op)
  <-> btype_mnemonic(op) ^ spc() ^ reg_name(rs1) ^ sep() ^ reg_name(rs2) ^ sep() ^ hex_bits_13(imm)

/* ****************************************************************** */
union clause ast = ITYPE : (bits(12), regbits, regbits, iop)

mapping encdec_iop : iop <-> bits(3) = {
  RISCV_ADDI  <-> 0b000,
  RISCV_SLTI  <-> 0b010,
  RISCV_SLTIU <-> 0b011,
  RISCV_ANDI  <-> 0b111,
  RISCV_ORI   <-> 0b110,
  RISCV_XORI  <-> 0b100
}

mapping clause encdec = ITYPE(imm, rs1, rd, op)
  <-> imm @ rs1 @ encdec_iop(op) @ rd @ 0b0010011

function clause execute (ITYPE (imm, rs1, rd, op)) = {
  let rs1_val = X(rs1);
  let immext : xlenbits = EXTS(imm);
  let result : xlenbits = match op {
    RISCV_ADDI  => rs1_val + immext,
    RISCV_SLTI  => EXTZ(rs1_val <_s immext),
    RISCV_SLTIU => EXTZ(rs1_val <_u immext),
    RISCV_ANDI  => rs1_val & immext,
    RISCV_ORI   => rs1_val | immext,
    RISCV_XORI  => rs1_val ^ immext
  };
  X(rd) = result;
  true
}

mapping itype_mnemonic : iop <-> string = {
  RISCV_ADDI  <-> "addi",
  RISCV_SLTI  <-> "slti",
  RISCV_SLTIU <-> "sltiu",
  RISCV_XORI  <-> "xori",
  RISCV_ORI   <-> "ori",
  RISCV_ANDI  <-> "andi"
}

mapping clause assembly = ITYPE(imm, rs1, rd, op)
  <-> itype_mnemonic(op) ^ spc() ^ reg_name(rd) ^ sep() ^ reg_name(rs1) ^ sep() ^ hex_bits_12(imm)

/* ****************************************************************** */
union clause ast = SHIFTIOP : (bits(6), regbits, regbits, sop)

mapping encdec_sop : sop <-> bits(3) = {
  RISCV_SLLI <-> 0b001,
  RISCV_SRLI <-> 0b101,
  RISCV_SRAI <-> 0b101
}

mapping clause encdec = SHIFTIOP(shamt, rs1, rd, RISCV_SLLI) <-> 0b000000 @ shamt @ rs1 @ 0b001 @ rd @ 0b0010011
mapping clause encdec = SHIFTIOP(shamt, rs1, rd, RISCV_SRLI) <-> 0b000000 @ shamt @ rs1 @ 0b101 @ rd @ 0b0010011
mapping clause encdec = SHIFTIOP(shamt, rs1, rd, RISCV_SRAI) <-> 0b010000 @ shamt @ rs1 @ 0b101 @ rd @ 0b0010011

function clause execute (SHIFTIOP(shamt, rs1, rd, op)) = {
  let rs1_val = X(rs1);
  let result : xlenbits = match op {
    RISCV_SLLI => rs1_val << shamt,
    RISCV_SRLI => rs1_val >> shamt,
    RISCV_SRAI => shift_right_arith64(rs1_val, shamt)
  };
  X(rd) = result;
  true
}

mapping shiftiop_mnemonic : sop <-> string = {
  RISCV_SLLI <-> "slli",
  RISCV_SRLI <-> "srli",
  RISCV_SRAI <-> "srai"
}

mapping clause assembly = SHIFTIOP(shamt, rs1, rd, op)
  <-> shiftiop_mnemonic(op) ^ spc() ^ reg_name(rd) ^ sep() ^ reg_name(rs1) ^ hex_bits_6(shamt)

/* ****************************************************************** */
union clause ast = RTYPE : (regbits, regbits, regbits, rop)

mapping clause encdec = RTYPE(rs2, rs1, rd, RISCV_ADD)  <-> 0b0000000 @ rs2 @ rs1 @ 0b000 @ rd @ 0b0110011
mapping clause encdec = RTYPE(rs2, rs1, rd, RISCV_SLT)  <-> 0b0000000 @ rs2 @ rs1 @ 0b010 @ rd @ 0b0110011
mapping clause encdec = RTYPE(rs2, rs1, rd, RISCV_SLTU) <-> 0b0000000 @ rs2 @ rs1 @ 0b011 @ rd @ 0b0110011
mapping clause encdec = RTYPE(rs2, rs1, rd, RISCV_AND)  <-> 0b0000000 @ rs2 @ rs1 @ 0b111 @ rd @ 0b0110011
mapping clause encdec = RTYPE(rs2, rs1, rd, RISCV_OR)   <-> 0b0000000 @ rs2 @ rs1 @ 0b110 @ rd @ 0b0110011
mapping clause encdec = RTYPE(rs2, rs1, rd, RISCV_XOR)  <-> 0b0000000 @ rs2 @ rs1 @ 0b100 @ rd @ 0b0110011
mapping clause encdec = RTYPE(rs2, rs1, rd, RISCV_SLL)  <-> 0b0000000 @ rs2 @ rs1 @ 0b001 @ rd @ 0b0110011
mapping clause encdec = RTYPE(rs2, rs1, rd, RISCV_SRL)  <-> 0b0000000 @ rs2 @ rs1 @ 0b101 @ rd @ 0b0110011
mapping clause encdec = RTYPE(rs2, rs1, rd, RISCV_SUB)  <-> 0b0100000 @ rs2 @ rs1 @ 0b000 @ rd @ 0b0110011
mapping clause encdec = RTYPE(rs2, rs1, rd, RISCV_SRA)  <-> 0b0100000 @ rs2 @ rs1 @ 0b101 @ rd @ 0b0110011

function clause execute (RTYPE(rs2, rs1, rd, op)) = {
  let rs1_val = X(rs1);
  let rs2_val = X(rs2);
  let result : xlenbits = match op {
    RISCV_ADD  => rs1_val + rs2_val,
    RISCV_SLT  => EXTZ(rs1_val <_s rs2_val),
    RISCV_SLTU => EXTZ(rs1_val <_u rs2_val),
    RISCV_AND  => rs1_val & rs2_val,
    RISCV_OR   => rs1_val | rs2_val,
    RISCV_XOR  => rs1_val ^ rs2_val,
    RISCV_SLL  => rs1_val << (rs2_val[5..0]),
    RISCV_SRL  => rs1_val >> (rs2_val[5..0]),
    RISCV_SUB  => rs1_val - rs2_val,
    RISCV_SRA  => shift_right_arith64(rs1_val, rs2_val[5..0])
  };
  X(rd) = result;
  true
}

mapping rtype_mnemonic : rop <-> string = {
  RISCV_ADD  <-> "add",
  RISCV_SLT  <-> "slt",
  RISCV_SLTU <-> "sltu",
  RISCV_AND  <-> "and",
  RISCV_OR   <-> "or",
  RISCV_XOR  <-> "xor",
  RISCV_SLL  <-> "sll",
  RISCV_SRL  <-> "srl",
  RISCV_SUB  <-> "sub",
  RISCV_SRA  <-> "sra"
}

mapping clause assembly = RTYPE(rs2, rs1, rd, op)
  <-> rtype_mnemonic(op) ^ spc() ^ reg_name(rd) ^ sep() ^ reg_name(rs1) ^ sep() ^ reg_name(rs2)

/* ****************************************************************** */
union clause ast = LOAD : (bits(12), regbits, regbits, bool, word_width, bool, bool)

/* Load unsigned double is only present in RV128I, not RV64I */
/* TODO: aq/rl */
mapping clause encdec = LOAD(imm, rs1, rd, is_unsigned, size, false, false) if size_bits(size) != 0b11 | not_bool(is_unsigned)
  <-> imm @ rs1 @ bool_bits(is_unsigned) @ size_bits(size) @ rd @ 0b0000011 if size_bits(size) != 0b11 | not_bool(is_unsigned)

val extend_value : forall 'n, 0 < 'n <= 8. (bool, MemoryOpResult(bits(8 * 'n))) -> MemoryOpResult(xlenbits)
function extend_value(is_unsigned, value) = match (value) {
  MemValue(v)     => MemValue(if is_unsigned then EXTZ(v) else EXTS(v) : xlenbits),
  MemException(e) => MemException(e)
}

val process_load : forall 'n, 0 < 'n <= 8. (regbits, xlenbits, MemoryOpResult(bits(8 * 'n)), bool) -> bool effect {escape, rreg, wreg}
function process_load(rd, addr, value, is_unsigned) =
  match extend_value(is_unsigned, value) {
    MemValue(result) => { X(rd) = result; true },
    MemException(e)  => { handle_mem_exception(addr, e); false }
  }

function check_misaligned(vaddr : xlenbits, width : word_width) -> bool =
  if   plat_enable_misaligned_access() then false
  else match width {
         BYTE   => false,
         HALF   => vaddr[0] == true,
         WORD   => vaddr[0] == true | vaddr[1] == true,
         DOUBLE => vaddr[0] == true | vaddr[1] == true | vaddr[2] == true
       }

function clause execute(LOAD(imm, rs1, rd, is_unsigned, width, aq, rl)) = {
  let vaddr : xlenbits = X(rs1) + EXTS(imm);
  if   check_misaligned(vaddr, width)
  then { handle_mem_exception(vaddr, E_Load_Addr_Align); false }
  else match translateAddr(vaddr, Read, Data) {
    TR_Failure(e) => { handle_mem_exception(vaddr, e); false },
    TR_Address(addr) =>
      match width {
        BYTE   =>
	  process_load(rd, vaddr, mem_read(addr, 1, aq, rl, false), is_unsigned),
        HALF   =>
	  process_load(rd, vaddr, mem_read(addr, 2, aq, rl, false), is_unsigned),
        WORD   =>
	  process_load(rd, vaddr, mem_read(addr, 4, aq, rl, false), is_unsigned),
        DOUBLE =>
	  process_load(rd, vaddr, mem_read(addr, 8, aq, rl, false), is_unsigned)
      }
  }
}

val maybe_aq : bool <-> string
mapping maybe_aq = {
  true  <-> ".aq",
  false <-> ""
}

val maybe_rl : bool <-> string
mapping maybe_rl = {
  true  <-> ".rl",
  false <-> ""
}

val maybe_u : bool <-> string
mapping maybe_u = {
  true  <-> "u",
  false <-> ""
}

mapping clause assembly = LOAD(imm, rs1, rd, is_unsigned, size, aq, rl)
  <-> "l" ^ size_mnemonic(size) ^ maybe_u(is_unsigned) ^ maybe_aq(aq) ^ maybe_rl(rl) ^ spc() ^ reg_name(rd) ^ sep() ^ reg_name(rs1) ^ sep() ^ hex_bits_12(imm)

/* ****************************************************************** */
union clause ast = STORE : (bits(12), regbits, regbits, word_width, bool, bool)

/* TODO: aq/rl */
mapping clause encdec = STORE(imm7 @ imm5, rs2, rs1, size, false, false)
  <-> imm7 : bits(7) @ rs2 @ rs1 @ 0b0 @ size_bits(size) @ imm5 : bits(5) @ 0b0100011

/* NOTE: Currently, we only EA if address translation is successful.
   This may need revisiting. */
function clause execute (STORE(imm, rs2, rs1, width, aq, rl)) = {
  let vaddr : xlenbits = X(rs1) + EXTS(imm);
  if   check_misaligned(vaddr, width)
  then { handle_mem_exception(vaddr, E_SAMO_Addr_Align); false }
  else match translateAddr(vaddr, Write, Data) {
    TR_Failure(e) => { handle_mem_exception(vaddr, e); false },
    TR_Address(addr) => {
      let eares : MemoryOpResult(unit) = match width {
        BYTE   => mem_write_ea(addr, 1, aq, rl, false),
        HALF   => mem_write_ea(addr, 2, aq, rl, false),
        WORD   => mem_write_ea(addr, 4, aq, rl, false),
        DOUBLE => mem_write_ea(addr, 8, aq, rl, false)
      };
      match (eares) {
        MemException(e) => { handle_mem_exception(addr, e); false },
        MemValue(_) => {
          let rs2_val = X(rs2);
          let res : MemoryOpResult(bool) = match width {
            BYTE   => mem_write_value(addr, 1, rs2_val[7..0],  aq, rl, false),
            HALF   => mem_write_value(addr, 2, rs2_val[15..0], aq, rl, false),
            WORD   => mem_write_value(addr, 4, rs2_val[31..0], aq, rl, false),
            DOUBLE => mem_write_value(addr, 8, rs2_val,        aq, rl, false)
          };
          match (res) {
            MemValue(true)     => true,
            MemValue(false)    => internal_error("store got false from mem_write_value"),
            MemException(e) => { handle_mem_exception(addr, e); false }
          }
        }
      }
    }
  }
}

mapping clause assembly = STORE(imm, rs1, rd, size, aq, rl)
  <-> "s" ^ size_mnemonic(size) ^ maybe_aq(aq) ^ maybe_rl(rl) ^ spc() ^ reg_name(rd) ^ sep() ^ reg_name(rs1) ^ sep() ^ hex_bits_12(imm)

/* ****************************************************************** */
union clause ast = ADDIW : (bits(12), regbits, regbits)

mapping clause encdec = ADDIW(imm, rs1, rd)
  <-> imm @ rs1 @ 0b000 @ rd @ 0b0011011

function clause execute (ADDIW(imm, rs1, rd)) = {
  let result : xlenbits = EXTS(imm) + X(rs1);
  X(rd) = EXTS(result[31..0]);
  true
}

mapping clause assembly = ADDIW(imm, rs1, rd)
  <-> "addiw" ^ spc() ^ reg_name(rd) ^ sep() ^ reg_name(rs1) ^ sep() ^ hex_bits_12(imm)

/* ****************************************************************** */
union clause ast = SHIFTW : (bits(5), regbits, regbits, sop)

mapping clause encdec = SHIFTW(shamt, rs1, rd, RISCV_SLLI) <-> 0b0000000 @ shamt @ rs1 @ 0b001 @ rd @ 0b0011011
mapping clause encdec = SHIFTW(shamt, rs1, rd, RISCV_SRLI) <-> 0b0000000 @ shamt @ rs1 @ 0b101 @ rd @ 0b0011011
mapping clause encdec = SHIFTW(shamt, rs1, rd, RISCV_SRAI) <-> 0b0100000 @ shamt @ rs1 @ 0b101 @ rd @ 0b0011011

function clause execute (SHIFTW(shamt, rs1, rd, op)) = {
  let rs1_val = (X(rs1))[31..0];
  let result : bits(32) = match op {
    RISCV_SLLI => rs1_val << shamt,
    RISCV_SRLI => rs1_val >> shamt,
    RISCV_SRAI => shift_right_arith32(rs1_val, shamt)
  };
  X(rd) = EXTS(result);
  true
}

mapping shiftw_mnemonic : sop <-> string = {
  RISCV_SLLI <-> "slli",
  RISCV_SRLI <-> "srli",
  RISCV_SRAI <-> "srai"
}

mapping clause assembly = SHIFTW(shamt, rs1, rd, op)
  <-> shiftw_mnemonic(op) ^ spc() ^ reg_name(rd) ^ sep() ^ reg_name(rs1) ^ sep() ^ hex_bits_5(shamt)

/* ****************************************************************** */
union clause ast = RTYPEW : (regbits, regbits, regbits, ropw)

mapping clause encdec = RTYPEW(rs2, rs1, rd, RISCV_ADDW) <-> 0b0000000 @ rs2 @ rs1 @ 0b000 @ rd @ 0b0111011
mapping clause encdec = RTYPEW(rs2, rs1, rd, RISCV_SUBW) <-> 0b0100000 @ rs2 @ rs1 @ 0b000 @ rd @ 0b0111011
mapping clause encdec = RTYPEW(rs2, rs1, rd, RISCV_SLLW) <-> 0b0000000 @ rs2 @ rs1 @ 0b001 @ rd @ 0b0111011
mapping clause encdec = RTYPEW(rs2, rs1, rd, RISCV_SRLW) <-> 0b0000000 @ rs2 @ rs1 @ 0b101 @ rd @ 0b0111011
mapping clause encdec = RTYPEW(rs2, rs1, rd, RISCV_SRAW) <-> 0b0100000 @ rs2 @ rs1 @ 0b101 @ rd @ 0b0111011

function clause execute (RTYPEW(rs2, rs1, rd, op)) = {
  let rs1_val = (X(rs1))[31..0];
  let rs2_val = (X(rs2))[31..0];
  let result : bits(32) = match op {
    RISCV_ADDW => rs1_val + rs2_val,
    RISCV_SUBW => rs1_val - rs2_val,
    RISCV_SLLW => rs1_val << (rs2_val[4..0]),
    RISCV_SRLW => rs1_val >> (rs2_val[4..0]),
    RISCV_SRAW => shift_right_arith32(rs1_val, rs2_val[4..0])
  };
  X(rd) = EXTS(result);
  true
}

mapping rtypew_mnemonic : ropw <-> string = {
  RISCV_ADDW <-> "addw",
  RISCV_SUBW <-> "subw",
  RISCV_SLLW <-> "sllw",
  RISCV_SRLW <-> "srlw",
  RISCV_SRAW <-> "sraw"
}

mapping clause assembly = RTYPEW(rs2, rs1, rd, op)
  <-> rtypew_mnemonic(op) ^ spc() ^ reg_name(rd) ^ sep() ^ reg_name(rs1) ^ sep() ^ reg_name(rs2)

/* ****************************************************************** */
union clause ast = SHIFTIWOP : (bits(5), regbits, regbits, sopw)

mapping clause encdec = SHIFTIWOP(shamt, rs1, rd, RISCV_SLLIW) <-> 0b0000000 @ shamt @ rs1 @ 0b001 @ rd @ 0b0011011
mapping clause encdec = SHIFTIWOP(shamt, rs1, rd, RISCV_SRLIW) <-> 0b0000000 @ shamt @ rs1 @ 0b101 @ rd @ 0b0011011
mapping clause encdec = SHIFTIWOP(shamt, rs1, rd, RISCV_SRAIW) <-> 0b0100000 @ shamt @ rs1 @ 0b101 @ rd @ 0b0011011

function clause execute (SHIFTIWOP(shamt, rs1, rd, op)) = {
  let rs1_val = X(rs1);
  let result : xlenbits = match op {
    RISCV_SLLIW => EXTS(rs1_val[31..0] << shamt),
    RISCV_SRLIW => EXTS(rs1_val[31..0] >> shamt),
    RISCV_SRAIW => EXTS(shift_right_arith32(rs1_val[31..0], shamt))
  };
  X(rd) = result;
  true
}

mapping shiftiwop_mnemonic : sopw <-> string = {
  RISCV_SLLIW <-> "slliw",
  RISCV_SRLIW <-> "srliw",
  RISCV_SRAIW <-> "sraiw"
}

mapping clause assembly = SHIFTIWOP(shamt, rs1, rd, op)
  <-> shiftiwop_mnemonic(op) ^ spc() ^ reg_name(rd) ^ sep() ^ reg_name(rs1) ^ hex_bits_5(shamt)

/* ****************************************************************** */
union clause ast = FENCE : (bits(4), bits(4))

mapping clause encdec = FENCE(pred, succ)
  <-> 0b0000 @ pred @ succ @ 0b00000 @ 0b000 @ 0b00000 @ 0b0001111

function clause execute (FENCE(pred, succ)) = {
  match (pred, succ) {
    (_ : bits(2) @ 0b11, _ : bits(2) @ 0b11) => MEM_fence_rw_rw(),
    (_ : bits(2) @ 0b10, _ : bits(2) @ 0b11) => MEM_fence_r_rw(),
    (_ : bits(2) @ 0b10, _ : bits(2) @ 0b10) => MEM_fence_r_r(),
    (_ : bits(2) @ 0b11, _ : bits(2) @ 0b01) => MEM_fence_rw_w(),
    (_ : bits(2) @ 0b01, _ : bits(2) @ 0b01) => MEM_fence_w_w(),
    (_ : bits(2) @ 0b01, _ : bits(2) @ 0b11) => MEM_fence_w_rw(),
    (_ : bits(2) @ 0b11, _ : bits(2) @ 0b10) => MEM_fence_rw_r(),
    (_ : bits(2) @ 0b10, _ : bits(2) @ 0b01) => MEM_fence_r_w(),
    (_ : bits(2) @ 0b01, _ : bits(2) @ 0b10) => MEM_fence_w_r(),

    (_ : bits(2) @ 0b00, _ : bits(2) @ 0b00) => (),

    _ => { print("FIXME: unsupported fence");
           () }
  };
  true
}

mapping bit_maybe_r : bits(1) <-> string = {
  0b1 <-> "r",
  0b0 <-> ""
}

mapping bit_maybe_w : bits(1) <-> string = {
  0b1 <-> "w",
  0b0 <-> ""
}

mapping bit_maybe_i : bits(1) <-> string = {
  0b1 <-> "i",
  0b0 <-> ""
}

mapping bit_maybe_o : bits(1) <-> string = {
  0b1 <-> "o",
  0b0 <-> ""
}

mapping fence_bits : bits(4) <-> string = {
  i : bits(1) @ o : bits(1) @ r : bits(1) @ w : bits(1) <-> bit_maybe_i(i) ^ bit_maybe_o(o) ^ bit_maybe_r(r) ^ bit_maybe_w(w)
}

mapping clause assembly = FENCE(pred, succ)
  <-> "fence" ^ spc() ^ fence_bits(pred) ^ sep() ^ fence_bits(succ)

/* ****************************************************************** */
union clause ast = FENCE_TSO : (bits(4), bits(4))

mapping clause encdec = FENCE_TSO(pred, succ)
  <-> 0b1000 @ pred @ succ @ 0b00000 @ 0b000 @ 0b00000 @ 0b0001111

function clause execute (FENCE_TSO(pred, succ)) = {
  match (pred, succ) {
    (_ : bits(2) @ 0b11, _ : bits(2) @ 0b11) => MEM_fence_tso(),
    (_ : bits(2) @ 0b00, _ : bits(2) @ 0b00) => (),

    _ => { print("FIXME: unsupported fence");
           () }
  };
  true
}

mapping clause assembly = FENCE_TSO(pred, succ)
  <-> "fence.tso" ^ spc() ^ fence_bits(pred) ^ sep() ^ fence_bits(succ)

/* ****************************************************************** */
union clause ast = FENCEI : unit

mapping clause encdec = FENCEI()
  <-> 0b000000000000 @ 0b00000 @ 0b001 @ 0b00000 @ 0b0001111

/* fence.i is a nop for the memory model */
function clause execute FENCEI() = { /* MEM_fence_i(); */ true }

mapping clause assembly = FENCEI() <-> "fence.i"

/* ****************************************************************** */
union clause ast = ECALL : unit

mapping clause encdec = ECALL()
  <-> 0b000000000000 @ 0b00000 @ 0b000 @ 0b00000 @ 0b1110011

function clause execute ECALL() = {
  let t : sync_exception =
    struct { trap = match (cur_privilege) {
                      User       => E_U_EnvCall,
                      Supervisor => E_S_EnvCall,
                      Machine    => E_M_EnvCall
                    },
             excinfo = (None() : option(xlenbits)) };
  nextPC = handle_exception(cur_privilege, CTL_TRAP(t), PC);
  false
}

mapping clause assembly = ECALL() <-> "ecall"

/* ****************************************************************** */
union clause ast = MRET : unit

mapping clause encdec = MRET()
  <-> 0b0011000 @ 0b00010 @ 0b00000 @ 0b000 @ 0b00000 @ 0b1110011

function clause execute MRET() = {
  if   cur_privilege == Machine
  then nextPC = handle_exception(cur_privilege, CTL_MRET(), PC)
  else handle_illegal();
  false
}

mapping clause assembly = MRET() <-> "mret"

/* ****************************************************************** */
union clause ast = SRET : unit

mapping clause encdec = SRET()
  <-> 0b0001000 @ 0b00010 @ 0b00000 @ 0b000 @ 0b00000 @ 0b1110011

function clause execute SRET() = {
  match cur_privilege {
    User       => handle_illegal(),
    Supervisor => if   (~ (haveSupMode ())) | mstatus.TSR() == true
                  then handle_illegal()
                  else nextPC = handle_exception(cur_privilege, CTL_SRET(), PC),
    Machine    => if   (~ (haveSupMode ()))
                  then handle_illegal()
                  else nextPC = handle_exception(cur_privilege, CTL_SRET(), PC)
  };
  false
}

mapping clause assembly = SRET() <-> "sret"

/* ****************************************************************** */
union clause ast = EBREAK : unit

mapping clause encdec = EBREAK()
  <-> 0b000000000001 @ 0b00000 @ 0b000 @ 0b00000 @ 0b1110011

function clause execute EBREAK() = {
  handle_mem_exception(PC, E_Breakpoint);
  false
}

mapping clause assembly = EBREAK() <-> "ebreak"

/* ****************************************************************** */
union clause ast = WFI : unit

mapping clause encdec = WFI()
  <-> 0b000100000101 @ 0b00000 @ 0b000 @ 0b00000 @ 0b1110011

function clause execute WFI() =
  match cur_privilege {
    Machine    => { platform_wfi(); true },
    Supervisor => if   mstatus.TW() == true
                  then { handle_illegal(); false }
                  else { platform_wfi(); true },
    User       => { handle_illegal(); false }
  }

mapping clause assembly = WFI() <-> "wfi"

/* ****************************************************************** */
union clause ast = SFENCE_VMA : (regbits, regbits)

mapping clause encdec = SFENCE_VMA(rs1, rs2)
  <-> 0b0001001 @ rs2 @ rs1 @ 0b000 @ 0b00000 @ 0b1110011

function clause execute SFENCE_VMA(rs1, rs2) = {
  /* TODO: handle PMP/TLB synchronization when executed in M-mode. */
  if   cur_privilege == User
  then { handle_illegal(); false }
  else match (architecture(mstatus.SXL()), mstatus.TVM()) {
    (Some(RV64), true)  => { handle_illegal(); false },
    (Some(RV64), false) => {
      let addr : option(vaddr39) = if rs1 == 0 then None() else Some(X(rs1)[38 .. 0]);
      let asid : option(asid64)  = if rs2 == 0 then None() else Some(X(rs2)[15 .. 0]);
      flushTLB(asid, addr);
      true
    },
    (_, _) => internal_error("unimplemented sfence architecture")
  }
}

mapping clause assembly = SFENCE_VMA(rs1, rs2)
  <-> "sfence.vma" ^ spc() ^ reg_name(rs1) ^ sep() ^ reg_name(rs2)

