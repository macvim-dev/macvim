/* vi:set ts=8 sts=4 sw=4 noet:
 *
 * VIM - Vi IMproved	by Bram Moolenaar
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

/*
 * vim9instr.c: Dealing with instructions of a compiled function
 */

#define USING_FLOAT_STUFF
#include "vim.h"

#if defined(FEAT_EVAL) || defined(PROTO)

// When not generating protos this is included in proto.h
#ifdef PROTO
# include "vim9.h"
#endif


/////////////////////////////////////////////////////////////////////
// Following generate_ functions expect the caller to call ga_grow().

#define RETURN_NULL_IF_SKIP(cctx) if (cctx->ctx_skip == SKIP_YES) return NULL
#define RETURN_OK_IF_SKIP(cctx) if (cctx->ctx_skip == SKIP_YES) return OK

/*
 * Generate an instruction without arguments.
 * Returns a pointer to the new instruction, NULL if failed.
 */
    isn_T *
generate_instr(cctx_T *cctx, isntype_T isn_type)
{
    garray_T	*instr = &cctx->ctx_instr;
    isn_T	*isn;

    RETURN_NULL_IF_SKIP(cctx);
    if (GA_GROW_FAILS(instr, 1))
	return NULL;
    isn = ((isn_T *)instr->ga_data) + instr->ga_len;
    isn->isn_type = isn_type;
    isn->isn_lnum = cctx->ctx_lnum + 1;
    ++instr->ga_len;

    return isn;
}

/*
 * Generate an instruction without arguments.
 * "drop" will be removed from the stack.
 * Returns a pointer to the new instruction, NULL if failed.
 */
    isn_T *
generate_instr_drop(cctx_T *cctx, isntype_T isn_type, int drop)
{
    RETURN_NULL_IF_SKIP(cctx);
    cctx->ctx_type_stack.ga_len -= drop;
    return generate_instr(cctx, isn_type);
}

/*
 * Generate instruction "isn_type" and put "type" on the type stack,
 * use "decl_type" for the declared type.
 */
    static isn_T *
generate_instr_type2(
	cctx_T	    *cctx,
	isntype_T   isn_type,
	type_T	    *type,
	type_T	    *decl_type)
{
    isn_T	*isn;

    if ((isn = generate_instr(cctx, isn_type)) == NULL)
	return NULL;

    if (push_type_stack2(cctx, type == NULL ? &t_any : type,
			       decl_type == NULL ? &t_any : decl_type) == FAIL)
	return NULL;

    return isn;
}

/*
 * Generate instruction "isn_type" and put "type" on the type stack.
 * Uses "any" for the declared type, which works for constants.  For declared
 * variables use generate_instr_type2().
 */
    isn_T *
generate_instr_type(cctx_T *cctx, isntype_T isn_type, type_T *type)
{
    return generate_instr_type2(cctx, isn_type, type, &t_any);
}

/*
 * Generate an ISN_DEBUG instruction.
 */
    isn_T *
generate_instr_debug(cctx_T *cctx)
{
    isn_T	*isn;
    dfunc_T	*dfunc = ((dfunc_T *)def_functions.ga_data)
					       + cctx->ctx_ufunc->uf_dfunc_idx;

    if ((isn = generate_instr(cctx, ISN_DEBUG)) == NULL)
	return NULL;
    isn->isn_arg.debug.dbg_var_names_len = dfunc->df_var_names.ga_len;
    isn->isn_arg.debug.dbg_break_lnum = cctx->ctx_prev_lnum;
    return isn;
}

/*
 * If type at "offset" isn't already VAR_STRING then generate ISN_2STRING.
 * But only for simple types.
 * When "tolerant" is TRUE convert most types to string, e.g. a List.
 */
    int
may_generate_2STRING(int offset, int tolerant, cctx_T *cctx)
{
    isn_T	*isn;
    isntype_T	isntype = ISN_2STRING;
    type_T	*type;

    RETURN_OK_IF_SKIP(cctx);
    type = get_type_on_stack(cctx, -1 - offset);
    switch (type->tt_type)
    {
	// nothing to be done
	case VAR_STRING: return OK;

	// conversion possible
	case VAR_SPECIAL:
	case VAR_BOOL:
	case VAR_NUMBER:
	case VAR_FLOAT:
			 break;

	// conversion possible (with runtime check)
	case VAR_ANY:
	case VAR_UNKNOWN:
			 isntype = ISN_2STRING_ANY;
			 break;

	// conversion possible when tolerant
	case VAR_LIST:
			 if (tolerant)
			 {
			     isntype = ISN_2STRING_ANY;
			     break;
			 }
			 // FALLTHROUGH

	// conversion not possible
	case VAR_VOID:
	case VAR_BLOB:
	case VAR_FUNC:
	case VAR_PARTIAL:
	case VAR_DICT:
	case VAR_JOB:
	case VAR_CHANNEL:
	case VAR_INSTR:
			 to_string_error(type->tt_type);
			 return FAIL;
    }

    set_type_on_stack(cctx, &t_string, -1 - offset);
    if ((isn = generate_instr(cctx, isntype)) == NULL)
	return FAIL;
    isn->isn_arg.tostring.offset = offset;
    isn->isn_arg.tostring.tolerant = tolerant;

    return OK;
}

    static int
check_number_or_float(vartype_T type1, vartype_T type2, char_u *op)
{
    if (!((type1 == VAR_NUMBER || type1 == VAR_FLOAT
				   || type1 == VAR_ANY || type1 == VAR_UNKNOWN)
	    && (type2 == VAR_NUMBER || type2 == VAR_FLOAT
				 || type2 == VAR_ANY || type2 == VAR_UNKNOWN)))
    {
	if (*op == '+')
	    emsg(_(e_wrong_argument_type_for_plus));
	else
	    semsg(_(e_char_requires_number_or_float_arguments), *op);
	return FAIL;
    }
    return OK;
}

/*
 * Generate instruction for "+".  For a list this creates a new list.
 */
    int
generate_add_instr(
	cctx_T *cctx,
	vartype_T vartype,
	type_T *type1,
	type_T *type2,
	exprtype_T expr_type)
{
    isn_T	*isn = generate_instr_drop(cctx,
		      vartype == VAR_NUMBER ? ISN_OPNR
		    : vartype == VAR_LIST ? ISN_ADDLIST
		    : vartype == VAR_BLOB ? ISN_ADDBLOB
#ifdef FEAT_FLOAT
		    : vartype == VAR_FLOAT ? ISN_OPFLOAT
#endif
		    : ISN_OPANY, 1);

    if (vartype != VAR_LIST && vartype != VAR_BLOB
	    && type1->tt_type != VAR_ANY
	    && type1->tt_type != VAR_UNKNOWN
	    && type2->tt_type != VAR_ANY
	    && type2->tt_type != VAR_UNKNOWN
	    && check_number_or_float(
			type1->tt_type, type2->tt_type, (char_u *)"+") == FAIL)
	return FAIL;

    if (isn != NULL)
    {
	if (isn->isn_type == ISN_ADDLIST)
	    isn->isn_arg.op.op_type = expr_type;
	else
	    isn->isn_arg.op.op_type = EXPR_ADD;
    }

    // When concatenating two lists with different member types the member type
    // becomes "any".
    if (vartype == VAR_LIST
	    && type1->tt_type == VAR_LIST && type2->tt_type == VAR_LIST
	    && type1->tt_member != type2->tt_member)
	set_type_on_stack(cctx, &t_list_any, 0);

    return isn == NULL ? FAIL : OK;
}

/*
 * Get the type to use for an instruction for an operation on "type1" and
 * "type2".  If they are matching use a type-specific instruction. Otherwise
 * fall back to runtime type checking.
 */
    vartype_T
operator_type(type_T *type1, type_T *type2)
{
    if (type1->tt_type == type2->tt_type
	    && (type1->tt_type == VAR_NUMBER
		|| type1->tt_type == VAR_LIST
#ifdef FEAT_FLOAT
		|| type1->tt_type == VAR_FLOAT
#endif
		|| type1->tt_type == VAR_BLOB))
	return type1->tt_type;
    return VAR_ANY;
}

