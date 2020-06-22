$let DEBUG = 1
'$include: '../common/util.bi'
'$include: '../common/type.bi'
'$include: '../common/ast.bi'
'$include: '../common/htable.bi'
'$include: '../common/sif.bi'

'$include: 'tokeng.bi'
'$include: 'pratt.bi'
'$include: '../../build/token_registrations.bm'

'We expect exactly two arguments, an input file and output file
if _commandcount <> 2 then
    print "Usage: " + command$(0) + " <input file> <output file>"
    print "65 parser: converts source code to a SIF file."
    print "In almost all cases you don't want to run this program directly; you want to run 65 instead"
    system
end if
inputfile$ = command$(1)
outputfile$ = command$(2)

on error goto file_error
open inputfile$ for input as #1
on error goto generic_error

ast_init
root = ps_block
sif_write outputfile$, root
cleanup
system

file_error:
    fatalerror inputfile$ + ": Does not exist or inaccessible."

'$include: '../common/util.bm'

sub ps_gobble(token)
    do
        t = tok_next_token
    loop until t <> token or t = 0 '0 indicates EOF
    tok_please_repeat
end sub
    
function ps_block
$if DEBUG then
    print "Start block"
$endif
    root = ast_add_node(AST_BLOCK)
    do
        ps_gobble(TOK_NEWLINE)
        stmt = ps_stmt
        if stmt = 0 then exit do 'use 0 to signal the end of a block
        ast_attach root, stmt
    loop
    ps_block = root
$if DEBUG then    
    print "End block"
$endif    
end function

function ps_stmt
    dim he as hentry_t
$if DEBUG then    
    print "Start statement"
$endif    
    token = tok_next_token
    select case token
        case is < 0
            fatalerror "Unexpected literal " + tok_content$
        case TOK_IF
            ps_stmt = ps_if
        case TOK_DO
            ps_stmt = ps_do
        case TOK_WHILE
            ps_stmt = ps_while
        case TOK_FOR
            ps_stmt = ps_for
        case TOK_SELECT
            ps_stmt = ps_select
        case TOK_ELSE, TOK_LOOP, TOK_WEND, TOK_NEXT, TOK_CASE, TOK_EOF 
            'These all end a block in some fashion. Repeat so that the
            'block-specific code can assert the ending token
            ps_stmt = 0
            tok_please_repeat
        case TOK_END 'As in END IF, END SUB etc.
            'Like above, but no repeat so the block-specific ending token
            'can be asserted
            ps_stmt = 0
        case TOK_UNKNOWN
            ps_stmt = ps_assignment(ps_variable(token, tok_content$))
        case else
            he = htable_entries(token)
            select case he.typ
            case HE_VARIABLE
                ps_stmt = ps_assignment(ps_variable(token, tok_content$))
            case HE_FUNCTION
                tok_please_repeat
                ps_stmt = ps_stmtreg
            case else
                fatalerror tok_content$ + " doesn't belong here"
            end select
    end select
$if DEBUG then    
    print "Completed statement"
$endif    
end function

function ps_select
$if DEBUG then    
    print "Start SELECT block"
$endif    
    dim he as hentry_t
    root = ast_add_node(AST_SELECT)
    ps_assert_token tok_next_token, TOK_CASE
    expr = ps_expr
    expr_type = type_of_expr(expr)
    ast_attach root, expr
    ps_assert_token tok_next_token, TOK_NEWLINE
    t = tok_next_token
    do
        ps_assert_token t, TOK_CASE
        guard = ps_expr
        guard_type = type_of_expr(guard)
        if not type_can_cast(expr_type, guard_type) then fatalerror "Type of CASE expression does not match"
        ast_attach root, ast_add_cast(guard, expr_type)
        ast_attach root, ps_block
        t = tok_next_token
    loop while t <> TOK_SELECT 'ps_block eats the END
    ps_select = root
end function

function ps_for
$if DEBUG then    
    print "Start FOR block"
