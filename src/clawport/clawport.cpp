/*
clawport - tiny CLI to create/configure/delete a clawmon port via the spooler's
XcvData interface (AddPort / SetConfig / DeletePort). Compiles against clawmon's
own config.h so PORTCONFIG matches the monitor byte-for-byte.

  clawport add <MonitorName> <PortName> <pipe 0|1> <command> [outputDir]
  clawport set <PortName>     <pipe 0|1> <command> [outputDir]
  clawport del <PortName>

GPL-2 (same as clawmon). Part of the ARM64 clawmon port.
*/
#include <windows.h>
#include <winspool.h>
#include <stdio.h>
#include "config.h"   /* PORTCONFIG + MAX_* (pulls defs.h, lmcons.h) */

static void fill_config(PORTCONFIG* pc, const wchar_t* port, int pipe,
                        const wchar_t* cmd, const wchar_t* outdir)
{
    ZeroMemory(pc, sizeof(*pc));
    lstrcpynW(pc->szPortName, port, MAX_PATH);
    lstrcpynW(pc->szOutputPath, outdir, MAX_PATH);
    lstrcpynW(pc->szFilePattern, L"claw%i.prn", MAX_PATH);
    pc->bOverwrite = FALSE;
    lstrcpynW(pc->szUserCommandPattern, cmd, MAX_USERCOMMMAND - 1);
    pc->szExecPath[0] = L'\0';
    pc->bWaitTermination = TRUE;
    pc->dwWaitTimeout = 300;
    pc->bPipeData = pipe ? TRUE : FALSE;
    pc->bHideProcess = TRUE;
    pc->bRunAsPUser = TRUE;            /* run the command as the printing user (so WSL sees their distro) */
    pc->nLogLevel = 3;                 /* verbose monitor logging while we bring this up */
    pc->szUser[0] = pc->szDomain[0] = pc->szPassword[0] = L'\0';
}

static HANDLE open_xcv(const wchar_t* object)
{
    PRINTER_DEFAULTSW pd; ZeroMemory(&pd, sizeof(pd));
    pd.DesiredAccess = SERVER_ACCESS_ADMINISTER;
    HANDLE h = NULL;
    if (!OpenPrinterW((LPWSTR)object, &h, &pd)) {
        wprintf(L"OpenPrinter(%s) failed: %lu\n", object, GetLastError());
        return NULL;
    }
    return h;
}

int wmain(int argc, wchar_t** argv)
{
    if (argc < 2) { wprintf(L"usage: clawport add|set|del ...\n"); return 2; }
    const wchar_t* mode = argv[1];
    DWORD needed = 0, status = 0; BOOL ok;
    wchar_t xcv[600];

    if (_wcsicmp(mode, L"add") == 0 && argc >= 6) {
        const wchar_t* mon = argv[2]; const wchar_t* port = argv[3];
        int pipe = _wtoi(argv[4]); const wchar_t* cmd = argv[5];
        const wchar_t* outdir = (argc >= 7) ? argv[6] : L"C:\\Claude\\clawmon-arm64\\spool";
        wsprintfW(xcv, L",XcvMonitor %s", mon);
        HANDLE h = open_xcv(xcv); if (!h) return 1;
        ok = XcvDataW(h, L"AddPort", (PBYTE)port, (DWORD)((lstrlenW(port)+1)*sizeof(WCHAR)), NULL, 0, &needed, &status);
        wprintf(L"AddPort   call=%d status=%lu\n", ok, status);
        PORTCONFIG pc; fill_config(&pc, port, pipe, cmd, outdir);
        ok = XcvDataW(h, L"SetConfig", (PBYTE)&pc, sizeof(pc), NULL, 0, &needed, &status);
        wprintf(L"SetConfig call=%d status=%lu\n", ok, status);
        ClosePrinter(h);
        return (status == 0) ? 0 : 1;
    }
    else if (_wcsicmp(mode, L"set") == 0 && argc >= 5) {
        const wchar_t* port = argv[2];
        int pipe = _wtoi(argv[3]); const wchar_t* cmd = argv[4];
        const wchar_t* outdir = (argc >= 6) ? argv[5] : L"C:\\Claude\\clawmon-arm64\\spool";
        wsprintfW(xcv, L",XcvPort %s", port);
        HANDLE h = open_xcv(xcv); if (!h) return 1;
        PORTCONFIG pc; fill_config(&pc, port, pipe, cmd, outdir);
        ok = XcvDataW(h, L"SetConfig", (PBYTE)&pc, sizeof(pc), NULL, 0, &needed, &status);
        wprintf(L"SetConfig call=%d status=%lu\n", ok, status);
        ClosePrinter(h);
        return (status == 0) ? 0 : 1;
    }
    else if (_wcsicmp(mode, L"del") == 0 && argc >= 3) {
        const wchar_t* port = argv[2];
        wsprintfW(xcv, L",XcvPort %s", port);
        HANDLE h = open_xcv(xcv); if (!h) return 1;
        ok = XcvDataW(h, L"DeletePort", (PBYTE)port, (DWORD)((lstrlenW(port)+1)*sizeof(WCHAR)), NULL, 0, &needed, &status);
        wprintf(L"DeletePort call=%d status=%lu\n", ok, status);
        ClosePrinter(h);
        return (status == 0) ? 0 : 1;
    }
    else if (_wcsicmp(mode, L"addprinter") == 0 && argc >= 5) {
        /* raw AddPrinterW - bypasses Add-Printer (CIM) and printui, reports the exact error */
        PRINTER_INFO_2W pi; ZeroMemory(&pi, sizeof(pi));
        pi.pPrinterName    = (LPWSTR)argv[2];
        pi.pDriverName     = (LPWSTR)argv[3];
        pi.pPortName       = (LPWSTR)argv[4];
        pi.pPrintProcessor = (LPWSTR)L"winprint";
        pi.pDatatype       = (LPWSTR)L"RAW";
        pi.Attributes      = PRINTER_ATTRIBUTE_LOCAL;
        HANDLE hp = AddPrinterW(NULL, 2, (LPBYTE)&pi);
        if (hp) { wprintf(L"AddPrinter OK: %s\n", argv[2]); ClosePrinter(hp); return 0; }
        DWORD e = GetLastError();
        wprintf(L"AddPrinter FAILED: Win32 error %lu (0x%08lX)\n", e, e);
        return 1;
    }
    wprintf(L"usage: clawport add <Monitor> <Port> <pipe 0|1> <command> [dir]\n"
            L"       clawport addprinter <PrinterName> <DriverName> <PortName>\n"
            L"       clawport set <Port> <pipe 0|1> <command> [dir]\n"
            L"       clawport del <Port>\n");
    return 2;
}
