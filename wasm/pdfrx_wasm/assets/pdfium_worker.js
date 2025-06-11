//
// A small implementation of a Web Worker that uses pdfium.wasm to render PDF files.
//

/**
 * PDFium WASM module imports
 */
const Pdfium = {
  /**
   * @param {WebAssembly.Exports} wasmExports 
   */
  initWith: function(wasmExports) {
    Pdfium.wasmExports = wasmExports;
    Pdfium.memory = Pdfium.wasmExports.memory;
    Pdfium.wasmTable = Pdfium.wasmExports["__indirect_function_table"];
    Pdfium.stackSave = Pdfium.wasmExports["emscripten_stack_get_current"];
    Pdfium.stackRestore = Pdfium.wasmExports["_emscripten_stack_restore"];
    Pdfium.setThrew = Pdfium.wasmExports["setThrew"];
  },

  /**
   * @type {WebAssembly.Exports}
   */
  wasmExports: null,
  /**
   * @type {WebAssembly.Memory}
   */
  memory: null,
  /**
   * @type {WebAssembly.Table}
   */
  wasmTable: null,
  /**
   * @type {function():number}
   */
  stackSave: null,
  /**
   * @type {function(number):void}
   */
  stackRestore: null,
  /**
   * @type {function(number, number):void}
   */
  setThrew: null,

  /**
   * Invoke a function from the WASM table
   * @param {number} index Function index
   * @param {function(function())} func Function to call
   * @returns {*} Result of the function
   */
  invokeFunc: function(index, func) {
    const sp = Pdfium.stackSave();
    try {
      return func(Pdfium.wasmTable.get(index));
    } catch (e) {
      Pdfium.stackRestore(sp);
      if (e !== e + 0) throw e;
      Pdfium.setThrew(1, 0);
    }
   }
}

/**
 * @typedef {Object} FileContext Defines I/O functions for a file
 * @property {number} size File size
 * @property {function(FileDescriptorContext, Uint8Array):number} read read(context, data)
 * @property {function(FileDescriptorContext):void|undefined} close close(context)
 * @property {function(FileDescriptorContext, Uint8Array):number|undefined} write write(context, data)
 * @property {function(FileDescriptorContext):number|undefined} sync sync(context)
 */

/**
 * @typedef {Object} FileDescriptorContext Defines I/O functions for a file descriptor
 * @property {number} size File size
 * @property {function(FileDescriptorContext, Uint8Array):number} read read(context, data)
 * @property {function(FileDescriptorContext):void|undefined} close close(context)
 * @property {function(FileDescriptorContext, Uint8Array):number|undefined} write write(context, data)
 * @property {function(FileDescriptorContext):number|undefined} sync sync(context)
 * @property {string} fileName
 * @property {number} fd
 * @property {number} flags
 * @property {number} mode
 * @property {number} dirfd
 * @property {number} position Current position
 */

/**
 * @typedef {Object} DirectoryContext Defines I/O functions for a directory file descriptor
 * @property {string[]} entries Directory entries (For directories, the name should be terminated with /)
 */

/**
 * @typedef {Object} DirectoryFileDescriptorContext Defines I/O functions for a directory file descriptor
 * @property {string[]} entries Directory entries (For directories, the name should be terminated with /)
 * @property {string} fileName
 * @property {number} fd
 * @property {number} dirfd
 * @property {number} position Current entry index
 */

/**
 * Emulate file system for PDFium
 */
class FileSystemEmulator {
  constructor() {
    /**
     * Filename to I/O functions/data
     * @type {Object<string, FileContext|DirectoryContext>}
     */
    this.fn2context = {};
    /**
     * File descriptor to I/O functions/data
     * @type {Object<number, FileDescriptorContext|DirectoryFileDescriptorContext>}
     */
    this.fd2context = {};
    /**
     * Last assigned file descriptor
     * @type {number}
     */
    this.fdAssignedLast = 1000;
  }

  /**
   * Register file
   * @param {string} fn Filename
   * @param {FileContext} context I/O functions/data
   */
  registerFile(fn, context) {
    this.fn2context[fn] = context;
  }

  /**
   * Register file with ArrayBuffer
   * @param {string} fn Filename
   * @param {ArrayBuffer} data File data
   */
  registerFileWithData(fn, data) {
    data = data.buffer != null ? data.buffer : data;
    this.registerFile(fn, {
      size: data.byteLength,
      read: function(context, buffer) {
        try {
          const size = Math.min(buffer.byteLength, data.byteLength - context.position);
          const array = new Uint8Array(data, context.position, size);
          buffer.set(array);
          context.position += array.byteLength;
          return array.length;
        } catch (err) {
          console.error(`read error: ${_error(err)}`);
          return 0;
        }
      },
    });
  }

  /**
   * Register directory
   * @param {string} fn Filename
   * @param {*} entries Directory entries (For directories, the name should be terminated with /)
   */
  registerDirectoryWithEntries(fn, entries) {
    this.registerFile(fn, { entries });
  }

  /**
   * Unregister file/directory context
   * @param {string} fn Filename
   */
  unregisterFile(fn) {
    delete this.fn2context[fn];
  }

  /**
   * Open a file
   * @param {number} dirfd Directory file descriptor
   * @param {number} fileNamePtr Pointer to buffer that contains filename
   * @param {number} flags File open flags
   * @param {number} mode File open mode
   * @returns {number} File descriptor
   */
  openFile(dirfd, fileNamePtr, flags, mode) {
    const fn = StringUtils.utf8BytesToString(new Uint8Array(Pdfium.memory.buffer, fileNamePtr, 2048));
    const funcs = this.fn2context[fn];
    if (funcs) {
      const fd = ++this.fdAssignedLast;
      this.fd2context[fd] = { ...funcs, fd, flags, mode, dirfd, position: 0 };
      return fd;
    }
    console.error(`openFile: not found: ${dirfd}/${fn}`);
    return -1;
  }

  /**
   * Close a file
   * @param {number} fd File descriptor
   */
  closeFile(fd) {
    const context = this.fd2context[fd];
    context.close?.call(context);
    delete this.fd2context[fd];
  }

