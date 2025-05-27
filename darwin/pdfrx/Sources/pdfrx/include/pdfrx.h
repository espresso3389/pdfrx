#ifndef PDFRX_H
#define PDFRX_H

#ifdef __cplusplus
extern "C" {
#endif

// Export the main function needed by Dart FFI
void const *const *pdfrx_binding(void);

// File access functions
struct pdfrx_file_access;
typedef void(*pdfrx_read_function)(void *param, size_t position, unsigned char *pBuf, size_t size);

struct pdfrx_file_access *pdfrx_file_access_create(unsigned long fileSize, pdfrx_read_function readBlock, void *param);
void pdfrx_file_access_destroy(struct pdfrx_file_access *fileAccess);
void pdfrx_file_access_set_value(struct pdfrx_file_access *fileAccess, int retValue);

#ifdef __cplusplus
}
#endif

#endif // PDFRX_H