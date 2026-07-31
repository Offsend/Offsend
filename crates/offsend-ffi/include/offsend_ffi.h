#ifndef OFFSEND_FFI_H
#define OFFSEND_FFI_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Offsend FFI — UTF-8 C strings. Caller frees return values and err_out
 * messages with offsend_string_free.
 *
 * Returns heap-allocated JSON or NULL on error. When err_out is non-null,
 * an error message is written there on failure (also needs free).
 */

char* offsend_detect_scan(
    const char* text,
    const char* options_json_or_null,
    char** err_out
);
char* offsend_privacy_audit(
    const char* directory_path,
    const char* options_json_or_null,
    char** err_out
);
char* offsend_privacy_fix(
    const char* directory_path,
    const char* selection_json_or_null,
    const char* options_json_or_null,
    char** err_out
);
char* offsend_check_report(
    const char* directory_path,
    const char* tool_version_or_null,
    char** err_out
);

/* Seal / mask / risk — key buffers are raw 32-byte AES keys. */
char* offsend_seal_spans(
    const unsigned char* key,
    size_t key_len,
    const char* text,
    const char* spans_json,
    size_t max_plaintext_bytes,
    char** err_out
);
char* offsend_unseal_text(
    const unsigned char* key,
    size_t key_len,
    const char* text,
    char** err_out
);
char* offsend_mask_text(
    const char* text,
    const char* entities_json,
    char** err_out
);
char* offsend_restore_text(
    const char* text,
    const char* mapping_json,
    char** err_out
);
char* offsend_risk_assess(
    const char* entity_types_json,
    const char* context_or_null,
    char** err_out
);

void offsend_string_free(char* ptr);

#ifdef __cplusplus
}
#endif

#endif /* OFFSEND_FFI_H */