  /**
   * Seek to a position in a file
   * @param {number} fd File descriptor
   * @param {number} offset_low Offset low
   * @param {number} offset_high Offset high
   * @param {number} whence Whence
   * @param {number} newOffset New offset
   * @returns {number} New offset
   */
  seek(fd, offset_low, offset_high, whence, newOffset) {
    const context = this.fd2context[fd];
    if (offset_high !== 0) {
      throw new Error('seek: offset_high is not supported');
    }
    switch (whence) {
      case 0: // SEEK_SET
        context.position = offset_low;
        break;
      case 1: // SEEK_CUR
        context.position += offset_low;
        break;
      case 2: // SEEK_END
        context.position = context.size + offset_low;
        break;
    }
    const offsetLowHigh = new Uint32Array(Pdfium.memory.buffer, newOffset, 2);
    offsetLowHigh[0] = context.position;
    offsetLowHigh[1] = 0;
  }

  /**
   * fd__write
   * @param {num} fd 
   * @param {num} iovs 
   * @param {num} iovs_len 
   * @param {num} ret_ptr 
   */
  write(fd, iovs, iovs_len, ret_ptr) {
    const context = this.fd2context[fd];
    let total = 0;
    for (let i = 0; i < iovs_len; i++) {
      const iov = new Int32Array(Pdfium.memory.buffer, iovs + i * 8, 2);
      const ptr = iov[0];
      const len = iov[1];
      const written = context.write(context, new Uint8Array(Pdfium.memory.buffer, ptr, len));
      total += written;
      if (written < len) break;
    }
    const bytes_written = new Uint32Array(Pdfium.memory.buffer, ret_ptr, 1);
    bytes_written[0] = written;
  }

  /**
   * fd_read
   * @param {num} fd 
   * @param {num} iovs 
   * @param {num} iovs_len 
   * @param {num} ret_ptr 
   */
  read(fd,iovs, iovs_len, ret_ptr) {
    /** @type {FileDescriptorContext} */
    const context = this.fd2context[fd];
    let total = 0;
    for (let i = 0; i < iovs_len; i++) {
      const iov = new Int32Array(Pdfium.memory.buffer, iovs + i * 8, 2);
      const ptr = iov[0];
      const len = iov[1];
      const read = context.read(context, new Uint8Array(Pdfium.memory.buffer, ptr, len));
      total += read;
      if (read < len) break;
    }
    const bytes_read = new Uint32Array(Pdfium.memory.buffer, ret_ptr, 1);
    bytes_read[0] = total;
  }

  sync(fd) {
    const context = this.fd2context[fd];
    return context.sync(context);
  }

  /**
   * __syscall_fstat64
   * @param {num} fd 
   * @param {num} statbuf 
   * @returns {num}
   */
  fstat(fd, statbuf) {
    const context = this.fd2context[fd];
    const buffer = new Int32Array(Pdfium.memory.buffer, statbuf, 92);
    buffer[6] = context.size; // st_size
    buffer[7]  = 0;
    return 0;
  }

  /**
   * __syscall_stat64
   * @param {num} pathnamePtr 
   * @param {num} statbuf 
   * @returns {num}
   */
  stat64(pathnamePtr, statbuf) {
    const fn = StringUtils.utf8BytesToString(new Uint8Array(Pdfium.memory.buffer, pathnamePtr, 2048));
    const funcs = this.fn2context[fn];
    if (funcs) {
      const buffer = new Int32Array(Pdfium.memory.buffer, statbuf, 92);
      buffer[6] = funcs.size; // st_size
      buffer[7]  = 0;
      return 0;
    }
    return -1;
  }

  /**
   * __syscall_getdents64
   * @param {num} fd
   * @param {num} dirp
   * @param {num} count
   * @returns {num}
   */
  getdents64(fd, dirp, count) {
    /** @type {DirectoryFileDescriptorContext} */
    const context = this.fd2context[fd];
    const entries = context.entries;
    if (entries == null) return 0;
    let written = 0;
    const DT_REG = 8, DT_DIR = 4;
    _memset(dirp, 0, count);
    for (let i = context.position; i < entries.length; i++) {
      let d_type, d_name;
      if (entries[i].endsWith('/')) {
        d_type = DT_DIR;
        d_name = entries[i].substring(0, entries[i].length - 1);
      } else {
        d_type = DT_REG;
        d_name = entries[i];
      }
      const d_nameLength = StringUtils.lengthBytesUTF8(d_name) + 1;
      const size = 8 + 8 + 2 + 1 + d_nameLength;

      if (written + size > count) break;
      const buffer = new Uint8Array(Pdfium.memory.buffer, dirp + written, size);
      // d_off
      const d_off = written + size;
      buffer[8] = d_off & 255;
      buffer[9] = (d_off >> 8) & 255;
      // d_reclen
      buffer[16] = size & 255;
      buffer[17] = (size >> 8) & 255;
      // d_type
      buffer[18] = d_type;
      // d_name
      StringUtils.stringToUtf8Bytes(d_name, new Uint8Array(Pdfium.memory.buffer, dirp + written + 19, d_nameLength));
      written = d_off;
    }
    return written;
  }
};

function _error(e) { return e.stack ? e.stack.toString() : e.toString(); }

function _notImplemented(name) { throw new Error(`${name} is not implemented`); }

const fileSystem = new FileSystemEmulator();

