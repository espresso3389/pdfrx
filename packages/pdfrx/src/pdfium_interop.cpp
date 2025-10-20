#include <stdlib.h>
#include <condition_variable>
#include <mutex>

#include <fpdfview.h>
#include <fpdf_sysfontinfo.h>

#if defined(_WIN32)
#define PDFRX_EXPORT __declspec(dllexport)
#define PDFRX_INTEROP_API __stdcall
#else
#define PDFRX_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#define PDFRX_INTEROP_API
#endif

struct pdfrx_file_access;

typedef void(PDFRX_INTEROP_API *pdfrx_read_function)(void *param,
                                               size_t position,
                                               unsigned char *pBuf,
                                               size_t size);

struct pdfrx_file_access
{
  FPDF_FILEACCESS fileAccess;
  int retValue;
  pdfrx_read_function readBlock;
  void *param;
  std::mutex mutex;
  std::condition_variable cond;
};

static int PDFRX_INTEROP_API read(void *param,
                            unsigned long position,
                            unsigned char *pBuf,
                            unsigned long size)
{
  auto fileAccess = reinterpret_cast<pdfrx_file_access *>(param);
  std::unique_lock<std::mutex> lock(fileAccess->mutex);
  fileAccess->readBlock(fileAccess->param, position, pBuf, size);
  fileAccess->cond.wait(lock);
  return fileAccess->retValue;
}

extern "C" PDFRX_EXPORT pdfrx_file_access *PDFRX_INTEROP_API pdfrx_file_access_create(unsigned long fileSize, pdfrx_read_function readBlock, void *param)
{
  auto fileAccess = new pdfrx_file_access();
  fileAccess->fileAccess.m_FileLen = fileSize;
  fileAccess->fileAccess.m_GetBlock = read;
  fileAccess->fileAccess.m_Param = fileAccess;
  fileAccess->retValue = 0;
  fileAccess->readBlock = readBlock;
  fileAccess->param = param;
  return fileAccess;
}

extern "C" PDFRX_EXPORT void PDFRX_INTEROP_API pdfrx_file_access_destroy(pdfrx_file_access *fileAccess)
{
  delete fileAccess;
}

extern "C" PDFRX_EXPORT void PDFRX_INTEROP_API pdfrx_file_access_set_value(pdfrx_file_access *fileAccess, int retValue)
{
  std::unique_lock<std::mutex> lock(fileAccess->mutex);
  fileAccess->retValue = retValue;
  fileAccess->cond.notify_one();
}
