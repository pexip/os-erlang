/*
 * %CopyrightBegin%
 *
 * Copyright Ericsson AB 2020-2021. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * %CopyrightEnd%
 */

#include "beam_asm.hpp"

extern "C"
{
#include "beam_common.h"
}

void BeamGlobalAssembler::emit_dispatch_return() {
#ifdef NATIVE_ERLANG_STACK
    /* ARG3 should contain the place to jump to. */
    a.pop(ARG3);
#else
    /* ARG3 already contains the place to jump to. */
#endif

    a.mov(x86::qword_ptr(c_p, offsetof(Process, current)), 0);
    a.mov(x86::qword_ptr(c_p, offsetof(Process, arity)), 1);
    a.jmp(labels[context_switch_simplified]);
}

void BeamModuleAssembler::emit_return() {
    Label dispatch_return = a.newLabel();

#ifdef JIT_HARD_DEBUG
    /* Validate return address and {x,0} */
    emit_validate(ArgVal(ArgVal::u, 1));
#endif

#if !defined(NATIVE_ERLANG_STACK)
    a.mov(ARG3, getCPRef());
    a.mov(getCPRef(), imm(NIL));
#endif

    /* The reduction test is kept in module code because moving it to a shared
     * fragment caused major performance regressions in dialyzer. */
    a.dec(FCALLS);
    a.short_().jl(dispatch_return);

#ifdef NATIVE_ERLANG_STACK
    a.ret();
#else
    a.jmp(ARG3);
#endif

    a.bind(dispatch_return);
    abs_jmp(ga->get_dispatch_return());
}

void BeamModuleAssembler::emit_i_call(const ArgVal &CallDest) {
    Label dest = labels[CallDest.getValue()];

    erlang_call(dest, RET);
}

void BeamModuleAssembler::emit_i_call_last(const ArgVal &CallDest,
                                           const ArgVal &Deallocate) {
    emit_deallocate(Deallocate);

    a.jmp(labels[CallDest.getValue()]);
}

void BeamModuleAssembler::emit_i_call_only(const ArgVal &CallDest) {
    a.jmp(labels[CallDest.getValue()]);
}

/* Handles save_calls. Export entry is in RET.
 *
 * When the active code index is ERTS_SAVE_CALLS_CODE_IX, all remote calls will
 * land here. */
void BeamGlobalAssembler::emit_dispatch_save_calls() {
    a.mov(TMP_MEM1q, RET);

    emit_enter_runtime();

    a.mov(ARG1, c_p);
    a.mov(ARG2, RET);
    runtime_call<2>(save_calls);

    emit_leave_runtime();

    a.mov(RET, TMP_MEM1q);

    /* Keep going with the actual code index. */
    a.mov(ARG1, imm(&the_active_code_index));
    a.mov(ARG1d, x86::dword_ptr(ARG1));

    a.jmp(emit_setup_export_call(RET, ARG1));
}

void BeamModuleAssembler::emit_i_call_ext(const ArgVal &Exp) {
    make_move_patch(RET, imports[Exp.getValue()].patches);
    x86::Mem destination = emit_setup_export_call(RET);
    erlang_call(destination, ARG1);
}

void BeamModuleAssembler::emit_i_call_ext_only(const ArgVal &Exp) {
    make_move_patch(RET, imports[Exp.getValue()].patches);
    x86::Mem destination = emit_setup_export_call(RET);
    a.jmp(destination);
}

void BeamModuleAssembler::emit_i_call_ext_last(const ArgVal &Exp,
                                               const ArgVal &Deallocate) {
    emit_deallocate(Deallocate);

    make_move_patch(RET, imports[Exp.getValue()].patches);
    x86::Mem destination = emit_setup_export_call(RET);
    a.jmp(destination);
}

static ErtsCodeMFA apply3_mfa = {am_erlang, am_apply, 3};

x86::Mem BeamModuleAssembler::emit_variable_apply(bool includeI) {
    Label dispatch = a.newLabel(), entry = a.newLabel();

    align_erlang_cp();
    a.bind(entry);

    emit_enter_runtime<Update::eReductions | Update::eStack | Update::eHeap>();

    a.mov(ARG1, c_p);
    load_x_reg_array(ARG2);

    if (includeI) {
        a.lea(ARG3, x86::qword_ptr(entry));
    } else {
        mov_imm(ARG3, 0);
    }

    mov_imm(ARG4, 0);

    runtime_call<4>(apply);

    emit_leave_runtime<Update::eReductions | Update::eStack | Update::eHeap>();

    a.test(RET, RET);
    a.short_().jne(dispatch);
    emit_handle_error(entry, &apply3_mfa);
    a.bind(dispatch);

    return emit_setup_export_call(RET);
}