$endif    
    dim he as hentry_t
    root = ast_add_node(AST_FOR)
    t = tok_next_token
    if t = TOK_UNKNOWN then
        iterator = ps_variable(t, tok_content$)
        iterator_type = type_of_var(iterator)
        if not type_is_number(iterator_type) then fatalerror "FOR must have a numeric variable"
    else
        fatalerror "Expected new variable as iterator"
    end if
    ps_assert_token tok_next_token, TOK_EQUALS

    start_val = ps_expr
    if not type_is_number(type_of_expr(start_val)) then fatalerror "FOR start value must be numeric"
    start_val = ast_add_cast(start_val, iterator_type)

    ps_assert_token tok_next_token, TOK_TO

    end_val = ps_expr
    if not type_is_number(type_of_expr(start_val)) then fatalerror "FOR end value must be numeric"
    end_val = ast_add_cast(end_val, iterator_type)

    t = tok_next_token
    if t = TOK_STEP then
        step_val = ps_expr
        if not type_is_number(type_of_expr(step_val)) then fatalerror "FOR STEP value must be numeric"
        ps_assert_token tok_next_token, TOK_NEWLINE
    elseif t = TOK_NEWLINE then
        'Default is STEP 1
        step_val = ast_add_node(AST_CONSTANT)
        ast_nodes(step_val).ref = AST_ONE
    else
        fatalerror "Unexpected " + tok_content$
    end if
    step_val = ast_add_cast(step_val, iterator_type)

    block = ps_block

    'Error checking
    ps_assert_token tok_next_token, TOK_NEXT
    t = tok_next_token
    if t < 0 then
        fatalerror "Expected variable reference, not a literal"
    elseif t = TOK_UNKNOWN then
        fatalerror "Unknown variable"
    end if
    he = htable_entries(t)
    if he.typ <> HE_VARIABLE then fatalerror "Unexpected " + tok_content$
    if iterator <> ps_variable(t, tok_content$) then fatalerror "Variable in NEXT does not match variable in FOR"
    ps_assert_token tok_next_token, TOK_NEWLINE

    ast_nodes(root).ref = iterator
    ast_attach root, start_val
    ast_attach root, end_val
    ast_attach root, step_val
    ast_attach root, block
    ps_for = root
end function

function ps_while
$if DEBUG then    
    print "Start WHILE block"
$endif    
    root = ast_add_node(AST_DO_PRE)
    ast_attach root, ps_expr
    ps_assert_token tok_next_token, TOK_NEWLINE
    ast_attach root, ps_block
    ps_assert_token tok_next_token, TOK_WEND
    ps_while = root
end function

function ps_do
$if DEBUG then    
    print "Start DO block"
$endif    
    check = tok_next_token
    if check = TOK_WHILE or check = TOK_UNTIL then
        ps_do = ps_do_pre(check)
    elseif check = TOK_NEWLINE then
        ps_do = ps_do_post
    else
        fatalerror "Unexpected " + tok_content$
    end if
$if DEBUG then    
    print "Completed DO block"
$endif    
end function

function ps_do_pre(check)
$if DEBUG then    
    print "Start DO-PRE"
$endif    
    root = ast_add_node(AST_DO_PRE)
    ast_attach root, ps_loop_guard_expr(check)
    ps_assert_token tok_next_token, TOK_NEWLINE
    ast_attach root, ps_block
    ps_assert_token tok_next_token, TOK_LOOP
    ps_do_pre = root
$if DEBUG then    
    print "Completed DO-PRE"
$endif    
end function

function ps_loop_guard_expr(check)
    'Condition is WHILE guard; UNTIL will need the guard to be negated
    raw_guard = ps_expr
    guard_type = type_of_expr(raw_guard)
    if not type_is_number(guard_type) then fatalerror "Loop guard must be a numeric expression"
    if check = TOK_UNTIL then
        guard = ast_add_node(AST_CALL)
        ast_nodes(guard).ref = TOK_EQUALS
        false_const = ast_add_node(AST_CONSTANT)
        false_const.ref = AST_FALSE
        ast_attach guard, ast_add_cast(false_const, guard_type)
        ast_attach guard, raw_guard
        sig$ = type_sig_add_arg$(type_sig_add_arg$("", guard_type, 0), guard_type, 0)
        ast_nodes(guard).ref2 = type_find_sig_match(TOK_EQUALS, sig$)
    elseif check = TOK_WHILE then
        guard = raw_guard
    else
        fatalerror "Unexpected " + tok_content$
    end if
    ps_loop_guard_expr = guard
end function

function ps_do_post
$if DEBUG then    
    print "Start DO-POST"
$endif    
    root = ast_add_node(AST_DO_POST)
    block = ps_block
    ps_assert_token tok_next_token, TOK_LOOP

    check = tok_next_token
    if check = TOK_NEWLINE then
        'Oh boy, infinite loop!
        guard = ast_add_node(AST_CONSTANT)
        ast_nodes(guard).ref = AST_TRUE
    else
        guard = ps_loop_guard_expr(check)
    end if
    ast_attach root, guard
    ast_attach root, block
    ps_do_post = root
