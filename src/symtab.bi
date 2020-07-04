'Copyright 2020 Luke Ceddia
'SPDX-License-Identifier: Apache-2.0
'symtab.bi - Declarations for symbol table

type symtab_entry_t
    identifier as string
    typ as long
    'the vn are generic parameters whose meaning depends on typ.
    v1 as long
    v2 as long
    v3 as long
end type

'A generic entry. No vn parameters are used.
const SYM_GENERIC = 1
'A function with infix notation.
'v1 -> reference to the type signature
'v2 -> binding power (controls precedence)
'v3 -> associativity (1/0 = right/left)
const SYM_INFIX = 2
'A function with prefix notation (and parentheses are not required)
'v1 -> reference to the type signature
'v2 -> binding power (controls precedence)
const SYM_PREFIX = 3
'A variable.
'v1 -> the data type
'v2 -> index in this scope (in each scope, first variable has 1, second has 2 etc.)
const SYM_VARIABLE = 4
'A function (subs too!)
'v1 -> reference to the type signature
const SYM_FUNCTION = 5

dim shared symtab(1000) as symtab_entry_t
dim shared symtab_last_entry
dim shared symtab_map(1750)