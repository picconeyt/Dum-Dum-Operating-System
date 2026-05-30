// Simple locale handler for DDOS
// stores argument in a global buffer, toggles layout and returns messages

// extern variables defined in kernel.asm
extern unsigned char current_locale;
extern char locale_argument[];

__attribute__((section(".text")))
const char* locale_handler(void) {
    char *arg = locale_argument;
    static char msg[32];

    // no argument supplied
    if (!arg || arg[0] == '\0') {
        return "Usage: locale it | us | show";
    }

    // lower-case first two characters for case-insensitive compare
    char a0 = arg[0];
    if (a0 >= 'A' && a0 <= 'Z')
        a0 += 'a' - 'A';
    char a1 = arg[1];
    if (a1 >= 'A' && a1 <= 'Z')
        a1 += 'a' - 'A';

    // check for "show"
    if (a0 == 's' && a1 == 'h' && arg[2] == 'o' && arg[3] == 'w' && arg[4] == '\0') {
        return "it us";
    }

    // italian
    if (a0 == 'i' && a1 == 't' && arg[2] == '\0') {
        current_locale = 1;
        return "Italian layout selected";
    }

    // us
    if (a0 == 'u' && a1 == 's' && arg[2] == '\0') {
        current_locale = 0;
        return "US layout selected";
    }

    // fall back: return unknown with the actual argument printed
    {
        char *p = msg;
        const char *u = "Unknown locale: ";
        while (*u) {
            *p++ = *u++;
        }
        int i = 0;
        while (arg[i] && (p - msg) < (int)sizeof(msg) - 1) {
            *p++ = arg[i++];
        }
        *p = '\0';
        return msg;
    }
}
