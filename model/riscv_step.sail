/* The emulator fetch-execute-interrupt dispatch loop. */

union FetchResult = {
  F_Base  : word,                      /* Base ISA */
  F_RVC   : half,                      /* Compressed ISA */
  F_Error : (ExceptionType, xlenbits)  /* exception and PC */
}

function isRVC(h : half) -> bool =
 ~ (h[1 .. 0] == 0b11)

val fetch : unit -> FetchResult effect {escape, rmem, rreg, wmv, wreg}
function fetch() -> FetchResult =
  /* check for legal PC */
  if (PC[0] != 0b0 | (PC[1] != 0b0 & (~ (haveRVC()))))
  then F_Error(E_Fetch_Addr_Align, PC)
  else match translateAddr(PC, Execute, Instruction) {
    TR_Failure(e)  => F_Error(e, PC),
    TR_Address(ppclo) => {
      /* split instruction fetch into 16-bit granules to handle RVC, as
       * well as to generate precise fault addresses in any fetch
       * exceptions.
       */
      match checked_mem_read(Instruction, ppclo, 2, false, false, false) {
        MemException(e) => F_Error(E_Fetch_Access_Fault, PC),
        MemValue(ilo) => {
          if isRVC(ilo) then F_RVC(ilo)
          else {
            PChi : xlenbits = PC + 2;
            match translateAddr(PChi, Execute, Instruction) {
              TR_Failure(e) => F_Error(e, PChi),
              TR_Address(ppchi) => {
                match checked_mem_read(Instruction, ppchi, 2, false, false, false) {
                  MemException(e) => F_Error(E_Fetch_Access_Fault, PChi),
                  MemValue(ihi) => F_Base(append(ihi, ilo))
                }
              }
            }
          }
        }
      }
    }
  }

/* returns whether to increment the step count in the trace */
val step : int -> bool effect {barr, eamem, escape, exmem, rmem, rreg, wmv, wreg}
function step(step_no) = {
  minstret_written = false;     /* see note for minstret */
  let (retired, stepped) : (bool, bool) =
    match dispatchInterrupt(cur_privilege) {
      Some(intr, priv) => {
        print_bits("Handling interrupt: ", intr);
        handle_interrupt(intr, priv);
        (false, false)
      },
      None() => {
        match fetch() {
          F_Error(e, addr) => {
            handle_mem_exception(addr, e);
            (false, false)
          },
          F_RVC(h) => {
            match decodeCompressed(h) {
              None() => {
                print_instr("[" ^ string_of_int(step_no) ^ "] [" ^ cur_privilege ^ "]: " ^ BitStr(PC) ^ " (" ^ BitStr(h) ^ ") <no-decode>");
                instbits = EXTZ(h);
                handle_illegal();
                (false, true)
              },
              Some(ast) => {
                print_instr("[" ^ string_of_int(step_no) ^ "] [" ^ cur_privilege ^ "]: " ^ BitStr(PC) ^ " (" ^ BitStr(h) ^ ") " ^ ast);
		/* check for RVC once here instead of every RVC execute clause. */
		if haveRVC() then {
                  nextPC = PC + 2;
                  (execute(ast), true)
		} else {
		  (false, true)
		}
              }
            }
          },
          F_Base(w) => {
            match decode(w) {
              None() => {
                print_instr("[" ^ string_of_int(step_no) ^ "] [" ^ cur_privilege ^ "]: " ^ BitStr(PC) ^ " (" ^ BitStr(w) ^ ") <no-decode>");
                instbits = EXTZ(w);
                handle_illegal();
                (false, true)
              },
              Some(ast) => {
                print_instr("[" ^ string_of_int(step_no) ^ "] [" ^ cur_privilege ^ "]: " ^ BitStr(PC) ^ " (" ^ BitStr(w) ^ ") " ^ ast);
                nextPC = PC + 4;
                (execute(ast), true)
              }
            }
          }
        }
      }
    };
  PC = nextPC;
  if retired then retire_instruction();
  stepped
}

val loop : unit -> unit effect {barr, eamem, escape, exmem, rmem, rreg, wmv, wreg}
function loop () = {
  let insns_per_tick = plat_insns_per_tick();
  i : int = 0;
  step_no : int = 0;
  while (~ (htif_done)) do {
    let stepped = step(step_no);
    if stepped then step_no = step_no + 1;

    /* check htif exit */
    if htif_done then {
      let exit_val = unsigned(htif_exit_code);
      if exit_val == 0 then print("SUCCESS")
      else print_int("FAILURE: ", exit_val);
    } else {
      /* update time */
      i = i + 1;
      if i == insns_per_tick then {
        tick_clock();
        /* for now, we drive the platform i/o at every clock tick. */
        tick_platform();
        i = 0;
      }
    }
  }
}
