// Process-wide PDFium coordinator for multiple Flutter engines in one OS
// process (desktop_multi_window and similar).
//
// PDFium and pdfrx's Dart font mapper are process-global, but each Flutter
// engine has its own Dart isolate family and BackgroundWorker. This library
// is loaded once per process; its statics serialize FPDF_* calls and ensure
// FPDF_InitLibrary runs only once.
//
// acquire/release are not thread-owner-affine: Dart may resume an await on a
// different OS thread. Hold the native mutex only for the duration of these
// functions, not across Dart awaits.

#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#else
#include <pthread.h>
#endif

#if defined(_WIN32)
#define PDFRX_GATE_EXPORT __declspec(dllexport)
#else
#define PDFRX_GATE_EXPORT __attribute__((visibility("default")))
#endif

#if defined(_WIN32)
static CRITICAL_SECTION g_mu;
static CONDITION_VARIABLE g_cv;
static INIT_ONCE g_once = INIT_ONCE_STATIC_INIT;
static LONG g_enabled = 0;

static BOOL CALLBACK PdfrxGateInitSync(PINIT_ONCE once, PVOID param, PVOID *context) {
  (void)once;
  (void)param;
  (void)context;
  InitializeCriticalSection(&g_mu);
  InitializeConditionVariable(&g_cv);
  return TRUE;
}

static void pdfrx_gate_sync_init(void) {
  InitOnceExecuteOnce(&g_once, PdfrxGateInitSync, NULL, NULL);
}

static void pdfrx_gate_lock(void) {
  pdfrx_gate_sync_init();
  EnterCriticalSection(&g_mu);
}

static void pdfrx_gate_unlock(void) {
  LeaveCriticalSection(&g_mu);
}

static void pdfrx_gate_wait(void) {
  SleepConditionVariableCS(&g_cv, &g_mu, INFINITE);
}

static void pdfrx_gate_signal(void) {
  WakeConditionVariable(&g_cv);
}

static void pdfrx_gate_set_enabled(void) {
  InterlockedExchange(&g_enabled, 1);
}

static int pdfrx_gate_get_enabled(void) {
  return InterlockedCompareExchange(&g_enabled, 0, 0);
}
#else
static pthread_mutex_t g_mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_cv = PTHREAD_COND_INITIALIZER;
static int g_enabled = 0;

static void pdfrx_gate_lock(void) {
  pthread_mutex_lock(&g_mu);
}

static void pdfrx_gate_unlock(void) {
  pthread_mutex_unlock(&g_mu);
}

static void pdfrx_gate_wait(void) {
  pthread_cond_wait(&g_cv, &g_mu);
}

static void pdfrx_gate_signal(void) {
  pthread_cond_signal(&g_cv);
}

static void pdfrx_gate_set_enabled(void) {
  pdfrx_gate_lock();
  g_enabled = 1;
  pdfrx_gate_unlock();
}

static int pdfrx_gate_get_enabled(void) {
  int enabled;
  pdfrx_gate_lock();
  enabled = g_enabled;
  pdfrx_gate_unlock();
  return enabled;
}
#endif

static int g_busy = 0;
static int g_init_claimed = 0;

PDFRX_GATE_EXPORT void pdfrx_pdfium_gate_enable(void) {
  pdfrx_gate_set_enabled();
}

PDFRX_GATE_EXPORT int pdfrx_pdfium_gate_is_enabled(void) {
  return pdfrx_gate_get_enabled();
}

PDFRX_GATE_EXPORT void pdfrx_pdfium_gate_acquire(void) {
  pdfrx_gate_lock();
#if defined(_WIN32)
  if (InterlockedCompareExchange(&g_enabled, 0, 0) == 0) {
    pdfrx_gate_unlock();
    return;
  }
#else
  if (!g_enabled) {
    pdfrx_gate_unlock();
    return;
  }
#endif
  while (g_busy) {
    pdfrx_gate_wait();
  }
  g_busy = 1;
  pdfrx_gate_unlock();
}

PDFRX_GATE_EXPORT void pdfrx_pdfium_gate_release(void) {
  pdfrx_gate_lock();
#if defined(_WIN32)
  if (InterlockedCompareExchange(&g_enabled, 0, 0) == 0) {
    pdfrx_gate_unlock();
    return;
  }
#else
  if (!g_enabled) {
    pdfrx_gate_unlock();
    return;
  }
#endif
  g_busy = 0;
  pdfrx_gate_signal();
  pdfrx_gate_unlock();
}

// Caller must hold acquire(). First claim in the process wins.
PDFRX_GATE_EXPORT int pdfrx_pdfium_gate_claim_init(void) {
  int first;
  pdfrx_gate_lock();
#if defined(_WIN32)
  if (InterlockedCompareExchange(&g_enabled, 0, 0) == 0) {
    pdfrx_gate_unlock();
    return 1;
  }
#else
  if (!g_enabled) {
    pdfrx_gate_unlock();
    return 1;
  }
#endif
  first = g_init_claimed ? 0 : 1;
  g_init_claimed = 1;
  pdfrx_gate_unlock();
  return first;
}
