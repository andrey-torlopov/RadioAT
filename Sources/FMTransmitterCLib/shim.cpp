#include <cstring>
#include <vector>

#include "fm_transmitter_shim.h"

#if __has_include("fm_transmitter.cpp")
#define FM_TRANSMITTER_AVAILABLE 1
#define main fm_transmitter_main
#include "fm_transmitter.cpp"
#undef main
#else
#define FM_TRANSMITTER_AVAILABLE 0
#endif

int fm_transmitter_run(int argc, const char* argv[]) {
#if FM_TRANSMITTER_AVAILABLE
    std::vector<char*> args;
    args.reserve(static_cast<size_t>(argc) + 1);

    for (int i = 0; i < argc; i++) {
        if (argv[i] == nullptr) {
            args.push_back(nullptr);
            continue;
        }
        size_t n = std::strlen(argv[i]);
        char* s = new char[n + 1];
        std::memcpy(s, argv[i], n + 1);
        args.push_back(s);
    }
    args.push_back(nullptr);

    int rc = fm_transmitter_main(argc, args.data());

    for (char* s : args) {
        delete[] s;
    }
    return rc;
#else
    (void)argc;
    (void)argv;
    return -1;
#endif
}

int fm_transmitter_is_available(void) {
#if FM_TRANSMITTER_AVAILABLE
    return 1;
#else
    return 0;
#endif
}
