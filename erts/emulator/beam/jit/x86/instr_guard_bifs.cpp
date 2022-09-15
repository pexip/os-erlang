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

#include <algorithm>
#include "beam_asm.hpp"

extern "C"
{
#include "erl_bif_table.h"
#include "big.h"
#include "beam_catches.h"
#include "beam_common.h"
#include "code_ix.h"
}

using namespace asmjit;

/*
 * We considered specializing tuple_size/1, but ultimately didn't
 * consider it worth doing.
 *
 * At the time of writing, there were 294 uses of tuple_size/1
 * in the OTP source code. (11 of them were in dialyzer.)
 *
 * The code size for the specialization was 34 bytes,
 * while the code size for the bif1 instruction was 24 bytes.
 */

void BeamGlobalAssembler::emit_handle_hd_error() {
    static ErtsCodeMFA mfa = {am_erlang, am_hd, 1};

    a.mov(getXRef(0), RET);
    a.mov(x86::qword_ptr(c_p, offsetof(Process, freason)), imm(BADARG));
    a.mov(ARG4, imm(&mfa));
    a.jmp(labels[handle_error_shared_prologue]);
}

/*
 * At the time of implementation, there were 3285 uses of hd/1 in
 * the OTP source code. Most of them were in code generated by
 * yecc.
 *
 * The code size for this specialization of hd/1 is 21 bytes,
 * while the code size for the bif1 instruction is 24 bytes.
 */
void BeamModuleAssembler::emit_bif_hd(const ArgVal &Fail,
                                      const ArgVal &Src,
                                      const ArgVal &Hd) {
    mov_arg(RET, Src);
    a.test(RETb, imm(_TAG_PRIMARY_MASK - TAG_PRIMARY_LIST));

    Uint fail = Fail.getValue();
    if (fail) {
        a.jne(labels[fail]);
    } else {
        Label next = a.newLabel();
        a.short_().je(next);
        safe_fragment_call(ga->get_handle_hd_error());
        a.bind(next);
    }

    x86::Gp boxed_ptr = emit_ptr_val(RET, RET);
    a.mov(ARG2, getCARRef(boxed_ptr));
    mov_arg(Hd, ARG2);
}

void BeamGlobalAssembler::emit_handle_element_error() {
    static ErtsCodeMFA mfa = {am_erlang, am_element, 2};

    a.mov(getXRef(0), ARG1);
    a.mov(getXRef(1), ARG2);
    a.mov(x86::qword_ptr(c_p, offsetof(Process, freason)), imm(BADARG));
    a.mov(ARG4, imm(&mfa));
    a.jmp(labels[handle_error_shared_prologue]);
}

/*
 * ARG1 = Position (1-based)
 * ARG2 = Tuple
 * ARG3 = 0 if if in body, otherwise address of failure label.
 *
 * Will return with a value in RET only if the element operation succeeds.
 */
void BeamGlobalAssembler::emit_bif_element_shared() {
    Label error = a.newLabel();

    a.mov(RETd, ARG1d);
    a.and_(RETb, imm(_TAG_IMMED1_MASK));
    a.cmp(RETb, imm(_TAG_IMMED1_SMALL));
    a.short_().jne(error);

    a.mov(ARG4, ARG1);
    a.sar(ARG4, imm(_TAG_IMMED1_SIZE));

    emit_is_boxed(error, ARG2, dShort);

    a.mov(ARG5, ARG2);
    (void)emit_ptr_val(ARG5, ARG5);
    a.lea(ARG5, emit_boxed_val(ARG5));
    a.mov(ARG6, x86::qword_ptr(ARG5));
    a.mov(RETd, ARG6d);
    ERTS_CT_ASSERT(make_arityval(0) == 0);
    a.and_(RETb, imm(_TAG_HEADER_MASK));
    a.short_().jne(error);

    a.shr(ARG6, imm(_HEADER_ARITY_OFFS));
    a.dec(ARG4);
    a.cmp(ARG6, ARG4);
    a.short_().jbe(error);

    a.inc(ARG4);
    a.mov(RET, x86::qword_ptr(ARG5, ARG4, 3));
    a.test(RETd, RETd);
    a.ret();

    a.bind(error);
    {
        Label exception = a.newLabel();

        a.test(ARG3, ARG3);
        a.short_().je(exception);
        emit_discard_cp();
        a.jmp(ARG3);

        a.bind(exception);
        a.jmp(labels[handle_element_error]);
    }
}

/*
 * At the time of implementation, there were 3678 uses of element/2 in
 * the OTP source code. 3137 of those uses had a literal first argument
 * (the position in the tuple), while 540 uses had a varible first
 * argument. Calls to element/2 (with a literal first argument) is
 * especially common in code generated by yecc.
 */
void BeamModuleAssembler::emit_bif_element(const ArgVal &Fail,
                                           const ArgVal &Pos,
                                           const ArgVal &Tuple,
                                           const ArgVal &Dst) {
    bool const_position;

    const_position = Pos.getType() == ArgVal::i && is_small(Pos.getValue()) &&
                     signed_val(Pos.getValue()) > 0 &&
                     signed_val(Pos.getValue()) <= (Sint)MAX_ARITYVAL;

    if (const_position) {
        /* The position is a valid small integer. Inline the code.
         *
         * The size of the code is 40 bytes, while the size of the bif2
         * instruction is 36 bytes. */
        Uint position = signed_val(Pos.getValue());
        Label error;

        mov_arg(ARG2, Tuple);

        if (Fail.getValue() == 0) {
            error = a.newLabel();

            emit_is_boxed(error, ARG2, dShort);
        } else {
            emit_is_boxed(labels[Fail.getValue()], ARG2);
        }

        x86::Gp boxed_ptr = emit_ptr_val(ARG3, ARG2);
        a.mov(RETd, emit_boxed_val(boxed_ptr, 0, sizeof(Uint32)));

        ERTS_CT_ASSERT(Support::isInt32(make_arityval(MAX_ARITYVAL)));
        a.cmp(RETd, imm(make_arityval(position)));

        if (Fail.getValue() == 0) {
            a.short_().jb(error);
        } else {
            a.jb(labels[Fail.getValue()]);
        }

        ERTS_CT_ASSERT(make_arityval(0) == 0);
        a.and_(RETb, imm(_TAG_HEADER_MASK));

        if (Fail.getValue() == 0) {
            Label next = a.newLabel();

            a.short_().je(next);

            a.bind(error);
            {
                mov_imm(ARG1, make_small(position));
                safe_fragment_call(ga->get_handle_element_error());
            }

            a.bind(next);
        } else {
            a.jne(labels[Fail.getValue()]);
        }

        a.mov(RET, emit_boxed_val(boxed_ptr, position * sizeof(Eterm)));
    } else {
        /* The code is too large to inline. Call a shared fragment.
         *
         * The size of the code that calls the shared fragment is 19 bytes,
         * while the size of the bif2 instruction is 36 bytes. */
        mov_arg(ARG2, Tuple);
        mov_arg(ARG1, Pos);

        if (Fail.getValue() != 0) {
            a.lea(ARG3, x86::qword_ptr(labels[Fail.getValue()]));
        } else {
            mov_imm(ARG3, 0);
        }

        safe_fragment_call(ga->get_bif_element_shared());
    }

    mov_arg(Dst, RET);
}