/*
 * Generate an instruction with two arguments.  The instruction depends on the
 * type of the arguments.
 */
    int
generate_two_op(cctx_T *cctx, char_u *op)
{
    type_T	*type1;
    type_T	*type2;
    vartype_T	vartype;
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);

    // Get the known type of the two items on the stack.
    type1 = get_type_on_stack(cctx, 1);
    type2 = get_type_on_stack(cctx, 0);
    vartype = operator_type(type1, type2);

    switch (*op)
    {
	case '+':
		  if (generate_add_instr(cctx, vartype, type1, type2,
							    EXPR_COPY) == FAIL)
		      return FAIL;
		  break;

	case '-':
	case '*':
	case '/': if (check_number_or_float(type1->tt_type, type2->tt_type,
								   op) == FAIL)
		      return FAIL;
		  if (vartype == VAR_NUMBER)
		      isn = generate_instr_drop(cctx, ISN_OPNR, 1);
#ifdef FEAT_FLOAT
		  else if (vartype == VAR_FLOAT)
		      isn = generate_instr_drop(cctx, ISN_OPFLOAT, 1);
#endif
		  else
		      isn = generate_instr_drop(cctx, ISN_OPANY, 1);
		  if (isn != NULL)
		      isn->isn_arg.op.op_type = *op == '*'
				 ? EXPR_MULT : *op == '/'? EXPR_DIV : EXPR_SUB;
		  break;

	case '%': if ((type1->tt_type != VAR_ANY
			      && type1->tt_type != VAR_UNKNOWN
					       && type1->tt_type != VAR_NUMBER)
			  || (type2->tt_type != VAR_ANY
			      && type2->tt_type != VAR_UNKNOWN
					      && type2->tt_type != VAR_NUMBER))
		  {
		      emsg(_(e_percent_requires_number_arguments));
		      return FAIL;
		  }
		  isn = generate_instr_drop(cctx,
			      vartype == VAR_NUMBER ? ISN_OPNR : ISN_OPANY, 1);
		  if (isn != NULL)
		      isn->isn_arg.op.op_type = EXPR_REM;
		  break;
    }

    // correct type of result
    if (vartype == VAR_ANY)
    {
	type_T *type = &t_any;

#ifdef FEAT_FLOAT
	// float+number and number+float results in float
	if ((type1->tt_type == VAR_NUMBER || type1->tt_type == VAR_FLOAT)
		&& (type2->tt_type == VAR_NUMBER || type2->tt_type == VAR_FLOAT))
	    type = &t_float;
#endif
	set_type_on_stack(cctx, type, 0);
    }

    return OK;
}

/*
 * Get the instruction to use for comparing "type1" with "type2"
 * Return ISN_DROP when failed.
 */
    static isntype_T
get_compare_isn(exprtype_T exprtype, vartype_T type1, vartype_T type2)
{
    isntype_T	isntype = ISN_DROP;

    if (type1 == VAR_UNKNOWN)
	type1 = VAR_ANY;
    if (type2 == VAR_UNKNOWN)
	type2 = VAR_ANY;

    if (type1 == type2)
    {
	switch (type1)
	{
	    case VAR_BOOL: isntype = ISN_COMPAREBOOL; break;
	    case VAR_SPECIAL: isntype = ISN_COMPARESPECIAL; break;
	    case VAR_NUMBER: isntype = ISN_COMPARENR; break;
	    case VAR_FLOAT: isntype = ISN_COMPAREFLOAT; break;
	    case VAR_STRING: isntype = ISN_COMPARESTRING; break;
	    case VAR_BLOB: isntype = ISN_COMPAREBLOB; break;
	    case VAR_LIST: isntype = ISN_COMPARELIST; break;
	    case VAR_DICT: isntype = ISN_COMPAREDICT; break;
	    case VAR_FUNC: isntype = ISN_COMPAREFUNC; break;
	    default: isntype = ISN_COMPAREANY; break;
	}
    }
    else if (type1 == VAR_ANY || type2 == VAR_ANY
	    || ((type1 == VAR_NUMBER || type1 == VAR_FLOAT)
	      && (type2 == VAR_NUMBER || type2 == VAR_FLOAT)))
	isntype = ISN_COMPAREANY;

    if ((exprtype == EXPR_IS || exprtype == EXPR_ISNOT)
	    && (isntype == ISN_COMPAREBOOL
	    || isntype == ISN_COMPARESPECIAL
	    || isntype == ISN_COMPARENR
	    || isntype == ISN_COMPAREFLOAT))
    {
	semsg(_(e_cannot_use_str_with_str),
		exprtype == EXPR_IS ? "is" : "isnot" , vartype_name(type1));
	return ISN_DROP;
    }
    if (isntype == ISN_DROP
	    || ((exprtype != EXPR_EQUAL && exprtype != EXPR_NEQUAL
		    && (type1 == VAR_BOOL || type1 == VAR_SPECIAL
		       || type2 == VAR_BOOL || type2 == VAR_SPECIAL)))
	    || ((exprtype != EXPR_EQUAL && exprtype != EXPR_NEQUAL
				 && exprtype != EXPR_IS && exprtype != EXPR_ISNOT
		    && (type1 == VAR_BLOB || type2 == VAR_BLOB
			|| type1 == VAR_LIST || type2 == VAR_LIST))))
    {
	semsg(_(e_cannot_compare_str_with_str),
		vartype_name(type1), vartype_name(type2));
	return ISN_DROP;
    }
    return isntype;
}

    int
check_compare_types(exprtype_T type, typval_T *tv1, typval_T *tv2)
{
    if (get_compare_isn(type, tv1->v_type, tv2->v_type) == ISN_DROP)
	return FAIL;
    return OK;
}

/*
 * Generate an ISN_COMPARE* instruction with a boolean result.
 */
    int
generate_COMPARE(cctx_T *cctx, exprtype_T exprtype, int ic)
{
    isntype_T	isntype;
    isn_T	*isn;
    garray_T	*stack = &cctx->ctx_type_stack;
    vartype_T	type1;
    vartype_T	type2;

    RETURN_OK_IF_SKIP(cctx);

    // Get the known type of the two items on the stack.  If they are matching
    // use a type-specific instruction. Otherwise fall back to runtime type
    // checking.
    type1 = get_type_on_stack(cctx, 1)->tt_type;
    type2 = get_type_on_stack(cctx, 0)->tt_type;
    isntype = get_compare_isn(exprtype, type1, type2);
    if (isntype == ISN_DROP)
	return FAIL;

    if ((isn = generate_instr(cctx, isntype)) == NULL)
	return FAIL;
    isn->isn_arg.op.op_type = exprtype;
    isn->isn_arg.op.op_ic = ic;

    // takes two arguments, puts one bool back
    if (stack->ga_len >= 2)
    {
	--stack->ga_len;
	set_type_on_stack(cctx, &t_bool, 0);
    }

    return OK;
}

/*
 * Generate an ISN_2BOOL instruction.
 * "offset" is the offset in the type stack.
 */
    int
generate_2BOOL(cctx_T *cctx, int invert, int offset)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr(cctx, ISN_2BOOL)) == NULL)
	return FAIL;
    isn->isn_arg.tobool.invert = invert;
    isn->isn_arg.tobool.offset = offset;

    // type becomes bool
    set_type_on_stack(cctx, &t_bool, -1 - offset);

    return OK;
}

/*
 * Generate an ISN_COND2BOOL instruction.
 */
    int
generate_COND2BOOL(cctx_T *cctx)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr(cctx, ISN_COND2BOOL)) == NULL)
	return FAIL;

    // type becomes bool
    set_type_on_stack(cctx, &t_bool, 0);

    return OK;
}

    int
generate_TYPECHECK(
	cctx_T	    *cctx,
	type_T	    *expected,
	int	    offset,
	int	    argidx)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr(cctx, ISN_CHECKTYPE)) == NULL)
	return FAIL;
    isn->isn_arg.type.ct_type = alloc_type(expected);
    isn->isn_arg.type.ct_off = (int8_T)offset;
    isn->isn_arg.type.ct_arg_idx = (int8_T)argidx;

    // type becomes expected
    set_type_on_stack(cctx, expected, -1 - offset);

    return OK;
}

    int
