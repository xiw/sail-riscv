/* *******************************************************************  */
/* This file specifies some internal pseudo instructions used by RMEM. */

/* ****************************************************************** */

union clause ast = STOP_FETCHING : unit

/* RMEM stop fetching sentinel, using RISCV encoding space custom-0 */
mapping clause encdec = STOP_FETCHING()
  <-> 0xfade @ 0b00000000 @ 0b0 @ 0b00 @ 0b010 @ 0b11

function clause execute (STOP_FETCHING()) = true

mapping clause assembly = STOP_FETCHING() <-> "stop_fetching"

union clause ast = THREAD_START : unit

/* RMEM thread start sentinel, using RISCV encoding space custom-0 */
mapping clause encdec = THREAD_START()
  <-> 0xc0de @ 0b00000000 @ 0b0 @ 0b00 @ 0b010 @ 0b11

function clause execute (THREAD_START()) = true

mapping clause assembly = THREAD_START() <-> "thread_start"