const emEnv = {
  __assert_fail: function(condition, filename, line, func) { throw new Error(`Assertion failed: ${condition} at ${filename}:${line} (${func})`); },
  _emscripten_memcpy_js: function(dest, src, num) { new Uint8Array(Pdfium.memory.buffer).copyWithin(dest, src, src + num); },
  __syscall_openat: fileSystem.openFile.bind(fileSystem),
  __syscall_fstat64: fileSystem.fstat.bind(fileSystem),
  __syscall_ftruncate64: function(fd, zero, zero2, zero3) { _notImplemented('__syscall_ftruncate64'); },
  __syscall_stat64: fileSystem.stat64.bind(fileSystem),
  __syscall_newfstatat: function(dirfd, pathnamePtr, statbuf, flags) { _notImplemented('__syscall_newfstatat'); },
  __syscall_lstat64: function(pathnamePtr, statbuf) { _notImplemented('__syscall_lstat64'); },
  __syscall_fcntl64: function(fd, cmd, arg) { _notImplemented('__syscall_fcntl64'); },
  __syscall_ioctl: function(fd, request, arg) { _notImplemented('__syscall_ioctl'); },
  __syscall_getdents64: fileSystem.getdents64.bind(fileSystem),
  __syscall_unlinkat: function(dirfd, pathnamePtr, flags) { _notImplemented('__syscall_unlinkat'); },
  __syscall_rmdir: function(pathnamePtr) { _notImplemented('__syscall_rmdir'); },
  _abort_js: function(what) { throw new Error(what); },
  _emscripten_throw_longjmp: function() { _notImplemented('longjmp'); },
  _gmtime_js: function(time, tmPtr) {
    const date = new Date(time * 1000);
    const tm = new Int32Array(Pdfium.memory.buffer, tmPtr, 9);
    tm[0] = date.getUTCSeconds();
    tm[1] = date.getUTCMinutes();
    tm[2] = date.getUTCHours();
    tm[3] = date.getUTCDate();
    tm[4] = date.getUTCMonth();
    tm[5] = date.getUTCFullYear() - 1900;
    tm[6] = date.getUTCDay();
    tm[7] = 0; // dst
    tm[8] = 0; // gmtoff
   },
  _localtime_js: function(time, tmPtr) { _notImplemented('_localtime_js'); },
  _tzset_js: function() { },
  emscripten_date_now: function() { return Date.now(); },
  emscripten_errn: function() { _notImplemented('emscripten_errn'); },
  emscripten_resize_heap: function(requestedSizeInBytes) {
    const maxHeapSizeInBytes = 2 * 1024 * 1024 * 1024; // 2GB
    if (requestedSizeInBytes > maxHeapSizeInBytes) {
      console.error(`emscripten_resize_heap: Cannot enlarge memory, asked for ${requestedPageCount} bytes but limit is ${maxHeapSizeInBytes}`);
      return false;
    }

    const pageSize = 65536;
    const oldPageCount = ((Pdfium.memory.buffer.byteLength + pageSize - 1) / pageSize)|0;
    const requestedPageCount = ((requestedSizeInBytes + pageSize - 1) / pageSize)|0;
    const newPageCount = Math.max(oldPageCount * 1.5, requestedPageCount) | 0;
    try {
      Pdfium.memory.grow(newPageCount - oldPageCount);
      console.log(`emscripten_resize_heap: ${oldPageCount} => ${newPageCount}`);
      return true;
    } catch (e) {
      console.error(`emscripten_resize_heap: Failed to resize heap: ${_error(e)}`);
      return false;
    }
  },
  exit: function(status) { _notImplemented('exit'); },
  invoke_ii: function(index, a) { return Pdfium.invokeFunc(index, function(func) { return func(a); });},
  invoke_iii: function(index, a, b) { return Pdfium.invokeFunc(index, function(func) { return func(a, b); });},
  invoke_iiii: function(index, a, b, c) { return Pdfium.invokeFunc(index, function(func) { return func(a, b, c); });},
  invoke_iiiii: function(index, a, b, c, d) { return Pdfium.invokeFunc(index, function(func) { return func(a, b, c, d); });},
  invoke_v: function(index) { return Pdfium.invokeFunc(index, function(func) { func(); });},
  invoke_viii: function(index, a, b, c) { Pdfium.invokeFunc(index, function(func) { func(a, b, c); });},
  invoke_viiii: function(index, a, b, c, d) { Pdfium.invokeFunc(index, function(func) { func(a, b, c, d); });},
  print: function(text) { console.log(text); },
  printErr: function(text) { console.error(text); },
};

const wasi = {
  proc_exit: function(code) { _notImplemented('proc_exit'); },
  environ_sizes_get: function(environCount, environBufSize) { _notImplemented('environ_sizes_get'); },
  environ_get: function(environ, environBuf) { _notImplemented('environ_get'); },
  fd_close: fileSystem.closeFile.bind(fileSystem),
  fd_seek: fileSystem.seek.bind(fileSystem),
  fd_write: fileSystem.write.bind(fileSystem),
  fd_read: fileSystem.read.bind(fileSystem),
  fd_sync: fileSystem.sync.bind(fileSystem),
};


/** @type {string[]} */
const fontNames = [];

/**
 * @param {{data: ArrayBuffer, name: string}} params 
 */
function registerFont(params) {
  const {name, data} = params;
  const fileDir = '/usr/share/fonts';
  fontNames.push(fileDir + name);
  fileSystem.registerDirectoryWithEntries(fileDir, name);

  fileSystem.registerFileWithData(name, data);
}

/**
 * @param {{url: string, name: string}} params 
 */
async function registerFontFromUrl(params) {
  const {name, url} = params;
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error("Failed to fetch font from URL: " + fontUrl);
  }
  const data = await response.arrayBuffer();
  registerFont({name, data});
}

/**
 * @param {{url: string, password: string|undefined}} params 
 */
async function loadDocumentFromUrl(params) {
  const url = params.url;
  const password = params.password || "";
  
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error("Failed to fetch PDF from URL: " + url);
  }

  return loadDocumentFromData({data: await response.arrayBuffer(), url: url, password});
}

/**
 * @param {{data: ArrayBuffer, password: string|undefined}} params 
 */
