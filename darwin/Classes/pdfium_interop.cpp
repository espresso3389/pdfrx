#include <stdlib.h>
#include <thread>
#include <condition_variable>
#include <mutex>
#include <fpdfview.h>

#if defined(_WIN32)
#define EXPORT __declspec(dllexport)
#define INTEROP_API __stdcall
#else
#define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#define INTEROP_API
#endif

struct pdfrx_file_access;

typedef void(INTEROP_API *pdfrx_read_function)(void *param,
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

static int INTEROP_API read(void *param,
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

extern "C" EXPORT pdfrx_file_access *INTEROP_API pdfrx_file_access_create(unsigned long fileSize, pdfrx_read_function readBlock, void *param)
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

extern "C" EXPORT void INTEROP_API pdfrx_file_access_destroy(pdfrx_file_access *fileAccess)
{
  delete fileAccess;
}

extern "C" EXPORT void INTEROP_API pdfrx_file_access_set_value(pdfrx_file_access *fileAccess, int retValue)
{
  std::unique_lock<std::mutex> lock(fileAccess->mutex);
  fileAccess->retValue = retValue;
  fileAccess->cond.notify_one();
}

#if defined(__APPLE__)
extern "C" EXPORT void const * const * INTEROP_API pdfrx_binding() {
  static const void* bindings[] = {
    reinterpret_cast<void*>(FPDF_InitLibraryWithConfig),
    reinterpret_cast<void*>(FPDF_InitLibrary),
    reinterpret_cast<void*>(FPDF_DestroyLibrary),
    reinterpret_cast<void*>(FPDF_SetSandBoxPolicy),
    //reinterpret_cast<void*>(FPDF_SetPrintMode),
    reinterpret_cast<void*>(FPDF_LoadDocument),
    reinterpret_cast<void*>(FPDF_LoadMemDocument),
    reinterpret_cast<void*>(FPDF_LoadMemDocument64),
    reinterpret_cast<void*>(FPDF_LoadCustomDocument),
    reinterpret_cast<void*>(FPDF_GetFileVersion),
    reinterpret_cast<void*>(FPDF_GetLastError),
    reinterpret_cast<void*>(FPDF_DocumentHasValidCrossReferenceTable),
    reinterpret_cast<void*>(FPDF_GetTrailerEnds),
    reinterpret_cast<void*>(FPDF_GetDocPermissions),
    //reinterpret_cast<void*>(FPDF_GetDocUserPermissions),
    reinterpret_cast<void*>(FPDF_GetSecurityHandlerRevision),
    reinterpret_cast<void*>(FPDF_GetPageCount),
    reinterpret_cast<void*>(FPDF_LoadPage),
    reinterpret_cast<void*>(FPDF_GetPageWidthF),
    reinterpret_cast<void*>(FPDF_GetPageWidth),
    reinterpret_cast<void*>(FPDF_GetPageHeightF),
    reinterpret_cast<void*>(FPDF_GetPageHeight),
    reinterpret_cast<void*>(FPDF_GetPageBoundingBox),
    reinterpret_cast<void*>(FPDF_GetPageSizeByIndexF),
    reinterpret_cast<void*>(FPDF_GetPageSizeByIndex),
    //reinterpret_cast<void*>(FPDF_RenderPage),
    reinterpret_cast<void*>(FPDF_RenderPageBitmap),
    reinterpret_cast<void*>(FPDF_RenderPageBitmapWithMatrix),
    reinterpret_cast<void*>(FPDF_ClosePage),
    reinterpret_cast<void*>(FPDF_CloseDocument),
    reinterpret_cast<void*>(FPDF_DeviceToPage),
    reinterpret_cast<void*>(FPDF_PageToDevice),
    reinterpret_cast<void*>(FPDF_VIEWERREF_GetPrintScaling),
    reinterpret_cast<void*>(FPDF_VIEWERREF_GetNumCopies),
    reinterpret_cast<void*>(FPDF_VIEWERREF_GetPrintPageRange),
    reinterpret_cast<void*>(FPDF_VIEWERREF_GetPrintPageRangeCount),
    reinterpret_cast<void*>(FPDF_VIEWERREF_GetPrintPageRangeElement),
    reinterpret_cast<void*>(FPDF_VIEWERREF_GetDuplex),
    reinterpret_cast<void*>(FPDF_VIEWERREF_GetName),
    reinterpret_cast<void*>(FPDF_CountNamedDests),
    reinterpret_cast<void*>(FPDF_GetNamedDestByName),
    reinterpret_cast<void*>(FPDF_GetNamedDest),
    reinterpret_cast<void*>(FPDF_GetXFAPacketCount),
    reinterpret_cast<void*>(FPDF_GetXFAPacketName),
    reinterpret_cast<void*>(FPDF_GetXFAPacketContent)
  };
  return bindings;
}
#endif