generate_SETTYPE(
	cctx_T	    *cctx,
	type_T	    *expected)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr(cctx, ISN_SETTYPE)) == NULL)
	return FAIL;
    isn->isn_arg.type.ct_type = alloc_type(expected);
    return OK;
}

/*
 * Generate a PUSH instruction for "tv".
 * "tv" will be consumed or cleared.
 * Nothing happens if "tv" is NULL or of type VAR_UNKNOWN;
 */
    int
generate_tv_PUSH(cctx_T *cctx, typval_T *tv)
{
    if (tv != NULL)
    {
	switch (tv->v_type)
	{
	    case VAR_UNKNOWN:
		break;
	    case VAR_BOOL:
		generate_PUSHBOOL(cctx, tv->vval.v_number);
		break;
	    case VAR_SPECIAL:
		generate_PUSHSPEC(cctx, tv->vval.v_number);
		break;
	    case VAR_NUMBER:
		generate_PUSHNR(cctx, tv->vval.v_number);
		break;
#ifdef FEAT_FLOAT
	    case VAR_FLOAT:
		generate_PUSHF(cctx, tv->vval.v_float);
		break;
#endif
	    case VAR_BLOB:
		generate_PUSHBLOB(cctx, tv->vval.v_blob);
		tv->vval.v_blob = NULL;
		break;
	    case VAR_STRING:
		generate_PUSHS(cctx, &tv->vval.v_string);
		tv->vval.v_string = NULL;
		break;
	    default:
		iemsg("constant type not supported");
		clear_tv(tv);
		return FAIL;
	}
	tv->v_type = VAR_UNKNOWN;
    }
    return OK;
}

/*
 * Generate an ISN_PUSHNR instruction.
 */
    int
generate_PUSHNR(cctx_T *cctx, varnumber_T number)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr_type(cctx, ISN_PUSHNR, &t_number)) == NULL)
	return FAIL;
    isn->isn_arg.number = number;

    if (number == 0 || number == 1)
	// A 0 or 1 number can also be used as a bool.
	set_type_on_stack(cctx, &t_number_bool, 0);
    return OK;
}

/*
 * Generate an ISN_PUSHBOOL instruction.
 */
    int
generate_PUSHBOOL(cctx_T *cctx, varnumber_T number)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr_type(cctx, ISN_PUSHBOOL, &t_bool)) == NULL)
	return FAIL;
    isn->isn_arg.number = number;

    return OK;
}

/*
 * Generate an ISN_PUSHSPEC instruction.
 */
    int
generate_PUSHSPEC(cctx_T *cctx, varnumber_T number)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr_type(cctx, ISN_PUSHSPEC, &t_special)) == NULL)
	return FAIL;
    isn->isn_arg.number = number;

    return OK;
}

#if defined(FEAT_FLOAT) || defined(PROTO)
/*
 * Generate an ISN_PUSHF instruction.
 */
    int
generate_PUSHF(cctx_T *cctx, float_T fnumber)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr_type(cctx, ISN_PUSHF, &t_float)) == NULL)
	return FAIL;
    isn->isn_arg.fnumber = fnumber;

    return OK;
}
#endif

/*
 * Generate an ISN_PUSHS instruction.
 * Consumes "*str".  When freed *str is set to NULL, unless "str" is NULL.
 */
    int
generate_PUSHS(cctx_T *cctx, char_u **str)
{
    isn_T	*isn;

    if (cctx->ctx_skip == SKIP_YES)
    {
	if (str != NULL)
	    VIM_CLEAR(*str);
	return OK;
    }
    if ((isn = generate_instr_type(cctx, ISN_PUSHS, &t_string)) == NULL)
    {
	if (str != NULL)
	    VIM_CLEAR(*str);
	return FAIL;
    }
    isn->isn_arg.string = str == NULL ? NULL : *str;

    return OK;
}

/*
 * Generate an ISN_PUSHCHANNEL instruction.
 * Consumes "channel".
 */
    int
generate_PUSHCHANNEL(cctx_T *cctx, channel_T *channel)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr_type(cctx, ISN_PUSHCHANNEL, &t_channel)) == NULL)
	return FAIL;
    isn->isn_arg.channel = channel;

    return OK;
}

/*
 * Generate an ISN_PUSHJOB instruction.
 * Consumes "job".
 */
    int
generate_PUSHJOB(cctx_T *cctx, job_T *job)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr_type(cctx, ISN_PUSHJOB, &t_channel)) == NULL)
	return FAIL;
    isn->isn_arg.job = job;

    return OK;
}

/*
 * Generate an ISN_PUSHBLOB instruction.
 * Consumes "blob".
 */
    int
generate_PUSHBLOB(cctx_T *cctx, blob_T *blob)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr_type(cctx, ISN_PUSHBLOB, &t_blob)) == NULL)
	return FAIL;
    isn->isn_arg.blob = blob;

    return OK;
}

/*
 * Generate an ISN_PUSHFUNC instruction with name "name".
 */
    int
generate_PUSHFUNC(cctx_T *cctx, char_u *name, type_T *type)
{
    isn_T	*isn;
    char_u	*funcname;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr_type(cctx, ISN_PUSHFUNC, type)) == NULL)
	return FAIL;
    if (name == NULL)
	funcname = NULL;
    else if (*name == K_SPECIAL				    // script-local
	    || vim_strchr(name, AUTOLOAD_CHAR) != NULL)	    // autoload
	funcname = vim_strsave(name);
    else
    {
	funcname = alloc(STRLEN(name) + 3);
	if (funcname != NULL)
	{
	    STRCPY(funcname, "g:");
	    STRCPY(funcname + 2, name);
	}
    }

    isn->isn_arg.string = funcname;
    return OK;
}

/*
 * Generate an ISN_AUTOLOAD instruction.
 */
    int
generate_AUTOLOAD(cctx_T *cctx, char_u *name, type_T *type)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr_type(cctx, ISN_AUTOLOAD, type)) == NULL)
	return FAIL;
    isn->isn_arg.string = vim_strsave(name);
    if (isn->isn_arg.string == NULL)
	return FAIL;
    return OK;
}

/*
 * Generate an ISN_GETITEM instruction with "index".
 * "with_op" is TRUE for "+=" and other operators, the stack has the current
 * value below the list with values.
 */
    int
generate_GETITEM(cctx_T *cctx, int index, int with_op)
{
    isn_T	*isn;
    type_T	*type = get_type_on_stack(cctx, with_op ? 1 : 0);
    type_T	*item_type = &t_any;

    RETURN_OK_IF_SKIP(cctx);

    if (type->tt_type != VAR_LIST)
    {
	// cannot happen, caller has checked the type
	emsg(_(e_list_required));
	return FAIL;
    }
    item_type = type->tt_member;
    if ((isn = generate_instr(cctx, ISN_GETITEM)) == NULL)
	return FAIL;
    isn->isn_arg.getitem.gi_index = index;
    isn->isn_arg.getitem.gi_with_op = with_op;

    // add the item type to the type stack
    return push_type_stack(cctx, item_type);
}

/*
 * Generate an ISN_SLICE instruction with "count".
 */
    int
generate_SLICE(cctx_T *cctx, int count)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr(cctx, ISN_SLICE)) == NULL)
	return FAIL;
    isn->isn_arg.number = count;
    return OK;
}

/*
 * Generate an ISN_CHECKLEN instruction with "min_len".
 */
    int
generate_CHECKLEN(cctx_T *cctx, int min_len, int more_OK)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);

    if ((isn = generate_instr(cctx, ISN_CHECKLEN)) == NULL)
	return FAIL;
    isn->isn_arg.checklen.cl_min_len = min_len;
    isn->isn_arg.checklen.cl_more_OK = more_OK;

    return OK;
}

/*
 * Generate an ISN_STORE instruction.
 */
    int
generate_STORE(cctx_T *cctx, isntype_T isn_type, int idx, char_u *name)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr_drop(cctx, isn_type, 1)) == NULL)
	return FAIL;
    if (name != NULL)
	isn->isn_arg.string = vim_strsave(name);
    else
	isn->isn_arg.number = idx;

    return OK;
}