$if DEBUG then    
    print "Completed DO-POST"
$endif    
end function

function ps_if
$if DEBUG then    
    print "Start conditional"
$endif    
    root = ast_add_node(AST_IF)
    condition = ps_expr
    if not type_is_number(type_of_expr(condition)) then fatalerror "IF condition must be a numeric expression"
    ast_attach root, condition
    ps_assert_token tok_next_token, TOK_THEN

    token = tok_next_token
    if token = TOK_NEWLINE then 'Multi-line if
        ast_attach root, ps_block
        t = tok_next_token
        if t = TOK_ELSE then
            ps_assert_token tok_next_token, TOK_NEWLINE
            ast_attach root, ps_block
            t = tok_next_token
        end if
        'END IF, with the END being eaten by ps_block
        ps_assert_token t, TOK_IF
    else
        tok_please_repeat
        ast_attach root, ps_stmt
    end if
    ps_if = root
$if DEBUG then    
    print "Completed conditional"
$endif    
end function
    
function ps_assignment(ref)
$if DEBUG then    
    print "Start assignment"
$endif    
    root = ast_add_node(AST_ASSIGN)
    ast_nodes(root).ref = ref
    ps_assert_token tok_next_token, TOK_EQUALS
    expr = ps_expr
    lvalue_type = htable_entries(ref).v1
    rvalue_type = type_of_expr(expr)
    if not type_can_cast(lvalue_type, rvalue_type) then fatalerror "Type of variable in assignment does not match value being assigned"
    expr = ast_add_cast(expr, lvalue_type)
    ast_attach root, expr
    ps_assignment = root
    ps_assert_token tok_next_token, TOK_NEWLINE
$if DEBUG then    
    print "Completed assignment"
$endif    
end function

function ps_expr
$if DEBUG then    
    print "Start expr"
$endif    
    pt_token = tok_next_token
    pt_content$ = tok_content$
    ps_expr = pt_expr(0)
    tok_please_repeat
$if DEBUG then    
    print "Completed expr"
$endif    
end function
        
function ps_stmtreg
$if DEBUG then    
    print "Start stmtreg"
$endif    
    root = ast_add_node(AST_CALL)
    token = tok_next_token
    ast_nodes(root).ref = htable_entries(token).id

    ps_funcargs root

    ps_stmtreg = root
$if DEBUG then    
    print "Completed stmtreg"
$endif    
end function

function ps_funccall(func)
$if DEBUG then    
    print "Start function call"
$endif    
    root = ast_add_node(AST_CALL)
    ast_nodes(root).ref = func
    sigil = ps_opt_sigil(0)
    'dummy = ps_opt_sigil(type_of_call(root))
    t = tok_next_token
    if t = TOK_OPAREN then
        ps_funcargs root
        ps_assert_token tok_next_token, TOK_CPAREN
    else
        'No arguments
        tok_please_repeat
    end if
    if sigil > 0 and sigil <> type_of_call(root) then fatalerror "Function must have correct type suffix if present"
    ps_funccall = root
$if DEBUG then    
    print "Completed function call"
$endif    
end function

sub ps_funcargs(root)
$if DEBUG then    
    print "Start funcargs"
$endif    
    'This code first builds a candidate type signature, then tries to match that against an instance signature.
    func = ast_nodes(root).ref
    do
        t = tok_next_token
$if DEBUG then            
        print ">>"; tok_human_readable$(t)
$endif
        select case t
        case TOK_CPAREN, TOK_NEWLINE
            'End of the argument list
            tok_please_repeat
            exit do
        case else
            tok_please_repeat
            ps_funcarg root, candidate$
        end select
    loop
    'Now we need to find a signature of func that matches candidate$.
    matching_sig = type_find_sig_match(func, candidate$)
    if matching_sig = 0 then fatalerror "Cannot find matching type signature"
    ast_nodes(root).ref2 = matching_sig
    'Modify argument nodes to add in casts where needed
    for i = 1 to ast_num_children(root)
        expr = ast_get_child(root, i)
        expr_type = type_of_expr(expr)
        arg_type = type_sig_argtype(matching_sig, i)
        if expr_type <> arg_type then
            ast_replace_child root, i, ast_add_cast(expr, arg_type)
        end if
    next i