function loadDocumentFromData(params) {
  const data = params.data;
  const password = params.password || "";

  const sizeThreshold = 1024 * 1024; // 1MB
  if (data.byteLength < sizeThreshold) {
    const buffer = Pdfium.wasmExports.malloc(data.byteLength);
    if (buffer === 0) {
      throw new Error("Failed to allocate memory for PDF data (${data.byteLength} bytes)");
    }
    new Uint8Array(Pdfium.memory.buffer, buffer, data.byteLength).set(new Uint8Array(data));
    const passwordPtr = StringUtils.allocateUTF8(password);
    const docHandle = Pdfium.wasmExports.FPDF_LoadMemDocument(
      buffer,
      data.byteLength,
      passwordPtr,
    );
    StringUtils.freeUTF8(passwordPtr);
    return _loadDocument(docHandle, () => Pdfium.wasmExports.free(buffer));
  }
  
  const tempFileName = params.url ?? '/tmp/temp.pdf';
  fileSystem.registerFileWithData(tempFileName, data);

  const fileNamePtr = StringUtils.allocateUTF8(tempFileName);
  const passwordPtr = StringUtils.allocateUTF8(password);
  const docHandle = Pdfium.wasmExports.FPDF_LoadDocument(fileNamePtr, passwordPtr);
  StringUtils.freeUTF8(passwordPtr);
  StringUtils.freeUTF8(fileNamePtr);
  return _loadDocument(docHandle, () => fileSystem.unregisterFile(tempFileName));

}

/** @type {Object<number, function():void>} */
const disposers = {};

/**
 * @typedef {{docHandle: number,permissions: number, securityHandlerRevision: number, pages: PdfPage[], formHandle: number, formInfo: number}} PdfDocument
 * @typedef {{pageIndex: number, width: number, height: number, rotation: number}} PdfPage
 * @typedef {{errorCode: number, errorCodeStr: string|undefined, message: string}} PdfError
 */

/**
 * @param {number} docHandle 
 * @param {function():void} onDispose
 * @returns {PdfDocument|PdfError}
 */
function _loadDocument(docHandle, onDispose) {
  try {
    if (!docHandle) {
      const error = Pdfium.wasmExports.FPDF_GetLastError();
      const errorStr = _errorMappings[error];
      return { errorCode: error, errorCodeStr: _errorMappings[error], message: `Failed to load document` };
    }
  
    const pageCount = Pdfium.wasmExports.FPDF_GetPageCount(docHandle);
    const permissions = Pdfium.wasmExports.FPDF_GetDocPermissions(docHandle);
    const securityHandlerRevision = Pdfium.wasmExports.FPDF_GetSecurityHandlerRevision(docHandle);
  
    const formInfoSize = 35 * 4;
    let formInfo = Pdfium.wasmExports.malloc(formInfoSize);
    const uint32 = new Uint32Array(Pdfium.memory.buffer, formInfo, formInfoSize >> 2);
    uint32[0] = 1; // version
    const formHandle = Pdfium.wasmExports.FPDFDOC_InitFormFillEnvironment(docHandle, formInfo);
    if (formHandle === 0) {
      formInfo = 0;
    }
  
    const pages = [];
    for (let i = 0; i < pageCount; i++) {
      const pageHandle = Pdfium.wasmExports.FPDF_LoadPage(docHandle, i);
      if (!pageHandle) {
        const error = Pdfium.wasmExports.FPDF_GetLastError();
        throw new Error(`FPDF_LoadPage failed (${_getErrorMessage(error)})`);
      }
  
      pages.push({
        pageIndex: i,
        width: Pdfium.wasmExports.FPDF_GetPageWidth(pageHandle),
        height: Pdfium.wasmExports.FPDF_GetPageHeight(pageHandle),
        rotation: Pdfium.wasmExports.FPDFPage_GetRotation(pageHandle)
      });
      Pdfium.wasmExports.FPDF_ClosePage(pageHandle);
    }
  
    disposers[docHandle] = onDispose;
    return {
      docHandle: docHandle,
      permissions: permissions,
      securityHandlerRevision: securityHandlerRevision,
      pages: pages,
      formHandle: formHandle,
      formInfo: formInfo,
    };
  } catch (e) {
    Pdfium.wasmExports.free(formInfo);
    delete disposers[docHandle];
    onDispose();
    throw e;
  }
}

/**
 * @param {{formHandle: number, formInfo: number, docHandle: number}} params 
 */
function closeDocument(params) {
  if (params.formHandle) {
    try {
      Pdfium.wasmExports.FPDFDOC_ExitFormFillEnvironment(params.formHandle);
    } catch (e) {}
  }
  Pdfium.wasmExports.free(params.formInfo);
  Pdfium.wasmExports.FPDF_CloseDocument(params.docHandle);
  disposers[params.docHandle]();
  delete disposers[params.docHandle];
  return { message: "Document closed" };
}

/**
 * @typedef {{pageIndex: number, command: string, params: number[]}} PdfDest
 * @typedef {{title: string, dest: PdfDest, children: OutlineNode[]}} OutlineNode
 */

/**
 * @param {{docHandle: number}} params 
 * @return {OutlineNode[]}
 */
function loadOutline(params) {
  return {
    outline: _getOutlineNodeSiblings(Pdfium.wasmExports.FPDFBookmark_GetFirstChild(params.docHandle, null), params.docHandle),
  };
}

/**
 * @param {number} bookmark 
 * @param {number} docHandle 
 * @return {OutlineNode[]}
 */
function _getOutlineNodeSiblings(bookmark, docHandle) {
  /** @type {OutlineNode[]} */
  const siblings = [];
  while (bookmark) {
    const titleBufSize = Pdfium.wasmExports.FPDFBookmark_GetTitle(bookmark, null, 0);
    const titleBuf = Pdfium.wasmExports.malloc(titleBufSize);
    Pdfium.wasmExports.FPDFBookmark_GetTitle(bookmark, titleBuf, titleBufSize);
    const title = StringUtils.utf16BytesToString(new Uint8Array(Pdfium.memory.buffer, titleBuf, titleBufSize));
    Pdfium.wasmExports.free(titleBuf);
    siblings.push({
      title: title,
      dest: _pdfDestFromDest(Pdfium.wasmExports.FPDFBookmark_GetDest(docHandle, bookmark), docHandle),
      children: _getOutlineNodeSiblings(Pdfium.wasmExports.FPDFBookmark_GetFirstChild(docHandle, bookmark), docHandle),
    });
    bookmark = Pdfium.wasmExports.FPDFBookmark_GetNextSibling(docHandle, bookmark);
  }
  return siblings;
}

/**
 * @param {{docHandle: number, pageIndex: number}} params
 * @return {number} Page handle
 */