/*
 * Generate an ISN_STOREOUTER instruction.
 */
    static int
generate_STOREOUTER(cctx_T *cctx, int idx, int level)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr_drop(cctx, ISN_STOREOUTER, 1)) == NULL)
	return FAIL;
    isn->isn_arg.outer.outer_idx = idx;
    isn->isn_arg.outer.outer_depth = level;

    return OK;
}

/*
 * Generate an ISN_STORENR instruction (short for ISN_PUSHNR + ISN_STORE)
 */
    int
generate_STORENR(cctx_T *cctx, int idx, varnumber_T value)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr(cctx, ISN_STORENR)) == NULL)
	return FAIL;
    isn->isn_arg.storenr.stnr_idx = idx;
    isn->isn_arg.storenr.stnr_val = value;

    return OK;
}

/*
 * Generate an ISN_STOREOPT or ISN_STOREFUNCOPT instruction
 */
    static int
generate_STOREOPT(
	cctx_T	    *cctx,
	isntype_T   isn_type,
	char_u	    *name,
	int	    opt_flags)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr_drop(cctx, isn_type, 1)) == NULL)
	return FAIL;
    isn->isn_arg.storeopt.so_name = vim_strsave(name);
    isn->isn_arg.storeopt.so_flags = opt_flags;

    return OK;
}

/*
 * Generate an ISN_LOAD or similar instruction.
 */
    int
generate_LOAD(
	cctx_T	    *cctx,
	isntype_T   isn_type,
	int	    idx,
	char_u	    *name,
	type_T	    *type)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr_type2(cctx, isn_type, type, type)) == NULL)
	return FAIL;
    if (name != NULL)
	isn->isn_arg.string = vim_strsave(name);
    else
	isn->isn_arg.number = idx;

    return OK;
}

/*
 * Generate an ISN_LOADOUTER instruction
 */
    int
generate_LOADOUTER(
	cctx_T	    *cctx,
	int	    idx,
	int	    nesting,
	type_T	    *type)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr_type2(cctx, ISN_LOADOUTER, type, type)) == NULL)
	return FAIL;
    isn->isn_arg.outer.outer_idx = idx;
    isn->isn_arg.outer.outer_depth = nesting;

    return OK;
}

/*
 * Generate an ISN_LOADV instruction for v:var.
 */
    int
generate_LOADV(
	cctx_T	    *cctx,
	char_u	    *name,
	int	    error)
{
    int	    di_flags;
    int	    vidx = find_vim_var(name, &di_flags);
    type_T  *type;

    RETURN_OK_IF_SKIP(cctx);
    if (vidx < 0)
    {
	if (error)
	    semsg(_(e_variable_not_found_str), name);
	return FAIL;
    }
    type = get_vim_var_type(vidx, cctx->ctx_type_list);
    return generate_LOAD(cctx, ISN_LOADV, vidx, NULL, type);
}

/*
 * Generate an ISN_UNLET instruction.
 */
    int
generate_UNLET(cctx_T *cctx, isntype_T isn_type, char_u *name, int forceit)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr(cctx, isn_type)) == NULL)
	return FAIL;
    isn->isn_arg.unlet.ul_name = vim_strsave(name);
    isn->isn_arg.unlet.ul_forceit = forceit;

    return OK;
}

/*
 * Generate an ISN_LOCKCONST instruction.
 */
    int
generate_LOCKCONST(cctx_T *cctx)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr(cctx, ISN_LOCKCONST)) == NULL)
	return FAIL;
    return OK;
}

/*
 * Generate an ISN_LOADS instruction.
 */
    int
generate_OLDSCRIPT(
	cctx_T	    *cctx,
	isntype_T   isn_type,
	char_u	    *name,
	int	    sid,
	type_T	    *type)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if (isn_type == ISN_LOADS)
	isn = generate_instr_type(cctx, isn_type, type);
    else
	isn = generate_instr_drop(cctx, isn_type, 1);
    if (isn == NULL)
	return FAIL;
    isn->isn_arg.loadstore.ls_name = vim_strsave(name);
    isn->isn_arg.loadstore.ls_sid = sid;

    return OK;
}

/*
 * Generate an ISN_LOADSCRIPT or ISN_STORESCRIPT instruction.
 */
    int
generate_VIM9SCRIPT(
	cctx_T	    *cctx,
	isntype_T   isn_type,
	int	    sid,
	int	    idx,
	type_T	    *type)
{
    isn_T	*isn;
    scriptref_T	*sref;
    scriptitem_T *si = SCRIPT_ITEM(sid);

    RETURN_OK_IF_SKIP(cctx);
    if (isn_type == ISN_LOADSCRIPT)
	isn = generate_instr_type(cctx, isn_type, type);
    else
	isn = generate_instr_drop(cctx, isn_type, 1);
    if (isn == NULL)
	return FAIL;

    // This requires three arguments, which doesn't fit in an instruction, thus
    // we need to allocate a struct for this.
    sref = ALLOC_ONE(scriptref_T);
    if (sref == NULL)
	return FAIL;
    isn->isn_arg.script.scriptref = sref;
    sref->sref_sid = sid;
    sref->sref_idx = idx;
    sref->sref_seq = si->sn_script_seq;
    sref->sref_type = type;
    return OK;
}

/*
 * Generate an ISN_NEWLIST instruction.
 */
    int
generate_NEWLIST(cctx_T *cctx, int count)
{
    isn_T	*isn;
    type_T	*member_type;
    type_T	*decl_member_type;
    type_T	*type;
    type_T	*decl_type;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr(cctx, ISN_NEWLIST)) == NULL)
	return FAIL;
    isn->isn_arg.number = count;

    // Get the member type and the declared member type from all the items on
    // the stack.
    member_type = get_member_type_from_stack(count, 1, &decl_member_type, cctx);
    type = get_list_type(member_type, cctx->ctx_type_list);
    decl_type = get_list_type(decl_member_type, cctx->ctx_type_list);

    // drop the value types
    cctx->ctx_type_stack.ga_len -= count;

    // add the list type to the type stack
    return push_type_stack2(cctx, type, decl_type);
}

/*
 * Generate an ISN_NEWDICT instruction.
 */
    int
generate_NEWDICT(cctx_T *cctx, int count)
{
    isn_T	*isn;
    type_T	*member_type;
    type_T	*decl_member_type;
    type_T	*type;
    type_T	*decl_type;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr(cctx, ISN_NEWDICT)) == NULL)
	return FAIL;
    isn->isn_arg.number = count;

    member_type = get_member_type_from_stack(count, 2,
						      &decl_member_type, cctx);
    type = get_dict_type(member_type, cctx->ctx_type_list);
    decl_type = get_dict_type(decl_member_type, cctx->ctx_type_list);

    // drop the key and value types
    cctx->ctx_type_stack.ga_len -= 2 * count;

    // add the dict type to the type stack
    return push_type_stack2(cctx, type, decl_type);
}

/*
 * Generate an ISN_FUNCREF instruction.
 */
    int
generate_FUNCREF(cctx_T *cctx, ufunc_T *ufunc)
{
    isn_T	*isn;
    type_T	*type;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr(cctx, ISN_FUNCREF)) == NULL)
	return FAIL;
    if (ufunc->uf_def_status == UF_NOT_COMPILED)
	isn->isn_arg.funcref.fr_func_name = vim_strsave(ufunc->uf_name);
    else
	isn->isn_arg.funcref.fr_dfunc_idx = ufunc->uf_dfunc_idx;
    cctx->ctx_has_closure = 1;

    // If the referenced function is a closure, it may use items further up in
    // the nested context, including this one.
    if (ufunc->uf_flags & FC_CLOSURE)
	cctx->ctx_ufunc->uf_flags |= FC_CLOSURE;

    type = ufunc->uf_func_type == NULL ? &t_func_any : ufunc->uf_func_type;
    return push_type_stack(cctx, type);
}

/*
 * Generate an ISN_NEWFUNC instruction.
 * "lambda_name" and "func_name" must be in allocated memory and will be
 * consumed.
 */
    int
