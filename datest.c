// Force the compiler to use 16-bit logic for the string pointer
__attribute__((section(".text")))
const char* get_test_message() {
    return "High-Level 16-bit Kernel Functional!";
}