function loadPage(params) {
  const pageHandle = Pdfium.wasmExports.FPDF_LoadPage(params.docHandle, params.pageIndex);
  if (!pageHandle) {
    throw new Error(`Failed to load page ${params.pageIndex} from document ${params.docHandle}`);
  }
  return { pageHandle: pageHandle };
}

/**
 * @param {{pageHandle: number}} params
*/
function closePage(params) {
  Pdfium.wasmExports.FPDF_ClosePage(params.pageHandle);
  return { message: "Page closed" };
}

/**
 * 
 * @param {{
 * docHandle: number,
 * pageIndex: number,
 * x: number,
 * y: number,
 * width: number,
 * height: number,
 * fullWidth: number,
 * fullHeight: number,
 * backgroundColor: number,
 * annotationRenderingMode: number,
 * flags: number,
 * formHandle: number
 * }} params 
 * @returns 
 */
function renderPage(params) {
  const {
    docHandle,
    pageIndex,
    x = 0,
    y = 0,
    width = 800,
    height = 600,
    fullWidth = width,
    fullHeight = height,
    backgroundColor,
    annotationRenderingMode = 0,
    flags = 0,
    formHandle,
  } = params;

  let pageHandle = 0;
  let bufferPtr = 0;
  let bitmap = 0;

  try {
    pageHandle = Pdfium.wasmExports.FPDF_LoadPage(docHandle, pageIndex);
    if (!pageHandle) {
      throw new Error(`Failed to load page ${pageIndex} from document ${docHandle}`);
    }
  
    const bufferSize = width * height * 4;
    bufferPtr = Pdfium.wasmExports.malloc(bufferSize);
    if (!bufferPtr) {
      throw new Error("Failed to allocate memory for rendering");
    }
    const FPDFBitmap_BGRA = 4;
    bitmap = Pdfium.wasmExports.FPDFBitmap_CreateEx(
      width,
      height,
      FPDFBitmap_BGRA,
      bufferPtr,
      width * 4
    );
    if (!bitmap) {
      throw new Error("Failed to create bitmap for rendering");
    }
  
    Pdfium.wasmExports.FPDFBitmap_FillRect(bitmap, 0, 0, width, height, backgroundColor);
  
    const FPDF_ANNOT = 1;
    const FPDF_RENDER_NO_SMOOTHTEXT = 0x1000;
    const FPDF_RENDER_NO_SMOOTHIMAGE = 0x2000;
    const FPDF_RENDER_NO_SMOOTHPATH = 0x4000;
    const PdfAnnotationRenderingMode_none = 0;
    const PdfAnnotationRenderingMode_annotationAndForms = 2;

    Pdfium.wasmExports.FPDF_RenderPageBitmap(
      bitmap,
      pageHandle,
      -x,
      -y,
      fullWidth,
      fullHeight,
      0,
      flags | (annotationRenderingMode !== PdfAnnotationRenderingMode_none ? FPDF_ANNOT : 0),
    );
  
    if (formHandle && annotationRenderingMode == PdfAnnotationRenderingMode_annotationAndForms) {
      Pdfium.wasmExports.FPDF_FFLDraw(formHandle, bitmap, pageHandle, -x, -y, fullWidth, fullHeight, 0, flags);
    }

    let copiedBuffer = new ArrayBuffer(bufferSize);
    let b = new Uint8Array(copiedBuffer);
    b.set(new Uint8Array(Pdfium.memory.buffer, bufferPtr, bufferSize));

    return {
      result: {
        imageData: copiedBuffer,
        width: width,
        height: height
      },
      transfer: [copiedBuffer],
    };
  } finally {
    Pdfium.wasmExports.FPDF_ClosePage(pageHandle);
    Pdfium.wasmExports.FPDFBitmap_Destroy(bitmap);
    Pdfium.wasmExports.free(bufferPtr);
  }
}

function _memset(ptr, value, num) {
  const buffer = new Uint8Array(Pdfium.memory.buffer, ptr, num);
  for (let i = 0; i < num; i++) {
    buffer[i] = value;
  }
}

const CR = 0x0D, LF = 0x0A, SPC = 0x20;

/**
 * 
 * @param {{pageIndex: number, docHandle: number}} params 
 * @returns {{fullText: string, charRects: number[][], fragments: number[]}}
 */
function loadText(params) {
  const { pageIndex, docHandle } = params;
  const pageHandle = Pdfium.wasmExports.FPDF_LoadPage(docHandle, pageIndex);
  const textPage = Pdfium.wasmExports.FPDFText_LoadPage(pageHandle);
  if (textPage == null) return {fullText: '', charRects: [], fragments: []};
  const charCount = Pdfium.wasmExports.FPDFText_CountChars(textPage);
  /** @type {number[][]} */
  const charRects = [];
  /** @type {number[]} */
  const fragments = [];
  const fullText = _loadTextInternal(textPage, 0, charCount, charRects, fragments);
  Pdfium.wasmExports.FPDFText_ClosePage(textPage);
  Pdfium.wasmExports.FPDF_ClosePage(pageHandle);
  return {fullText, charRects, fragments};
}

/**
 * @param {number} textPage
 * @param {number} from
 * @param {number} length
 * @param {number[][]} charRects
 * @param {number[]} fragments
 * @returns 
 */