generate_NEWFUNC(cctx_T *cctx, char_u *lambda_name, char_u *func_name)
{
    isn_T	*isn;

    if (cctx->ctx_skip == SKIP_YES)
    {
	vim_free(lambda_name);
	vim_free(func_name);
	return OK;
    }
    if ((isn = generate_instr(cctx, ISN_NEWFUNC)) == NULL)
    {
	vim_free(lambda_name);
	vim_free(func_name);
	return FAIL;
    }
    isn->isn_arg.newfunc.nf_lambda = lambda_name;
    isn->isn_arg.newfunc.nf_global = func_name;

    return OK;
}

/*
 * Generate an ISN_DEF instruction: list functions
 */
    int
generate_DEF(cctx_T *cctx, char_u *name, size_t len)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr(cctx, ISN_DEF)) == NULL)
	return FAIL;
    if (len > 0)
    {
	isn->isn_arg.string = vim_strnsave(name, len);
	if (isn->isn_arg.string == NULL)
	    return FAIL;
    }
    return OK;
}

/*
 * Generate an ISN_JUMP instruction.
 */
    int
generate_JUMP(cctx_T *cctx, jumpwhen_T when, int where)
{
    isn_T	*isn;
    garray_T	*stack = &cctx->ctx_type_stack;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr(cctx, ISN_JUMP)) == NULL)
	return FAIL;
    isn->isn_arg.jump.jump_when = when;
    isn->isn_arg.jump.jump_where = where;

    if (when != JUMP_ALWAYS && stack->ga_len > 0)
	--stack->ga_len;

    return OK;
}

/*
 * Generate an ISN_JUMP_IF_ARG_SET instruction.
 */
    int
generate_JUMP_IF_ARG_SET(cctx_T *cctx, int arg_off)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr(cctx, ISN_JUMP_IF_ARG_SET)) == NULL)
	return FAIL;
    isn->isn_arg.jumparg.jump_arg_off = arg_off;
    // jump_where is set later
    return OK;
}

    int
generate_FOR(cctx_T *cctx, int loop_idx)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr(cctx, ISN_FOR)) == NULL)
	return FAIL;
    isn->isn_arg.forloop.for_idx = loop_idx;

    // type doesn't matter, will be stored next
    return push_type_stack(cctx, &t_any);
}
/*
 * Generate an ISN_TRYCONT instruction.
 */
    int
generate_TRYCONT(cctx_T *cctx, int levels, int where)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr(cctx, ISN_TRYCONT)) == NULL)
	return FAIL;
    isn->isn_arg.trycont.tct_levels = levels;
    isn->isn_arg.trycont.tct_where = where;

    return OK;
}


/*
 * Generate an ISN_BCALL instruction.
 * "method_call" is TRUE for "value->method()"
 * Return FAIL if the number of arguments is wrong.
 */
    int
generate_BCALL(cctx_T *cctx, int func_idx, int argcount, int method_call)
{
    isn_T	*isn;
    garray_T	*stack = &cctx->ctx_type_stack;
    int		argoff;
    type2_T	*typep;
    type2_T	*argtypes = NULL;
    type2_T	shuffled_argtypes[MAX_FUNC_ARGS];
    type2_T	*maptype = NULL;
    type_T	*type;

    RETURN_OK_IF_SKIP(cctx);
    argoff = check_internal_func(func_idx, argcount);
    if (argoff < 0)
	return FAIL;

    if (method_call && argoff > 1)
    {
	if ((isn = generate_instr(cctx, ISN_SHUFFLE)) == NULL)
	    return FAIL;
	isn->isn_arg.shuffle.shfl_item = argcount;
	isn->isn_arg.shuffle.shfl_up = argoff - 1;
    }

    if (argcount > 0)
    {
	// Check the types of the arguments.
	typep = ((type2_T *)stack->ga_data) + stack->ga_len - argcount;
	if (method_call && argoff > 1)
	{
	    int i;

	    for (i = 0; i < argcount; ++i)
		shuffled_argtypes[i] = (i < argoff - 1)
			    ? typep[i + 1]
				  : (i == argoff - 1) ? typep[0] : typep[i];
	    argtypes = shuffled_argtypes;
	}
	else
	{
	    int i;

	    for (i = 0; i < argcount; ++i)
		shuffled_argtypes[i] = typep[i];
	    argtypes = shuffled_argtypes;
	}
	if (internal_func_check_arg_types(argtypes, func_idx, argcount,
								 cctx) == FAIL)
	    return FAIL;
	if (internal_func_is_map(func_idx))
	    maptype = argtypes;
    }

    if ((isn = generate_instr(cctx, ISN_BCALL)) == NULL)
	return FAIL;
    isn->isn_arg.bfunc.cbf_idx = func_idx;
    isn->isn_arg.bfunc.cbf_argcount = argcount;

    // Drop the argument types and push the return type.
    stack->ga_len -= argcount;
    type = internal_func_ret_type(func_idx, argcount, argtypes);
    if (push_type_stack(cctx, type) == FAIL)
	return FAIL;

    if (maptype != NULL && maptype[0].type_curr->tt_member != NULL
				  && maptype[0].type_curr->tt_member != &t_any)
	// Check that map() didn't change the item types.
	generate_TYPECHECK(cctx, maptype[0].type_curr, -1, 1);

    return OK;
}

/*
 * Generate an ISN_LISTAPPEND instruction.  Works like add().
 * Argument count is already checked.
 */
    int
generate_LISTAPPEND(cctx_T *cctx)
{
    type_T	*list_type;
    type_T	*item_type;
    type_T	*expected;

    // Caller already checked that list_type is a list.
    list_type = get_type_on_stack(cctx, 1);
    item_type = get_type_on_stack(cctx, 0);
    expected = list_type->tt_member;
    if (need_type(item_type, expected, -1, 0, cctx, FALSE, FALSE) == FAIL)
	return FAIL;

    if (generate_instr(cctx, ISN_LISTAPPEND) == NULL)
	return FAIL;

    --cctx->ctx_type_stack.ga_len;	    // drop the argument
    return OK;
}

/*
 * Generate an ISN_BLOBAPPEND instruction.  Works like add().
 * Argument count is already checked.
 */
    int
generate_BLOBAPPEND(cctx_T *cctx)
{
    type_T	*item_type;

    // Caller already checked that blob_type is a blob.
    item_type = get_type_on_stack(cctx, 0);
    if (need_type(item_type, &t_number, -1, 0, cctx, FALSE, FALSE) == FAIL)
	return FAIL;

    if (generate_instr(cctx, ISN_BLOBAPPEND) == NULL)
	return FAIL;

    --cctx->ctx_type_stack.ga_len;	    // drop the argument
    return OK;
}

/*
 * Generate an ISN_DCALL or ISN_UCALL instruction.
 * Return FAIL if the number of arguments is wrong.
 */
    int