void BeamModuleAssembler::emit_i_apply() {
    x86::Mem dest = emit_variable_apply(false);
    erlang_call(dest, ARG1);
}

void BeamModuleAssembler::emit_i_apply_last(const ArgVal &Deallocate) {
    emit_deallocate(Deallocate);
    emit_i_apply_only();
}

void BeamModuleAssembler::emit_i_apply_only() {
    x86::Mem dest = emit_variable_apply(true);
    a.jmp(dest);
}

x86::Mem BeamModuleAssembler::emit_fixed_apply(const ArgVal &Arity,
                                               bool includeI) {
    Label dispatch = a.newLabel(), entry = a.newLabel();

    align_erlang_cp();
    a.bind(entry);

    mov_arg(ARG3, Arity);

    emit_enter_runtime<Update::eReductions | Update::eStack | Update::eHeap>();

    a.mov(ARG1, c_p);
    load_x_reg_array(ARG2);

    if (includeI) {
        a.lea(ARG4, x86::qword_ptr(entry));
    } else {
        mov_imm(ARG4, 0);
    }

    mov_imm(ARG5, 0);

    runtime_call<5>(fixed_apply);

    emit_leave_runtime<Update::eReductions | Update::eStack | Update::eHeap>();

    a.test(RET, RET);
    a.short_().jne(dispatch);

    emit_handle_error(entry, &apply3_mfa);
    a.bind(dispatch);

    return emit_setup_export_call(RET);
}

void BeamModuleAssembler::emit_apply(const ArgVal &Arity) {
    x86::Mem dest = emit_fixed_apply(Arity, false);
    erlang_call(dest, ARG1);
}

void BeamModuleAssembler::emit_apply_last(const ArgVal &Arity,
                                          const ArgVal &Deallocate) {
    emit_deallocate(Deallocate);

    x86::Mem dest = emit_fixed_apply(Arity, true);
    a.jmp(dest);
}

x86::Gp BeamModuleAssembler::emit_apply_fun() {
    Label dispatch = a.newLabel();

    emit_enter_runtime<Update::eStack | Update::eHeap>();

    a.mov(ARG1, c_p);
    a.mov(ARG2, getXRef(0));
    a.mov(ARG3, getXRef(1));
    load_x_reg_array(ARG4);
    a.lea(ARG5, TMP_MEM1q);
    runtime_call<5>(apply_fun);

    emit_leave_runtime<Update::eStack | Update::eHeap>();

    a.mov(ARG2, RET);
    a.test(RET, RET);

    /* Put the export entry, if any, into RET to follow the export calling
     * convention in case we applied an external fun. See
     * `emit_setup_export_call` for details. */
    a.mov(RET, TMP_MEM1q);

    a.short_().jne(dispatch);
    emit_handle_error();
    a.bind(dispatch);

    return ARG2;
}

void BeamModuleAssembler::emit_i_apply_fun() {
    x86::Gp dest = emit_apply_fun();

    ASSERT(dest != ARG1);
    erlang_call(dest, ARG1);
}

void BeamModuleAssembler::emit_i_apply_fun_last(const ArgVal &Deallocate) {
    emit_deallocate(Deallocate);
    emit_i_apply_fun_only();
}

void BeamModuleAssembler::emit_i_apply_fun_only() {
    x86::Gp dest = emit_apply_fun();

    a.jmp(dest);
}

x86::Gp BeamModuleAssembler::emit_call_fun(const ArgVal &Fun) {
    Label dispatch = a.newLabel();

    mov_arg(ARG2, Fun);

    emit_enter_runtime<Update::eStack | Update::eHeap>();

    a.mov(ARG1, c_p);
    load_x_reg_array(ARG3);
    mov_imm(ARG4, THE_NON_VALUE);
    a.lea(ARG5, TMP_MEM1q);
    runtime_call<5>(call_fun);

    emit_leave_runtime<Update::eStack | Update::eHeap>();

    a.mov(ARG2, RET);
    a.test(RET, RET);

    /* Put the export entry, if any, into RET to follow the export calling
     * convention in case we called an external fun. See
     * `emit_setup_export_call` for details. */
    a.mov(RET, TMP_MEM1q);

    a.short_().jne(dispatch);
    emit_handle_error();
    a.bind(dispatch);

    return ARG2;
}

void BeamModuleAssembler::emit_i_call_fun(const ArgVal &Fun) {
    x86::Gp dest = emit_call_fun(Fun);

    ASSERT(dest != ARG1);
    erlang_call(dest, ARG1);
}

void BeamModuleAssembler::emit_i_call_fun_last(const ArgVal &Fun,
                                               const ArgVal &Deallocate) {
    emit_deallocate(Deallocate);

    x86::Gp dest = emit_call_fun(Fun);
    a.jmp(dest);
}