function _loadTextInternal(textPage, from, length, charRects, fragments) {
  const fullText = _getText(textPage, from, length);
  const rectBuffer = Pdfium.wasmExports.malloc(8 * 4); // double[4]
  const sb = {
    str: '',
    push(text) { this.str += text; },
    get length() { return this.str.length; },
  };
  let lineStart = 0, wordStart = 0;
  let lastChar;
  for (let i = 0; i < length; i++) {
    const char = fullText.charCodeAt(i);
    if (char == CR) {
      if (i + 1 < length && fullText.codePointAt(i + 1) == LF) {
        lastChar = char;
        continue;
      }
    }
    if (char === CR || char === LF) {
      if (_makeLineFlat(charRects, lineStart, sb.length, sb)) {
        sb.push('\r\n');
        _appendDummy(charRects);
        _appendDummy(charRects);
        fragments.push(sb.length - wordStart);
        lineStart = wordStart = sb.length;
      }
      lastChar = char;
      continue;
    }

    Pdfium.wasmExports.FPDFText_GetCharBox(textPage, from + i,
      rectBuffer, // L
      rectBuffer + 8 * 2, // R
      rectBuffer + 8 * 3, // B
      rectBuffer + 8); // T
    const rect = Array.from(new Float64Array(Pdfium.memory.buffer, rectBuffer, 4));
    if (char === SPC) {
      if (lastChar == SPC) continue;
      if (sb.length > wordStart) {
        fragments.push(sb.length - wordStart);
      }
      sb.push(String.fromCharCode(char));
      charRects.push(rect);
      fragments.push(1);
      wordStart = sb.length;
      lastChar = char;
      continue;
    }

    if (sb.length > lineStart) {
      const columnHeightThreshold = 72.0; // 1 inch
      const prev = charRects[charRects.length - 1];
      if (prev[0] > rect[0] || prev[3] + columnHeightThreshold < rect[3]) {
        if (_makeLineFlat(charRects, lineStart, sb.length, sb)) {
          if (sb.length > wordStart) {
            fragments.push(sb.length - wordStart);
          }
          lineStart = wordStart = sb.length;
        }
      }
    }

    sb.push(String.fromCharCode(char));
    charRects.push(rect);
    lastChar = char;
  }

  if (_makeLineFlat(charRects, lineStart, sb.length, sb)) {
    if (sb.length > wordStart) {
      fragments.push(sb.length - wordStart);
    }
  }

  Pdfium.wasmExports.free(rectBuffer);
  return sb.str;
}

function _appendDummy(rects, width = 1) {
  if (rects.length === 0) return;
  const last = rects[rects.length - 1];
  rects.push([last[0], last[1], last[2] + width, last[3]]);
}

/// return true if any meaningful characters in the line (start -> end)
function _makeLineFlat(rects, start, end, sb) {
  if (start >= end) return false;
  const str = sb.str;
  const bounds = _boundingRect(rects, start, end);
  let prev;
  for (let i = start; i < end; i++) {
    const rect = rects[i];
    const char = str.codePointAt(i);
    if (char === SPC) {
      const next = i + 1 < end ? rects[i + 1][0] : null;
      rects[i] = [prev != null ? prev : rect[0], bounds[1], next != null ? next : rect[2], bounds[3]];
      prev = null;
    } else {
      rects[i] = [prev != null ? prev : rect[0], bounds[1], rect[2], bounds[3]];
      prev = rect[2]; // right
    }
  }
  return true;
}

function _boundingRect(rects, start, end) {
  let l = Number.MAX_VALUE, t = 0, r = 0, b = Number.MAX_VALUE;
  for (let i = start; i < end; i++) {
    const rect = rects[i];
    l = Math.min(l, rect[0]);
    t = Math.max(t, rect[1]);
    r = Math.max(r, rect[2]);
    b = Math.min(b, rect[3]);
  }
  return [l, t, r, b];
}

function _getText(textPage, from, length) {
  const count = Pdfium.wasmExports.FPDFText_CountChars(textPage);
  let sb = '';
  for (let i = 0; i < count; i++) {
    sb += String.fromCodePoint(Pdfium.wasmExports.FPDFText_GetUnicode(textPage, i));
  }
  return sb;

  // const textBuffer = Pdfium.wasmExports.malloc(length * 2 + 2);
  // const count = Pdfium.wasmExports.FPDFText_GetText(textPage, from, length, textBuffer);
  // const text = StringUtils.utf16BytesToString(new Uint8Array(Pdfium.memory.buffer, textBuffer, count * 2));
  // Pdfium.wasmExports.free(textBuffer);
  // return text;
}


/**
 * @typedef {{rects: number[][], dest: url: string}} PdfUrlLink
 * @typedef {{rects: number[][], dest: PdfDest}} PdfDestLink
 */

/**
 * @param {{docHandle: number, pageIndex: number}} params
 * @returns {{links: Array<PdfUrlLink|PdfDestLink>}}
 */
function loadLinks(params) {
  const links = [..._loadAnnotLinks(params), ..._loadLinks(params)];
  return {
    links: links,
  };
}

/**
 * @param {{docHandle: number, pageIndex: number}} params
 * @returns {Array<PdfUrlLink>}
 */
function _loadLinks(params) {
  const { pageIndex, docHandle } = params;
  const pageHandle = Pdfium.wasmExports.FPDF_LoadPage(docHandle, pageIndex);
  const textPage = Pdfium.wasmExports.FPDFText_LoadPage(pageHandle);
  if (textPage == null) return [];
  const linkPage = Pdfium.wasmExports.FPDFLink_LoadWebLinks(textPage);
  if (linkPage == null) return [];

  const links = [];
  const count = Pdfium.wasmExports.FPDFLink_CountWebLinks(linkPage);
  const rectBuffer = Pdfium.wasmExports.malloc(8 * 4); // double[4]
  for (let i = 0; i < count; i++) {
    const rectCount = Pdfium.wasmExports.FPDFLink_CountRects(linkPage, i);
    const rects = [];
    for (let j = 0; j < rectCount; j++) {
      Pdfium.wasmExports.FPDFLink_GetRect(linkPage, i, j, rectBuffer, rectBuffer + 8, rectBuffer + 16, rectBuffer + 24);
      rects.push(Array.from(new Float64Array(Pdfium.memory.buffer, rectBuffer, 4)));
    }
    links.push({
      rects: rects,
      url: _getLinkUrl(linkPage, i),
    });
  }
  Pdfium.wasmExports.free(rectBuffer);
  Pdfium.wasmExports.FPDFLink_CloseWebLinks(linkPage);
  Pdfium.wasmExports.FPDFText_ClosePage(textPage);
  Pdfium.wasmExports.FPDF_ClosePage(pageHandle);
  return links;
}

/**
 * @param {number} linkPage
 * @param {number} linkIndex 
 * @returns {string}
 */