generate_CALL(cctx_T *cctx, ufunc_T *ufunc, int pushed_argcount)
{
    isn_T	*isn;
    int		regular_args = ufunc->uf_args.ga_len;
    int		argcount = pushed_argcount;

    RETURN_OK_IF_SKIP(cctx);
    if (argcount > regular_args && !has_varargs(ufunc))
    {
	semsg(_(e_too_many_arguments_for_function_str),
						   printable_func_name(ufunc));
	return FAIL;
    }
    if (argcount < regular_args - ufunc->uf_def_args.ga_len)
    {
	semsg(_(e_not_enough_arguments_for_function_str),
						   printable_func_name(ufunc));
	return FAIL;
    }

    if (ufunc->uf_def_status != UF_NOT_COMPILED
	    && ufunc->uf_def_status != UF_COMPILE_ERROR)
    {
	int		i;

	for (i = 0; i < argcount; ++i)
	{
	    type_T *expected;
	    type_T *actual;

	    actual = get_type_on_stack(cctx, argcount - i - 1);
	    if (actual == &t_special
			      && i >= regular_args - ufunc->uf_def_args.ga_len)
	    {
		// assume v:none used for default argument value
		continue;
	    }
	    if (i < regular_args)
	    {
		if (ufunc->uf_arg_types == NULL)
		    continue;
		expected = ufunc->uf_arg_types[i];
	    }
	    else if (ufunc->uf_va_type == NULL
					   || ufunc->uf_va_type == &t_list_any)
		// possibly a lambda or "...: any"
		expected = &t_any;
	    else
		expected = ufunc->uf_va_type->tt_member;
	    if (need_type(actual, expected, -argcount + i, i + 1, cctx,
							  TRUE, FALSE) == FAIL)
	    {
		arg_type_mismatch(expected, actual, i + 1);
		return FAIL;
	    }
	}
	if (func_needs_compiling(ufunc, COMPILE_TYPE(ufunc))
		&& compile_def_function(ufunc, ufunc->uf_ret_type == NULL,
					    COMPILE_TYPE(ufunc), NULL) == FAIL)
	    return FAIL;
    }
    if (ufunc->uf_def_status == UF_COMPILE_ERROR)
    {
	emsg_funcname(_(e_call_to_function_that_failed_to_compile_str),
							       ufunc->uf_name);
	return FAIL;
    }

    if ((isn = generate_instr(cctx,
		    ufunc->uf_def_status != UF_NOT_COMPILED ? ISN_DCALL
							 : ISN_UCALL)) == NULL)
	return FAIL;
    if (isn->isn_type == ISN_DCALL)
    {
	isn->isn_arg.dfunc.cdf_idx = ufunc->uf_dfunc_idx;
	isn->isn_arg.dfunc.cdf_argcount = argcount;
    }
    else
    {
	// A user function may be deleted and redefined later, can't use the
	// ufunc pointer, need to look it up again at runtime.
	isn->isn_arg.ufunc.cuf_name = vim_strsave(ufunc->uf_name);
	isn->isn_arg.ufunc.cuf_argcount = argcount;
    }

    // drop the argument types
    cctx->ctx_type_stack.ga_len -= argcount;

    // add return type
    return push_type_stack(cctx, ufunc->uf_ret_type);
}

/*
 * Generate an ISN_UCALL instruction when the function isn't defined yet.
 */
    int
generate_UCALL(cctx_T *cctx, char_u *name, int argcount)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr(cctx, ISN_UCALL)) == NULL)
	return FAIL;
    isn->isn_arg.ufunc.cuf_name = vim_strsave(name);
    isn->isn_arg.ufunc.cuf_argcount = argcount;

    // drop the argument types
    cctx->ctx_type_stack.ga_len -= argcount;

    // add return value
    return push_type_stack(cctx, &t_any);
}

/*
 * Generate an ISN_PCALL instruction.
 * "type" is the type of the FuncRef.
 */
    int
generate_PCALL(
	cctx_T	*cctx,
	int	argcount,
	char_u	*name,
	type_T	*type,
	int	at_top)
{
    isn_T	*isn;
    type_T	*ret_type;

    RETURN_OK_IF_SKIP(cctx);

    if (type->tt_type == VAR_ANY || type->tt_type == VAR_UNKNOWN)
	ret_type = &t_any;
    else if (type->tt_type == VAR_FUNC || type->tt_type == VAR_PARTIAL)
    {
	if (type->tt_argcount != -1)
	{
	    int	    varargs = (type->tt_flags & TTFLAG_VARARGS) ? 1 : 0;

	    if (argcount < type->tt_min_argcount - varargs)
	    {
		semsg(_(e_not_enough_arguments_for_function_str), name);
		return FAIL;
	    }
	    if (!varargs && argcount > type->tt_argcount)
	    {
		semsg(_(e_too_many_arguments_for_function_str), name);
		return FAIL;
	    }
	    if (type->tt_args != NULL)
	    {
		int i;

		for (i = 0; i < argcount; ++i)
		{
		    int	    offset = -argcount + i - (at_top ? 0 : 1);
		    type_T *actual = get_type_on_stack(cctx, -1 - offset);
		    type_T *expected;

		    if (varargs && i >= type->tt_argcount - 1)
			expected = type->tt_args[
					     type->tt_argcount - 1]->tt_member;
		    else if (i >= type->tt_min_argcount
						       && actual == &t_special)
			expected = &t_any;
		    else
			expected = type->tt_args[i];
		    if (need_type(actual, expected, offset, i + 1,
						    cctx, TRUE, FALSE) == FAIL)
		    {
			arg_type_mismatch(expected, actual, i + 1);
			return FAIL;
		    }
		}
	    }
	}
	ret_type = type->tt_member;
	if (ret_type == &t_unknown)
	    // return type not known yet, use a runtime check
	    ret_type = &t_any;
    }
    else
    {
	semsg(_(e_not_callable_type_str), name);
	return FAIL;
    }

    if ((isn = generate_instr(cctx, ISN_PCALL)) == NULL)
	return FAIL;
    isn->isn_arg.pfunc.cpf_top = at_top;
    isn->isn_arg.pfunc.cpf_argcount = argcount;

    // drop the arguments and the funcref/partial
    cctx->ctx_type_stack.ga_len -= argcount + 1;

    // push the return value
    push_type_stack(cctx, ret_type);

    // If partial is above the arguments it must be cleared and replaced with
    // the return value.
    if (at_top && generate_instr(cctx, ISN_PCALL_END) == NULL)
	return FAIL;

    return OK;
}

/*
 * Generate an ISN_STRINGMEMBER instruction.
 */
    int
generate_STRINGMEMBER(cctx_T *cctx, char_u *name, size_t len)
{
    isn_T	*isn;
    type_T	*type;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr(cctx, ISN_STRINGMEMBER)) == NULL)
	return FAIL;
    isn->isn_arg.string = vim_strnsave(name, len);

    // check for dict type
    type = get_type_on_stack(cctx, 0);
    if (type->tt_type != VAR_DICT && type != &t_any && type != &t_unknown)
    {
	char *tofree;

	semsg(_(e_expected_dictionary_for_using_key_str_but_got_str),
					       name, type_name(type, &tofree));
	vim_free(tofree);
	return FAIL;
    }
    // change dict type to dict member type
    if (type->tt_type == VAR_DICT)
    {
	type_T *ntype = type->tt_member == &t_unknown
						    ? &t_any : type->tt_member;
	set_type_on_stack(cctx, ntype, 0);
    }

    return OK;
}

/*
 * Generate an ISN_ECHO instruction.
 */
    int
generate_ECHO(cctx_T *cctx, int with_white, int count)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr_drop(cctx, ISN_ECHO, count)) == NULL)
	return FAIL;
    isn->isn_arg.echo.echo_with_white = with_white;
    isn->isn_arg.echo.echo_count = count;

    return OK;
}

/*
 * Generate an ISN_EXECUTE/ISN_ECHOMSG/ISN_ECHOERR instruction.
 */
    int
generate_MULT_EXPR(cctx_T *cctx, isntype_T isn_type, int count)
{
    isn_T	*isn;

    if ((isn = generate_instr_drop(cctx, isn_type, count)) == NULL)
	return FAIL;
    isn->isn_arg.number = count;

    return OK;
}

/*
 * Generate an ISN_PUT instruction.
 */
    int
generate_PUT(cctx_T *cctx, int regname, linenr_T lnum)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr(cctx, ISN_PUT)) == NULL)
	return FAIL;
    isn->isn_arg.put.put_regname = regname;
    isn->isn_arg.put.put_lnum = lnum;
    return OK;
}

/*
 * Generate an EXEC instruction that takes a string argument.
 * A copy is made of "line".
 */
    int
generate_EXEC_copy(cctx_T *cctx, isntype_T isntype, char_u *line)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr(cctx, isntype)) == NULL)
	return FAIL;
    isn->isn_arg.string = vim_strsave(line);
    return OK;
}

/*
 * Generate an EXEC instruction that takes a string argument.
 * "str" must be allocated, it is consumed.
 */
    int
generate_EXEC(cctx_T *cctx, isntype_T isntype, char_u *str)
{
    isn_T	*isn;

    if (cctx->ctx_skip == SKIP_YES)
    {
	vim_free(str);
	return OK;
    }
    if ((isn = generate_instr(cctx, isntype)) == NULL)
    {
	vim_free(str);
	return FAIL;
    }
    isn->isn_arg.string = str;
    return OK;
}

    int
