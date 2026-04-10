/*
 * PdfAne — AIR Native Extension (Windows x86)
 * Build with build.bat (Visual Studio 32-bit toolchain) + AIR SDK 51.x.
 *
 * Define USE_PDFIUM=1 and add PDFium include/lib to render real PDFs (see build.bat).
 */

#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <stdint.h>
#include <algorithm>
#include <vector>
#include <string>
#include <cstring>
#include <cstdio>
#include <cmath>

#include "FlashRuntimeExtensions.h"

#if USE_PDFIUM
#include "fpdfview.h"
#endif

struct PdfContext {
    std::string pathUtf8;
    std::string lastError;
    uint32_t pageCount;
#if USE_PDFIUM
    FPDF_DOCUMENT doc;
    std::vector<uint8_t> fileBytes;
#endif
    PdfContext() : pageCount(0)
#if USE_PDFIUM
        , doc(nullptr)
#endif
    {}
};

static void SetLastErrorStr(PdfContext* pc, const char* msg) {
    if (pc) {
        pc->lastError = msg ? msg : "";
    }
}

static bool FileExistsUtf8(const char* utf8Path) {
    if (!utf8Path || !*utf8Path) {
        return false;
    }
    int wlen = MultiByteToWideChar(CP_UTF8, 0, utf8Path, -1, nullptr, 0);
    if (wlen <= 0) {
        return false;
    }
    std::vector<wchar_t> wbuf(static_cast<size_t>(wlen));
    MultiByteToWideChar(CP_UTF8, 0, utf8Path, -1, wbuf.data(), wlen);
    DWORD attr = GetFileAttributesW(wbuf.data());
    return attr != INVALID_FILE_ATTRIBUTES && (attr & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

static bool ReadFileUtf8(const char* utf8Path, std::vector<uint8_t>& out, std::string& err) {
    out.clear();
    int wlen = MultiByteToWideChar(CP_UTF8, 0, utf8Path, -1, nullptr, 0);
    if (wlen <= 0) {
        err = "Invalid path encoding";
        return false;
    }
    std::vector<wchar_t> wbuf(static_cast<size_t>(wlen));
    MultiByteToWideChar(CP_UTF8, 0, utf8Path, -1, wbuf.data(), wlen);
    HANDLE h = CreateFileW(wbuf.data(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                           FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) {
        err = "Cannot open file";
        return false;
    }
    LARGE_INTEGER sz{};
    if (!GetFileSizeEx(h, &sz) || sz.QuadPart <= 0 || sz.QuadPart > 128LL * 1024 * 1024) {
        CloseHandle(h);
        err = "Invalid file size";
        return false;
    }
    DWORD n = static_cast<DWORD>(sz.QuadPart);
    out.resize(n);
    DWORD rd = 0;
    if (!ReadFile(h, out.data(), n, &rd, nullptr) || rd != n) {
        CloseHandle(h);
        err = "Read failed";
        return false;
    }
    CloseHandle(h);
    return true;
}

static const uint8_t* MemFindBytes(const uint8_t* hay, size_t hayLen, const char* needle) {
    size_t n = strlen(needle);
    if (n == 0 || hayLen < n) {
        return nullptr;
    }
    for (size_t i = 0; i + n <= hayLen; ++i) {
        if (memcmp(hay + i, needle, n) == 0) {
            return hay + i;
        }
    }
    return nullptr;
}

static bool ParseUInt32(const uint8_t* p, size_t rem, uint32_t* outVal) {
    size_t i = 0;
    while (i < rem && (p[i] == ' ' || p[i] == '\t' || p[i] == '\r' || p[i] == '\n')) {
        ++i;
    }
    if (i >= rem || p[i] < '0' || p[i] > '9') {
        return false;
    }
    uint64_t v = 0;
    while (i < rem && p[i] >= '0' && p[i] <= '9') {
        v = v * 10u + static_cast<unsigned>(p[i] - '0');
        if (v > 0xFFFFFFFFull) {
            return false;
        }
        ++i;
    }
    *outVal = static_cast<uint32_t>(v);
    return true;
}

/** Heuristic page count without PDFium (linearized /N, /Count, or /Type /Page). */
static uint32_t GuessPdfPageCount(const uint8_t* data, size_t len) {
    if (len < 16) {
        return 1;
    }
    const size_t headLim = len < 65536u ? len : 65536u;
    const uint8_t* lin = MemFindBytes(data, headLim, "/Linearized");
    if (lin) {
        size_t off = static_cast<size_t>(lin - data);
        size_t span = len - off;
        if (span > 4096u) {
            span = 4096u;
        }
        const uint8_t* nKey = MemFindBytes(lin, span, "/N ");
        if (nKey) {
            uint32_t n = 0;
            if (ParseUInt32(nKey + 3, span - static_cast<size_t>(nKey - lin) - 3, &n) && n > 0 && n < 100000u) {
                return n;
            }
        }
    }
    const size_t scanLen = len < 262144u ? len : 262144u;
    uint32_t bestCount = 0;
    for (size_t i = 0; i + 7 < scanLen; ++i) {
        if (memcmp(data + i, "/Count ", 7) == 0) {
            uint32_t c = 0;
            if (ParseUInt32(data + i + 7, scanLen - (i + 7), &c) && c > bestCount && c < 100000u) {
                bestCount = c;
            }
        }
    }
    if (bestCount > 0) {
        return bestCount;
    }
    static const char pat[] = "/Type /Page";
    const size_t plen = sizeof(pat) - 1;
    uint32_t pageObjs = 0;
    const size_t cap = len < 524288u ? len : 524288u;
    for (size_t i = 0; i + plen + 1 < cap; ++i) {
        if (memcmp(data + i, pat, plen) == 0) {
            uint8_t next = data[i + plen];
            if (next != 's') {
                ++pageObjs;
            }
        }
    }
    if (pageObjs > 0 && pageObjs < 100000u) {
        return pageObjs;
    }
    return 1;
}

#if !USE_PDFIUM
static void RenderPlaceholder(PdfContext* pc, uint32_t pageIndex, FREBitmapData& bm) {
    uint32_t w = bm.width;
    uint32_t h = bm.height;
    uint32_t stride = bm.lineStride32;
    uint32_t* bits = bm.bits32;
    for (uint32_t y = 0; y < h; ++y) {
        uint32_t* row = bits + y * stride;
        for (uint32_t x = 0; x < w; ++x) {
            uint8_t g = static_cast<uint8_t>((x ^ y ^ pageIndex * 13) & 0xFF);
            uint32_t c = 0xFF000000u | (g << 16) | (g << 8) | (200u - (g >> 1));
            row[x] = c;
        }
    }
    (void)pc;
}
#else
static void FlipBitmapVertical(uint32_t* bits, uint32_t width, uint32_t height, uint32_t stride32) {
    std::vector<uint32_t> tmp(width);
    for (uint32_t y = 0; y < height / 2; ++y) {
        uint32_t* a = bits + y * stride32;
        uint32_t* b = bits + (height - 1u - y) * stride32;
        memcpy(tmp.data(), a, static_cast<size_t>(width) * sizeof(uint32_t));
        memcpy(a, b, static_cast<size_t>(width) * sizeof(uint32_t));
        memcpy(b, tmp.data(), static_cast<size_t>(width) * sizeof(uint32_t));
    }
}

/**
 * PDFium BGRA scan order is bottom-up vs Flash BitmapData (top row = top of screen).
 * Only vertical flip is applied; horizontal flip made pages look left-right mirrored in AIR.
 * Page is scaled uniformly and centered in the target (letterbox).
 */
static bool RenderPdfiumPage(PdfContext* pc, uint32_t pageIndex, FREBitmapData& bm, std::string& err) {
    if (!pc->doc) {
        err = "No document";
        return false;
    }
    int total = FPDF_GetPageCount(pc->doc);
    if (total <= 0) {
        err = "No pages";
        return false;
    }
    if (pageIndex >= static_cast<uint32_t>(total)) {
        err = "Page out of range";
        return false;
    }
    FPDF_PAGE page = FPDF_LoadPage(pc->doc, static_cast<int>(pageIndex));
    if (!page) {
        err = "LoadPage failed";
        return false;
    }

    uint32_t w = bm.width;
    uint32_t h = bm.height;
    uint32_t stride = bm.lineStride32;
    uint32_t* bits = bm.bits32;

    FPDF_BITMAP pdfBmp = FPDFBitmap_CreateEx(static_cast<int>(w), static_cast<int>(h), FPDFBitmap_BGRA,
                                             bits, static_cast<int>(stride * 4));
    if (!pdfBmp) {
        FPDF_ClosePage(page);
        err = "Bitmap_CreateEx failed";
        return false;
    }
    FPDFBitmap_FillRect(pdfBmp, 0, 0, static_cast<int>(w), static_cast<int>(h), 0xFFFFFFFF);

    double pw = static_cast<double>(FPDF_GetPageWidth(page));
    double ph = static_cast<double>(FPDF_GetPageHeight(page));
    if (pw <= 1.0 || ph <= 1.0 || !std::isfinite(pw) || !std::isfinite(ph)) {
        FPDFBitmap_Destroy(pdfBmp);
        FPDF_ClosePage(page);
        err = "Bad page size";
        return false;
    }
    double sx = static_cast<double>(w) / pw;
    double sy = static_cast<double>(h) / ph;
    double sc = (std::min)(sx, sy);
    int rw = static_cast<int>(floor(pw * sc));
    int rh = static_cast<int>(floor(ph * sc));
    if (rw < 1) {
        rw = 1;
    }
    if (rh < 1) {
        rh = 1;
    }
    int ox = (static_cast<int>(w) - rw) / 2;
    int oy = (static_cast<int>(h) - rh) / 2;
    if (ox < 0) {
        ox = 0;
    }
    if (oy < 0) {
        oy = 0;
    }

    FPDF_RenderPageBitmap(pdfBmp, page, ox, oy, rw, rh, 0, FPDF_ANNOT);
    FPDFBitmap_Destroy(pdfBmp);
    FPDF_ClosePage(page);

    FlipBitmapVertical(bits, w, h, stride);
    return true;
}
#endif

static FREObject BoolToFre(bool v) {
    FREObject o = nullptr;
    FRENewObjectFromBool(v ? 1u : 0u, &o);
    return o;
}

static FREObject fnOpen(FREContext ctx, void*, uint32_t argc, FREObject argv[]) {
    void* nd = nullptr;
    FREGetContextNativeData(ctx, &nd);
    auto* pc = static_cast<PdfContext*>(nd);
    if (!pc || argc < 1) {
        return BoolToFre(false);
    }
    uint32_t len = 0;
    const uint8_t* utf8 = nullptr;
    if (FREGetObjectAsUTF8(argv[0], &len, &utf8) != FRE_OK || !utf8) {
        SetLastErrorStr(pc, "Bad path argument");
        return BoolToFre(false);
    }
    {
        const char* p = reinterpret_cast<const char*>(utf8);
        size_t cap = static_cast<size_t>(len);
        size_t pathLen = (cap > 0) ? strnlen(p, cap) : 0;
        pc->pathUtf8.assign(p, pathLen);
    }
    pc->lastError.clear();
#if USE_PDFIUM
    if (pc->doc) {
        FPDF_CloseDocument(pc->doc);
        pc->doc = nullptr;
    }
    pc->fileBytes.clear();
    pc->pageCount = 0;
    if (!ReadFileUtf8(pc->pathUtf8.c_str(), pc->fileBytes, pc->lastError)) {
        return BoolToFre(false);
    }
    pc->doc = FPDF_LoadMemDocument64(pc->fileBytes.data(), pc->fileBytes.size(), nullptr);
    if (!pc->doc) {
        unsigned long errMem = FPDF_GetLastError();
        pc->fileBytes.clear();
        pc->doc = FPDF_LoadDocument(pc->pathUtf8.c_str(), nullptr);
        if (!pc->doc) {
            unsigned long errFile = FPDF_GetLastError();
            char buf[96];
            sprintf_s(buf, "Load PDF failed: mem err %lu, file err %lu", errMem, errFile);
            SetLastErrorStr(pc, buf);
            return BoolToFre(false);
        }
    }
    pc->pageCount = static_cast<uint32_t>(FPDF_GetPageCount(pc->doc));
    if (pc->pageCount == 0) {
        SetLastErrorStr(pc, "Zero pages");
        FPDF_CloseDocument(pc->doc);
        pc->doc = nullptr;
        pc->fileBytes.clear();
        return BoolToFre(false);
    }
#else
    if (!FileExistsUtf8(pc->pathUtf8.c_str())) {
        SetLastErrorStr(pc, "File not found");
        pc->pageCount = 0;
        return BoolToFre(false);
    }
    {
        std::vector<uint8_t> buf;
        std::string readErr;
        pc->pageCount = 1;
        if (ReadFileUtf8(pc->pathUtf8.c_str(), buf, readErr) && buf.size() >= 8) {
            uint32_t g = GuessPdfPageCount(buf.data(), buf.size());
            if (g >= 1 && g < 100000u) {
                pc->pageCount = g;
            }
        }
    }
#endif
    return BoolToFre(true);
}

static FREObject fnClose(FREContext ctx, void*, uint32_t, FREObject[]) {
    void* nd = nullptr;
    FREGetContextNativeData(ctx, &nd);
    auto* pc = static_cast<PdfContext*>(nd);
    if (pc) {
#if USE_PDFIUM
        if (pc->doc) {
            FPDF_CloseDocument(pc->doc);
            pc->doc = nullptr;
        }
        pc->fileBytes.clear();
#endif
        pc->pathUtf8.clear();
        pc->pageCount = 0;
        pc->lastError.clear();
    }
    return nullptr;
}

static FREObject fnGetPageCount(FREContext ctx, void*, uint32_t, FREObject[]) {
    void* nd = nullptr;
    FREGetContextNativeData(ctx, &nd);
    auto* pc = static_cast<PdfContext*>(nd);
    uint32_t n = pc ? pc->pageCount : 0;
    FREObject o = nullptr;
    FRENewObjectFromUint32(n, &o);
    return o;
}

static FREObject fnRenderPage(FREContext ctx, void*, uint32_t argc, FREObject argv[]) {
    void* nd = nullptr;
    FREGetContextNativeData(ctx, &nd);
    auto* pc = static_cast<PdfContext*>(nd);
    if (!pc || argc < 2) {
        return BoolToFre(false);
    }
    int32_t pageIndex = 0;
    if (FREGetObjectAsInt32(argv[0], &pageIndex) != FRE_OK) {
        SetLastErrorStr(pc, "Bad page index");
        return BoolToFre(false);
    }
    FREBitmapData bm{};
    if (FREAcquireBitmapData(argv[1], &bm) != FRE_OK) {
        SetLastErrorStr(pc, "Not BitmapData");
        return BoolToFre(false);
    }
    if (bm.width == 0 || bm.height == 0 || !bm.bits32) {
        FREReleaseBitmapData(argv[1]);
        SetLastErrorStr(pc, "Empty bitmap");
        return BoolToFre(false);
    }
    bool ok = false;
#if USE_PDFIUM
    std::string err;
    ok = RenderPdfiumPage(pc, static_cast<uint32_t>(pageIndex), bm, err);
    if (!ok) {
        SetLastErrorStr(pc, err.c_str());
    }
#else
    if (pc->pageCount == 0) {
        SetLastErrorStr(pc, "No document open");
    } else if (pageIndex < 0 || static_cast<uint32_t>(pageIndex) >= pc->pageCount) {
        SetLastErrorStr(pc, "Page out of range");
    } else {
        RenderPlaceholder(pc, static_cast<uint32_t>(pageIndex), bm);
        ok = true;
    }
#endif
    if (ok) {
        FREInvalidateBitmapDataRect(argv[1], 0, 0, bm.width, bm.height);
    }
    FREReleaseBitmapData(argv[1]);
    return BoolToFre(ok);
}

static FREObject fnGetRenderer(FREContext ctx, void*, uint32_t, FREObject[]) {
    (void)ctx;
#if USE_PDFIUM
    const char* s = "pdfium";
#else
    const char* s = "placeholder";
#endif
    uint32_t slen = static_cast<uint32_t>(strlen(s)) + 1;
    FREObject o = nullptr;
    FRENewObjectFromUTF8(slen, reinterpret_cast<const uint8_t*>(s), &o);
    return o;
}

static FREObject fnGetLastError(FREContext ctx, void*, uint32_t, FREObject[]) {
    void* nd = nullptr;
    FREGetContextNativeData(ctx, &nd);
    auto* pc = static_cast<PdfContext*>(nd);
    const char* s = (pc && !pc->lastError.empty()) ? pc->lastError.c_str() : "";
    uint32_t slen = static_cast<uint32_t>(strlen(s)) + 1;
    FREObject o = nullptr;
    FRENewObjectFromUTF8(slen, reinterpret_cast<const uint8_t*>(s), &o);
    return o;
}

static void ContextInitializer(void* extData, const uint8_t*, FREContext ctx, uint32_t* numFunctions,
                               const FRENamedFunction** functionsToSet) {
    (void)extData;
    static FRENamedFunction fnMap[] = {
        { (const uint8_t*)"open", nullptr, fnOpen },
        { (const uint8_t*)"close", nullptr, fnClose },
        { (const uint8_t*)"getPageCount", nullptr, fnGetPageCount },
        { (const uint8_t*)"renderPage", nullptr, fnRenderPage },
        { (const uint8_t*)"getLastError", nullptr, fnGetLastError },
        { (const uint8_t*)"getRenderer", nullptr, fnGetRenderer },
    };
    *numFunctions = sizeof(fnMap) / sizeof(fnMap[0]);
    *functionsToSet = fnMap;
    auto* pc = new PdfContext();
    FRESetContextNativeData(ctx, pc);
}

static void ContextFinalizer(FREContext ctx) {
    void* nd = nullptr;
    FREGetContextNativeData(ctx, &nd);
    auto* pc = static_cast<PdfContext*>(nd);
    if (pc) {
#if USE_PDFIUM
        if (pc->doc) {
            FPDF_CloseDocument(pc->doc);
        }
#endif
        delete pc;
        FRESetContextNativeData(ctx, nullptr);
    }
}

extern "C" {

__declspec(dllexport) void PdfAneExtensionInitializer(void** extDataToSet,
                                                      FREContextInitializer* ctxInit,
                                                      FREContextFinalizer* ctxFin) {
    *extDataToSet = nullptr;
    *ctxInit = ContextInitializer;
    *ctxFin = ContextFinalizer;
}

__declspec(dllexport) void PdfAneExtensionFinalizer(void* extData) {
    (void)extData;
}

} // extern "C"

#if USE_PDFIUM
struct PdfiumLibInit {
    PdfiumLibInit() {
        FPDF_LIBRARY_CONFIG cfg{ 1, nullptr, nullptr, 0 };
        FPDF_InitLibraryWithConfig(&cfg);
    }
    ~PdfiumLibInit() { FPDF_DestroyLibrary(); }
};
static PdfiumLibInit g_pdfiumInit;
#endif