$if DEBUG then    
    print "Completed funcargs"
$endif    
end sub

sub ps_funcarg(root, candidate$)
$if DEBUG then    
    print "Start funcarg"
$endif    
    expr = ps_expr
    'Declare whether this expression would satisfy a BYREF argument
    if ast_nodes(expr).typ = AST_VAR then flags = TYPE_BYREF
    candidate$ = type_sig_add_arg$(candidate$, type_of_expr(expr), flags)
    ast_attach root, expr
$if DEBUG then    
    print "Completed funcarg"
$endif
end sub

'    dim sig as type_signature_t
'    func = ast_nodes(root).ref
'    type_return_sig func, sig
'    if type_next_sig(sig) then
'        arg_count = 1
'        do
'$if DEBUG then            
'            print "Argument"; arg_count; ":"
'$endif            
'            t = tok_next_token
'$if DEBUG then            
'            print ">>"; tok_human_readable$(t)
'$endif            
'            select case t
'            case TOK_CPAREN, TOK_NEWLINE
'                'Pack up folks, end of the arg list.
'                if arg_count > ast_num_children(root) then
'                    if sig.flags AND TYPE_REQUIRED then fatalerror "Argument cannot be omitted"
'                    arg = ast_add_node(AST_CONSTANT)
'                    ast_nodes(arg).ref = AST_NONE
'                    ast_attach root, arg
'                end if
'                tok_please_repeat
'                exit do
'            case TOK_COMMA
'                if arg_count > ast_num_children(root) then
'                    if sig.flags AND TYPE_REQUIRED then fatalerror "Argument cannot be omitted"
'                    arg = ast_add_node(AST_CONSTANT)
'                    ast_nodes(arg).ref = AST_NONE
'                    ast_attach root, arg
'                end if
'                arg_count = arg_count + 1
'                if type_next_sig(sig) = 0 then fatalerror "More arguments than expected"
'            case else
'                tok_please_repeat
'                ps_funcarg root, sig
'            end select
'        loop
'        'Fill in any extra arguments if they were omitted
'        while type_next_sig(sig)
'            if sig.flags AND TYPE_REQUIRED then fatalerror "A required argument was not supplied"
'            arg = ast_add_node(AST_CONSTANT)
'            ast_nodes(arg).ref = AST_NONE
'            ast_attach root, arg
'        wend
'    end if
'$if DEBUG then    
'    print "Completed funcargs"
'$endif    
'end sub

function ps_variable(token, content$)
$if DEBUG then    
    print "Start variable"
$endif    
    dim he as hentry_t
    'Do array & udt element stuff here.
    'For now only support simple variables.
  
    'New variable?
    if token = TOK_UNKNOWN then
        he.typ = HE_VARIABLE
        htable_add_hentry ucase$(content$), he
        var = htable_last_id
        htable_entries(var).v1 = TYPE_SINGLE
    else
        var = token
    end if

    'Check for type sigil
    sigil = ps_opt_sigil(0)
    if sigil then
        if token <> TOK_UNKNOWN and sigil <> htable_entries(var).v1 then fatalerror "Type suffix does not match existing variable type"
        'Otherwise it's a new variable; set its type
        htable_entries(var).v1 = sigil
    end if
    ps_variable = var
$if DEBUG then    
    print "End variable"
$endif    
end function

sub ps_assert_token(actual, expected)
    if actual <> expected then
        fatalerror "Syntax error: expected " + tok_human_readable(expected) + " got " + tok_human_readable(actual)
    else
$if DEBUG then        
        print "Assert " + tok_human_readable(expected)
$endif        
    end if
end sub

function ps_opt_sigil(expected)
$if DEBUG then    
    print "Start optional sigil"
$endif    
    'if expected > 0 then it must match the type of the sigil
    typ = type_sfx2type(tok_next_token)
    if typ then
        ps_opt_sigil = typ
        if expected and typ <> expected then
            fatalerror "Type sigil is incorrect"
        end if
    else
        ps_opt_sigil = 0
        tok_please_repeat
    end if
$if DEBUG then    
    print "Completed optional sigil"
$endif    
end function

'$include: '../common/type.bm'
'$include: '../common/ast.bm'
'$include: '../common/htable.bm'
'$include: '../common/sif.bm'

'$include: 'pratt.bm'
'$include: 'tokeng.bm'