function _getLinkUrl(linkPage, linkIndex) {
  const urlLength = Pdfium.wasmExports.FPDFLink_GetURL(linkPage, linkIndex, null, 0);
  const urlBuffer = Pdfium.wasmExports.malloc(urlLength * 2);
  Pdfium.wasmExports.FPDFLink_GetURL(linkPage, linkIndex, urlBuffer, urlLength);
  const url = StringUtils.utf16BytesToString(new Uint8Array(Pdfium.memory.buffer, urlBuffer, urlLength * 2));
  Pdfium.wasmExports.free(urlBuffer);
  return url;
}

/**
 * @param {{docHandle: number, pageIndex: number}} params
 * @returns {Array<PdfDestLink|PdfUrlLink>}
 */
function _loadAnnotLinks(params) {
  const { pageIndex, docHandle } = params;
  const pageHandle = Pdfium.wasmExports.FPDF_LoadPage(docHandle, pageIndex);
  const count = Pdfium.wasmExports.FPDFPage_GetAnnotCount(pageHandle);
  const rectF = Pdfium.wasmExports.malloc(4 * 4); // float[4]
  const links = [];
  for (let i = 0; i < count; i++) {
    const annot = Pdfium.wasmExports.FPDFPage_GetAnnot(pageHandle, i);
    Pdfium.wasmExports.FPDFAnnot_GetRect(annot, rectF);
    const [l, t, r, b] = new Float32Array(Pdfium.memory.buffer, rectF, 4);
    const rect = [
      l,
      t > b ? t : b,
      r,
      t > b ? b : t,
    ];
    const dest = _processAnnotDest(annot, docHandle);
    if (dest) {
      links.push({rects: [rect], dest: _pdfDestFromDest(dest, docHandle)});
    } else {
      const url = _processAnnotLink(annot, docHandle);
      if (url) {
        links.push({rects: [rect], url: url});
      }
    }
    Pdfium.wasmExports.FPDFPage_CloseAnnot(annot);
  }
  Pdfium.wasmExports.free(rectF);
  Pdfium.wasmExports.FPDF_ClosePage(pageHandle);
  return links;
}

/**
 * 
 * @param {number} annot 
 * @param {number} docHandle 
 * @returns {number|null} Dest
 */
function _processAnnotDest(annot, docHandle) {
  const link = Pdfium.wasmExports.FPDFAnnot_GetLink(annot);

  // firstly check the direct dest
  const dest = Pdfium.wasmExports.FPDFLink_GetDest(docHandle, link);
  if (dest) return dest;

  const action = Pdfium.wasmExports.FPDFLink_GetAction(link);
  if (!action) return null;
  const PDFACTION_GOTO = 1;
  switch (Pdfium.wasmExports.FPDFAction_GetType(action)) {
    case PDFACTION_GOTO:
      return Pdfium.wasmExports.FPDFAction_GetDest(docHandle, action);
    default:
      return null;
  }
}

/**
 * @param {number} annot 
 * @param {number} docHandle 
 * @returns {string|null} URI
 */
function _processAnnotLink(annot, docHandle) {
  const link = Pdfium.wasmExports.FPDFAnnot_GetLink(annot);
  const action = Pdfium.wasmExports.FPDFLink_GetAction(link);
  if (!action) return null;
  const PDFACTION_URI = 3;
  switch (Pdfium.wasmExports.FPDFAction_GetType(action)) {
    case PDFACTION_URI:
      const size = Pdfium.wasmExports.FPDFAction_GetURIPath(docHandle, action, null, 0);
      const buf = Pdfium.wasmExports.malloc(size);
      Pdfium.wasmExports.FPDFAction_GetURIPath(docHandle, action, buf, size);
      const uri = StringUtils.utf8BytesToString(new Uint8Array(Pdfium.memory.buffer, buf, size));
      Pdfium.wasmExports.free(buf);
      return uri;
    default:
      return null;
  }
}

/// [PDF 32000-1:2008, 12.3.2.2 Explicit Destinations, Table 151](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf#page=374)
const pdfDestCommands = ['unknown', 'xyz', 'fit', 'fitH', 'fitV', 'fitR', 'fitB', 'fitBH', 'fitBV'];

/**
 * @param {number} dest 
 * @param {number} docHandle 
 * @returns {PdfDest|null}
 */
function _pdfDestFromDest(dest, docHandle) {
  if (dest === 0) return null;
  const buf = Pdfium.wasmExports.malloc(40);
  const pageIndex = Pdfium.wasmExports.FPDFDest_GetDestPageIndex(docHandle, dest);
  const type = Pdfium.wasmExports.FPDFDest_GetView(dest, buf, buf + 4);
  const [count] = new Int32Array(Pdfium.memory.buffer, buf, 1);
  const params = Array.from(new Float32Array(Pdfium.memory.buffer, buf + 4, count));
  Pdfium.wasmExports.free(buf);
  if (type !== 0) {
    return {
      pageIndex,
      command: pdfDestCommands[type],
      params,
    };
  }
  return null;
}

/**
 * Functions that can be called from the main thread
 */
const functions = {
  registerFont,
  registerFontFromUrl,
  loadDocumentFromUrl,
  loadDocumentFromData,
  closeDocument,
  loadOutline,
  loadPage,
  closePage,
  renderPage,
  loadText,
  loadLinks,
};

function handleRequest(data) {
  const { id, command, parameters = {} } = data;
  
  try {
    const result = functions[command](parameters);
    if (result instanceof Promise) {
      result
        .then(finalResult => {
          if (finalResult.result != null && finalResult.transfer != null) {
            postMessage({ id, status: "success", result: finalResult.result }, finalResult.transfer);
          } else {
            postMessage({ id, status: "success", result: finalResult });
          }
        })
        .catch(err => {
          postMessage({
            id,
            status: "error",
            error: _error(err)
          });
        });
    } else {
      if (result.result != null && result.transfer != null) {
        postMessage({ id, status: "success", result: result.result }, result.transfer);
      } else {
        postMessage({ id, status: "success", result: result });
      }
    }
  } catch (err) {
    postMessage({
      id,
      status: "error",
      error: _error(err)
    });
  }
}

let messagesBeforeInitialized = [];

console.log(`PDFium worker initialized: ${self.location.href}`);


/**
 * Entrypoint
 */
