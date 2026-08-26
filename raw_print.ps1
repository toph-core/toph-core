param(
    [string]$PrinterName = "XP80-Raw",
    [byte[]]$Bytes
)

$signature = @'
[DllImport("winspool.drv", CharSet = CharSet.Auto, SetLastError = true)]
public static extern bool OpenPrinter(string pPrinterName, out IntPtr phPrinter, IntPtr pDefault);

[DllImport("winspool.drv", SetLastError = true)]
public static extern bool ClosePrinter(IntPtr hPrinter);

[DllImport("winspool.drv", CharSet = CharSet.Auto, SetLastError = true)]
public static extern bool StartDocPrinter(IntPtr hPrinter, int level, ref DOCINFOA di);

[DllImport("winspool.drv", SetLastError = true)]
public static extern bool EndDocPrinter(IntPtr hPrinter);

[DllImport("winspool.drv", SetLastError = true)]
public static extern bool StartPagePrinter(IntPtr hPrinter);

[DllImport("winspool.drv", SetLastError = true)]
public static extern bool EndPagePrinter(IntPtr hPrinter);

[DllImport("winspool.drv", SetLastError = true)]
public static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int dwCount, out int dwWritten);

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
public struct DOCINFOA
{
    [MarshalAs(UnmanagedType.LPTStr)] public string pDocName;
    [MarshalAs(UnmanagedType.LPTStr)] public string pOutputFile;
    [MarshalAs(UnmanagedType.LPTStr)] public string pDataType;
}
'@

Add-Type -MemberDefinition $signature -Name RawPrinter -Namespace Win32

function Send-RawBytes {
    param([string]$PrinterName, [byte[]]$Data)

    $hPrinter = [IntPtr]::Zero
    if (-not [Win32.RawPrinter]::OpenPrinter($PrinterName, [ref]$hPrinter, [IntPtr]::Zero)) {
        throw "OpenPrinter failed: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }

    try {
        $di = New-Object Win32.RawPrinter+DOCINFOA
        $di.pDocName = "Raw ESC/POS Job"
        $di.pDataType = "RAW"

        if (-not [Win32.RawPrinter]::StartDocPrinter($hPrinter, 1, [ref]$di)) {
            $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "StartDocPrinter failed, Win32 error $err"
        }
        if (-not [Win32.RawPrinter]::StartPagePrinter($hPrinter)) {
            $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "StartPagePrinter failed, Win32 error $err"
        }

        $pUnmanaged = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($Data.Length)
        [System.Runtime.InteropServices.Marshal]::Copy($Data, 0, $pUnmanaged, $Data.Length)

        $written = 0
        $ok = [Win32.RawPrinter]::WritePrinter($hPrinter, $pUnmanaged, $Data.Length, [ref]$written)

        [System.Runtime.InteropServices.Marshal]::FreeHGlobal($pUnmanaged)

        [Win32.RawPrinter]::EndPagePrinter($hPrinter) | Out-Null
        [Win32.RawPrinter]::EndDocPrinter($hPrinter) | Out-Null

        if (-not $ok) { throw "WritePrinter failed" }
        Write-Host "Wrote $written bytes to $PrinterName"
    }
    finally {
        [Win32.RawPrinter]::ClosePrinter($hPrinter) | Out-Null
    }
}

Send-RawBytes -PrinterName $PrinterName -Data $Bytes
