// Stub for lexbor filesystem functions on embedded ARM
// These functions are not used in exo since we fetch HTML over network

#include <stddef.h>
#include "lexbor/core/fs.h"

lxb_status_t lxb_fs_dir_read(const lxb_char_t *dirpath, lxb_fs_file_type_t type, 
                              lexbor_mraw_t *mraw, lexbor_array_t *array) {
    // Stub: not implemented for embedded ARM
    return LXB_STATUS_ERROR;
}

lxb_char_t * lxb_fs_file_easy_read(const lxb_char_t *full_path, size_t *len) {
    // Stub: not implemented for embedded ARM
    *len = 0;
    return NULL;
}