generate_LEGACY_EVAL(cctx_T *cctx, char_u *line)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr(cctx, ISN_LEGACY_EVAL)) == NULL)
	return FAIL;
    isn->isn_arg.string = vim_strsave(line);

    return push_type_stack(cctx, &t_any);
}

    int
generate_EXECCONCAT(cctx_T *cctx, int count)
{
    isn_T	*isn;

    if ((isn = generate_instr_drop(cctx, ISN_EXECCONCAT, count)) == NULL)
	return FAIL;
    isn->isn_arg.number = count;
    return OK;
}

/*
 * Generate ISN_RANGE.  Consumes "range".  Return OK/FAIL.
 */
    int
generate_RANGE(cctx_T *cctx, char_u *range)
{
    isn_T	*isn;

    if ((isn = generate_instr(cctx, ISN_RANGE)) == NULL)
	return FAIL;
    isn->isn_arg.string = range;

    return push_type_stack(cctx, &t_number);
}

    int
generate_UNPACK(cctx_T *cctx, int var_count, int semicolon)
{
    isn_T	*isn;

    RETURN_OK_IF_SKIP(cctx);
    if ((isn = generate_instr(cctx, ISN_UNPACK)) == NULL)
	return FAIL;
    isn->isn_arg.unpack.unp_count = var_count;
    isn->isn_arg.unpack.unp_semicolon = semicolon;
    return OK;
}

/*
 * Generate an instruction for any command modifiers.
 */
    int
generate_cmdmods(cctx_T *cctx, cmdmod_T *cmod)
{
    isn_T	*isn;

    if (has_cmdmod(cmod, FALSE))
    {
	cctx->ctx_has_cmdmod = TRUE;

	if ((isn = generate_instr(cctx, ISN_CMDMOD)) == NULL)
	    return FAIL;
	isn->isn_arg.cmdmod.cf_cmdmod = ALLOC_ONE(cmdmod_T);
	if (isn->isn_arg.cmdmod.cf_cmdmod == NULL)
	    return FAIL;
	mch_memmove(isn->isn_arg.cmdmod.cf_cmdmod, cmod, sizeof(cmdmod_T));
	// filter program now belongs to the instruction
	cmod->cmod_filter_regmatch.regprog = NULL;
    }

    return OK;
}

    int
generate_undo_cmdmods(cctx_T *cctx)
{
    if (cctx->ctx_has_cmdmod && generate_instr(cctx, ISN_CMDMOD_REV) == NULL)
	return FAIL;
    cctx->ctx_has_cmdmod = FALSE;
    return OK;
}

/*
 * Generate a STORE instruction for "dest", not being "dest_local".
 * Return FAIL when out of memory.
 */
    int
generate_store_var(
	cctx_T		*cctx,
	assign_dest_T	dest,
	int		opt_flags,
	int		vimvaridx,
	int		scriptvar_idx,
	int		scriptvar_sid,
	type_T		*type,
	char_u		*name)
{
    switch (dest)
    {
	case dest_option:
	    return generate_STOREOPT(cctx, ISN_STOREOPT,
					skip_option_env_lead(name), opt_flags);
	case dest_func_option:
	    return generate_STOREOPT(cctx, ISN_STOREFUNCOPT,
					skip_option_env_lead(name), opt_flags);
	case dest_global:
	    // include g: with the name, easier to execute that way
	    return generate_STORE(cctx, vim_strchr(name, AUTOLOAD_CHAR) == NULL
					? ISN_STOREG : ISN_STOREAUTO, 0, name);
	case dest_buffer:
	    // include b: with the name, easier to execute that way
	    return generate_STORE(cctx, ISN_STOREB, 0, name);
	case dest_window:
	    // include w: with the name, easier to execute that way
	    return generate_STORE(cctx, ISN_STOREW, 0, name);
	case dest_tab:
	    // include t: with the name, easier to execute that way
	    return generate_STORE(cctx, ISN_STORET, 0, name);
	case dest_env:
	    return generate_STORE(cctx, ISN_STOREENV, 0, name + 1);
	case dest_reg:
	    return generate_STORE(cctx, ISN_STOREREG,
					 name[1] == '@' ? '"' : name[1], NULL);
	case dest_vimvar:
	    return generate_STORE(cctx, ISN_STOREV, vimvaridx, NULL);
	case dest_script:
	    if (scriptvar_idx < 0)
		// "s:" may be included in the name.
		return generate_OLDSCRIPT(cctx, ISN_STORES, name,
							  scriptvar_sid, type);
	    return generate_VIM9SCRIPT(cctx, ISN_STORESCRIPT,
					   scriptvar_sid, scriptvar_idx, type);
	case dest_local:
	case dest_expr:
	    // cannot happen
	    break;
    }
    return FAIL;
}

/*
 * Return TRUE when inside a "for" or "while" loop.
 */
    int
inside_loop_scope(cctx_T *cctx)
{
    scope_T	*scope = cctx->ctx_scope;

    for (;;)
    {
	if (scope == NULL)
	    break;
	if (scope->se_type == FOR_SCOPE || scope->se_type == WHILE_SCOPE)
	    return TRUE;
	scope = scope->se_outer;
    }
    return FALSE;
}

    int
generate_store_lhs(cctx_T *cctx, lhs_T *lhs, int instr_count, int is_decl)
{
    if (lhs->lhs_dest != dest_local)
	return generate_store_var(cctx, lhs->lhs_dest,
			    lhs->lhs_opt_flags, lhs->lhs_vimvaridx,
			    lhs->lhs_scriptvar_idx, lhs->lhs_scriptvar_sid,
			    lhs->lhs_type, lhs->lhs_name);

    if (lhs->lhs_lvar != NULL)
    {
	garray_T	*instr = &cctx->ctx_instr;
	isn_T		*isn = ((isn_T *)instr->ga_data) + instr->ga_len - 1;

	// Optimization: turn "var = 123" from ISN_PUSHNR + ISN_STORE into
	// ISN_STORENR.
	// And "var = 0" does not need any instruction.
	if (lhs->lhs_lvar->lv_from_outer == 0
		&& instr->ga_len == instr_count + 1
		&& isn->isn_type == ISN_PUSHNR)
	{
	    varnumber_T val = isn->isn_arg.number;
	    garray_T    *stack = &cctx->ctx_type_stack;

	    if (val == 0 && is_decl && !inside_loop_scope(cctx))
	    {
		// zero is the default value, no need to do anything
		--instr->ga_len;
	    }
	    else
	    {
		isn->isn_type = ISN_STORENR;
		isn->isn_arg.storenr.stnr_idx = lhs->lhs_lvar->lv_idx;
		isn->isn_arg.storenr.stnr_val = val;
	    }
	    if (stack->ga_len > 0)
		--stack->ga_len;
	}
	else if (lhs->lhs_lvar->lv_from_outer > 0)
	    generate_STOREOUTER(cctx, lhs->lhs_lvar->lv_idx,
						 lhs->lhs_lvar->lv_from_outer);
	else
	    generate_STORE(cctx, ISN_STORE, lhs->lhs_lvar->lv_idx, NULL);
    }
    return OK;
}

#if defined(FEAT_PROFILE) || defined(PROTO)
    void
may_generate_prof_end(cctx_T *cctx, int prof_lnum)
{
    if (cctx->ctx_compile_type == CT_PROFILE && prof_lnum >= 0)
	generate_instr(cctx, ISN_PROF_END);
}
#endif


/*
 * Delete an instruction, free what it contains.
 */
    void
