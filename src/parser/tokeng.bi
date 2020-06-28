'$include: '../../rules/ts_data.bi'
'$include: '../../rules/token_data.bi'

type tokeniser_state_t
    file_handle as long 'Set to -1 to read from console
    index as long
    curstate as long
    has_data as long
    linestart as long
    raw_line_in as string
end type

dim shared tokeng_state as tokeniser_state_t

dim shared tok_content$
dim shared tok_token as long
dim shared tok_next_content$
dim shared tok_next_token as long