console.log(`Loading PDFium WASM module from ${pdfiumWasmUrl}`);
WebAssembly.instantiateStreaming(fetch(pdfiumWasmUrl), {
  env: emEnv,
  wasi_snapshot_preview1: wasi
}).then(result => {
  Pdfium.initWith(result.instance.exports);

  Pdfium.wasmExports.FPDF_InitLibrary();
  postMessage({ type: "ready" });
  
  messagesBeforeInitialized.forEach(event => handleRequest(event.data));
  messagesBeforeInitialized = null;
}).catch(err => {
  console.error('Failed to load WASM module:', err);
  postMessage({ type: "error", error: _error(err) });
});

onmessage = function(e) {
  const data = e.data;
  if (data && data.id && data.command) {
    if (messagesBeforeInitialized) {
      messagesBeforeInitialized.push(e);
      return;
    }
    handleRequest(data);
  } else {
    console.error("Received improperly formatted message:", data);
  }
};

const _errorMappings = {
  0: "FPDF_ERR_SUCCESS",
  1: "FPDF_ERR_UNKNOWN",
  2: "FPDF_ERR_FILE",
  3: "FPDF_ERR_FORMAT",
  4: "FPDF_ERR_PASSWORD",
  5: "FPDF_ERR_SECURITY",
  6: "FPDF_ERR_PAGE",
  7: "FPDF_ERR_XFALOAD",
  8: "FPDF_ERR_XFALAYOUT",
};

function _getErrorMessage(errorCode) {
  const error = _errorMappings[errorCode];
  return error ? `${error} (${errorCode})` : `Unknown error (${errorCode})`;
}

/**
 * String utilities
 */
class StringUtils {
  /**
   * UTF-16 string to bytes
   * @param {number[]} buffer 
   * @returns {string} Converted string
   */
  static utf16BytesToString(buffer) {
    let endPtr = 0;
    while (buffer[endPtr] || buffer[endPtr + 1]) endPtr += 2;
    const str = new TextDecoder('utf-16le').decode(new Uint8Array(buffer.buffer, buffer.byteOffset, endPtr));
    return str;
  }
  /**
   * UTF-8 bytes to string
   * @param {number[]} buffer 
   * @returns {string} Converted string
   */
  static utf8BytesToString(buffer) {
    let endPtr = 0;
    while (buffer[endPtr] && !(endPtr >= buffer.length)) ++endPtr;
    
    let str = '';
    let idx = 0;
    while (idx < endPtr) {
      let u0 = buffer[idx++];
      if (!(u0 & 0x80)) {
        str += String.fromCharCode(u0);
        continue;
      }
      const u1 = buffer[idx++] & 63;
      if ((u0 & 0xE0) == 0xC0) {
        str += String.fromCharCode(((u0 & 31) << 6) | u1);
        continue;
      }
      const u2 = buffer[idx++] & 63;
      if ((u0 & 0xF0) == 0xE0) {
        u0 = ((u0 & 15) << 12) | (u1 << 6) | u2;
      } else {
        u0 = ((u0 & 7) << 18) | (u1 << 12) | (u2 << 6) | (buffer[idx++] & 63);
      }
      if (u0 < 0x10000) {
        str += String.fromCharCode(u0);
      } else {
        const ch = u0 - 0x10000;
        str += String.fromCharCode(0xD800 | (ch >> 10), 0xDC00 | (ch & 0x3FF));
      }
    }
    return str;
  }
  /**
   * String to UTF-8 bytes
   * @param {string} str 
   * @param {number[]} buffer
   * @returns {number} Number of bytes written to the buffer
   */
  static stringToUtf8Bytes(str, buffer) {
    let idx = 0;
    for(let i = 0; i < str.length; ++i) {
      let u = str.charCodeAt(i);
      if(u >= 0xD800 && u <= 0xDFFF) {
        const u1 = str.charCodeAt(++i);
        u = 0x10000 + ((u & 0x3FF) << 10) | (u1 & 0x3FF);
      }
      if(u <= 0x7F) {
        buffer[idx++] = u;
      } else if(u <= 0x7FF) {
        buffer[idx++] = 0xC0 | (u >> 6);
        buffer[idx++] = 0x80 | (u & 63);
      } else if(u <= 0xFFFF) {
        buffer[idx++] = 0xE0 | (u >> 12);
        buffer[idx++] = 0x80 | ((u >> 6) & 63);
        buffer[idx++] = 0x80 | (u & 63);
      } else {
        buffer[idx++] = 0xF0 | (u >> 18);
        buffer[idx++] = 0x80 | ((u >> 12) & 63);
        buffer[idx++] = 0x80 | ((u >> 6) & 63);
        buffer[idx++] = 0x80 | (u & 63);
      }
    }
    buffer[idx++] = 0;
    return idx;
  }
  /**
   * Calculate length of UTF-8 string in bytes (it does not contain the terminating '\0' character)
   * @param {string} str String to calculate length
   * @returns {number} Number of bytes
   */
  static lengthBytesUTF8(str) {
    let len = 0;
    for(let i = 0; i < str.length; ++i) {
      let u = str.charCodeAt(i);
      if(u >= 0xD800 && u <= 0xDFFF) {
        u = 0x10000 + ((u & 0x3FF) << 10) | (str.charCodeAt(++i) & 0x3FF);
      }
      if(u <= 0x7F) len += 1;
      else if(u <= 0x7FF) len += 2;
      else if(u <= 0xFFFF) len += 3;
      else len += 4;
    }
    return len;
  }
  /**
   * Allocate memory for UTF-8 string
   * @param {string} str 
   * @returns {number} Pointer to allocated buffer that contains UTF-8 string. The buffer should be released by calling [freeUTF8].
   */
  static allocateUTF8(str) {
    if (str == null) return 0;
    const size = this.lengthBytesUTF8(str) + 1;
    const ptr = Pdfium.wasmExports.malloc(size);
    this.stringToUtf8Bytes(str, new Uint8Array(Pdfium.memory.buffer, ptr, size));
    return ptr;
  }
  /**
   * Release memory allocated for UTF-8 string
   * @param {number} ptr Pointer to allocated buffer
   */
  static freeUTF8(ptr) {
    Pdfium.wasmExports.free(ptr);
  }
};