delete_instr(isn_T *isn)
{
    switch (isn->isn_type)
    {
	case ISN_AUTOLOAD:
	case ISN_DEF:
	case ISN_EXEC:
	case ISN_EXECRANGE:
	case ISN_EXEC_SPLIT:
	case ISN_LEGACY_EVAL:
	case ISN_LOADAUTO:
	case ISN_LOADB:
	case ISN_LOADENV:
	case ISN_LOADG:
	case ISN_LOADOPT:
	case ISN_LOADT:
	case ISN_LOADW:
	case ISN_LOCKUNLOCK:
	case ISN_PUSHEXC:
	case ISN_PUSHFUNC:
	case ISN_PUSHS:
	case ISN_RANGE:
	case ISN_STOREAUTO:
	case ISN_STOREB:
	case ISN_STOREENV:
	case ISN_STOREG:
	case ISN_STORET:
	case ISN_STOREW:
	case ISN_STRINGMEMBER:
	    vim_free(isn->isn_arg.string);
	    break;

	case ISN_SUBSTITUTE:
	    {
		int	idx;
		isn_T	*list = isn->isn_arg.subs.subs_instr;

		vim_free(isn->isn_arg.subs.subs_cmd);
		for (idx = 0; list[idx].isn_type != ISN_FINISH; ++idx)
		    delete_instr(list + idx);
		vim_free(list);
	    }
	    break;

	case ISN_INSTR:
	    {
		int	idx;
		isn_T	*list = isn->isn_arg.instr;

		for (idx = 0; list[idx].isn_type != ISN_FINISH; ++idx)
		    delete_instr(list + idx);
		vim_free(list);
	    }
	    break;

	case ISN_LOADS:
	case ISN_STORES:
	    vim_free(isn->isn_arg.loadstore.ls_name);
	    break;

	case ISN_UNLET:
	case ISN_UNLETENV:
	    vim_free(isn->isn_arg.unlet.ul_name);
	    break;

	case ISN_STOREOPT:
	case ISN_STOREFUNCOPT:
	    vim_free(isn->isn_arg.storeopt.so_name);
	    break;

	case ISN_PUSHBLOB:   // push blob isn_arg.blob
	    blob_unref(isn->isn_arg.blob);
	    break;

	case ISN_PUSHJOB:
#ifdef FEAT_JOB_CHANNEL
	    job_unref(isn->isn_arg.job);
#endif
	    break;

	case ISN_PUSHCHANNEL:
#ifdef FEAT_JOB_CHANNEL
	    channel_unref(isn->isn_arg.channel);
#endif
	    break;

	case ISN_UCALL:
	    vim_free(isn->isn_arg.ufunc.cuf_name);
	    break;

	case ISN_FUNCREF:
	    {
		if (isn->isn_arg.funcref.fr_func_name == NULL)
		{
		    dfunc_T *dfunc = ((dfunc_T *)def_functions.ga_data)
					   + isn->isn_arg.funcref.fr_dfunc_idx;
		    ufunc_T *ufunc = dfunc->df_ufunc;

		    if (ufunc != NULL && func_name_refcount(ufunc->uf_name))
			func_ptr_unref(ufunc);
		}
		else
		{
		    char_u *name = isn->isn_arg.funcref.fr_func_name;

		    if (name != NULL)
			func_unref(name);
		    vim_free(isn->isn_arg.funcref.fr_func_name);
		}
	    }
	    break;

	case ISN_DCALL:
	    {
		dfunc_T *dfunc = ((dfunc_T *)def_functions.ga_data)
					       + isn->isn_arg.dfunc.cdf_idx;

		if (dfunc->df_ufunc != NULL
			       && func_name_refcount(dfunc->df_ufunc->uf_name))
		    func_ptr_unref(dfunc->df_ufunc);
	    }
	    break;

	case ISN_NEWFUNC:
	    {
		char_u  *lambda = isn->isn_arg.newfunc.nf_lambda;
		ufunc_T *ufunc = find_func_even_dead(lambda, FFED_IS_GLOBAL);

		if (ufunc != NULL)
		{
		    unlink_def_function(ufunc);
		    func_ptr_unref(ufunc);
		}

		vim_free(lambda);
		vim_free(isn->isn_arg.newfunc.nf_global);
	    }
	    break;

	case ISN_CHECKTYPE:
	case ISN_SETTYPE:
	    free_type(isn->isn_arg.type.ct_type);
	    break;

	case ISN_CMDMOD:
	    vim_regfree(isn->isn_arg.cmdmod.cf_cmdmod
					       ->cmod_filter_regmatch.regprog);
	    vim_free(isn->isn_arg.cmdmod.cf_cmdmod);
	    break;

	case ISN_LOADSCRIPT:
	case ISN_STORESCRIPT:
	    vim_free(isn->isn_arg.script.scriptref);
	    break;

	case ISN_TRY:
	    vim_free(isn->isn_arg.tryref.try_ref);
	    break;

	case ISN_CEXPR_CORE:
	    vim_free(isn->isn_arg.cexpr.cexpr_ref->cer_cmdline);
	    vim_free(isn->isn_arg.cexpr.cexpr_ref);
	    break;

	case ISN_2BOOL:
	case ISN_2STRING:
	case ISN_2STRING_ANY:
	case ISN_ADDBLOB:
	case ISN_ADDLIST:
	case ISN_ANYINDEX:
	case ISN_ANYSLICE:
	case ISN_BCALL:
	case ISN_BLOBAPPEND:
	case ISN_BLOBINDEX:
	case ISN_BLOBSLICE:
	case ISN_CATCH:
	case ISN_CEXPR_AUCMD:
	case ISN_CHECKLEN:
	case ISN_CHECKNR:
	case ISN_CLEARDICT:
	case ISN_CMDMOD_REV:
	case ISN_COMPAREANY:
	case ISN_COMPAREBLOB:
	case ISN_COMPAREBOOL:
	case ISN_COMPAREDICT:
	case ISN_COMPAREFLOAT:
	case ISN_COMPAREFUNC:
	case ISN_COMPARELIST:
	case ISN_COMPARENR:
	case ISN_COMPARESPECIAL:
	case ISN_COMPARESTRING:
	case ISN_CONCAT:
	case ISN_COND2BOOL:
	case ISN_DEBUG:
	case ISN_DROP:
	case ISN_ECHO:
	case ISN_ECHOCONSOLE:
	case ISN_ECHOERR:
	case ISN_ECHOMSG:
	case ISN_ENDTRY:
	case ISN_EXECCONCAT:
	case ISN_EXECUTE:
	case ISN_FINALLY:
	case ISN_FINISH:
	case ISN_FOR:
	case ISN_GETITEM:
	case ISN_JUMP:
	case ISN_JUMP_IF_ARG_SET:
	case ISN_LISTAPPEND:
	case ISN_LISTINDEX:
	case ISN_LISTSLICE:
	case ISN_LOAD:
	case ISN_LOADBDICT:
	case ISN_LOADGDICT:
	case ISN_LOADOUTER:
	case ISN_LOADREG:
	case ISN_LOADTDICT:
	case ISN_LOADV:
	case ISN_LOADWDICT:
	case ISN_LOCKCONST:
	case ISN_MEMBER:
	case ISN_NEGATENR:
	case ISN_NEWDICT:
	case ISN_NEWLIST:
	case ISN_OPANY:
	case ISN_OPFLOAT:
	case ISN_OPNR:
	case ISN_PCALL:
	case ISN_PCALL_END:
	case ISN_PROF_END:
	case ISN_PROF_START:
	case ISN_PUSHBOOL:
	case ISN_PUSHF:
	case ISN_PUSHNR:
	case ISN_PUSHSPEC:
	case ISN_PUT:
	case ISN_REDIREND:
	case ISN_REDIRSTART:
	case ISN_RETURN:
	case ISN_RETURN_VOID:
	case ISN_SHUFFLE:
	case ISN_SLICE:
	case ISN_STORE:
	case ISN_STOREINDEX:
	case ISN_STORENR:
	case ISN_STOREOUTER:
	case ISN_STORERANGE:
	case ISN_STOREREG:
	case ISN_STOREV:
	case ISN_STRINDEX:
	case ISN_STRSLICE:
	case ISN_THROW:
	case ISN_TRYCONT:
	case ISN_UNLETINDEX:
	case ISN_UNLETRANGE:
	case ISN_UNPACK:
	case ISN_USEDICT:
	    // nothing allocated
	    break;
    }
}

    void
clear_instr_ga(garray_T *gap)
{
    int idx;

    for (idx = 0; idx < gap->ga_len; ++idx)
	delete_instr(((isn_T *)gap->ga_data) + idx);
    ga_clear(gap);
}


#endif  // defined(FEAT_EVAL)
