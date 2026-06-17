/* dshell.c – Dummers Programming Language Shell logic
   Called from kernel.asm with 16-bit real-mode pointer parameters.
   Returns 0 to exit the shell, 1 to continue. */

int shell_process(const char* input, char* output)
{
    /* skip leading spaces */
    while (*input == ' ') input++;

    /* ----- exit ----- */
    if (input[0] == 'e' && input[1] == 'x' && input[2] == 'i' && input[3] == 't' &&
        (input[4] == '\0' || input[4] == ' '))
    {
        return 0;   /* tell ASM to leave the shell */
    }

    /* ----- print "..." ----- */
    if (input[0] == 'p' && input[1] == 'r' && input[2] == 'i' && input[3] == 'n' &&
        input[4] == 't' && (input[5] == ' ' || input[5] == '\0'))
    {
        const char* ptr = input + 5;
        while (*ptr == ' ') ptr++;

        if (*ptr == '"')
        {
            ptr++;                      /* skip opening quote */
            while (*ptr && *ptr != '"')
            {
                *output++ = *ptr++;
            }
            *output = '\0';
            return 1;
        }
        else
        {
            const char* err = "Syntax: print \"text\"";
            for (int i = 0; err[i]; i++) *output++ = err[i];
            *output = '\0';
            return 1;
        }
    }

    /* ----- unknown command ----- */
    const char* err = "Unknown command. Type exit to leave.";
    for (int i = 0; err[i]; i++) *output++ = err[i];
    *output = '\0';
    return 1;
}
