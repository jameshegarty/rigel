HEX [0-9a-fA-F]+
DEC1 [0-9]

%{
#include <math.h>
%}

%%
{HEX}   {
        printf("A Hex!: %s (%x)\n", yytext, atoi(yytext) );
        return;
        }
%%

void cmdIface()
    {
        yyin=stdin;
        yylex();
    }
