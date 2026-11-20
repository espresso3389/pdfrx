// Loaded only by wasm_range_coalescing_test.dart's HTTP fixture server.
functions.testRangeCoalescing = async ({ url, mode }) => {
  const cache = new PdfRangeCache(url, {}, false, undefined);
  const ranges = mode === 'overlap'
    ? [[0, 131072], [65536, 131072]]
    : Array.from({ length: 100 }, (_, i) => [i * 19, 7]);
  const outcomes = await Promise.allSettled(ranges.map(([offset, size]) => cache.download(offset, size)));
  const rejected = outcomes.filter((result) => result.status === 'rejected').length;
  const pendingAfterFailure = cache.pendingDownloads.size;
  if (mode === 'failure' || mode === 'short') await cache.download(0, 1);
  const length = mode === 'overlap' ? 196608 : mode === 'full' ? cache.fileSize : 65536;
  const pointer = Pdfium.wasmExports.malloc(length);
  let correct;
  try {
    correct = cache.read(0, pointer, length) === 1;
    const bytes = new Uint8Array(Pdfium.memory.buffer, pointer, length);
    for (let i = 0; i < length && correct; i++) correct = bytes[i] === i % 251;
  } finally {
    Pdfium.wasmExports.free(pointer);
  }
  const payload = cache.payloadBytes;
  const logical = cache.bytesCached;
  const backingBuffers = new Set(cache.chunks.map((chunk) => chunk.data.buffer));
  const retained = [...backingBuffers].reduce((sum, buffer) => sum + buffer.byteLength, 0);
  let handoffLength = null;
  if (mode === 'full') handoffLength = cache.takeFullData().byteLength;
  const statsUrl = new URL('/stats', url);
  statsUrl.searchParams.set('mode', mode);
  const stats = await (await fetch(statsUrl)).json();
  return {
    ...stats, correct, rejected, payload, logical, retained, handoffLength,
    pendingAfterFailure, pending: cache.pendingDownloads.size, payloadAfterHandoff: cache.payloadBytes,
  };
};
