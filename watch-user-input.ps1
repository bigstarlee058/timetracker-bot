$source = @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

public static class UserInputWatcher
{
    private const int WH_KEYBOARD_LL = 13;
    private const int WH_MOUSE_LL = 14;

    private const int WM_KEYDOWN = 0x0100;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_LBUTTONDOWN = 0x0201;
    private const int WM_RBUTTONDOWN = 0x0204;
    private const int WM_MBUTTONDOWN = 0x0207;
    private const int WM_MOUSEWHEEL = 0x020A;
    private const int WM_XBUTTONDOWN = 0x020B;
    private const int WM_MOUSEHWHEEL = 0x020E;

    private const uint LLKHF_INJECTED = 0x00000010;
    private const uint LLKHF_LOWER_IL_INJECTED = 0x00000002;
    private const uint LLMHF_INJECTED = 0x00000001;
    private const uint LLMHF_LOWER_IL_INJECTED = 0x00000002;

    private static readonly LowLevelProc KeyboardProc = KeyboardHookCallback;
    private static readonly LowLevelProc MouseProc = MouseHookCallback;
    private static IntPtr keyboardHook = IntPtr.Zero;
    private static IntPtr mouseHook = IntPtr.Zero;
    private static int reported = 0;

    public static int Run()
    {
        IntPtr moduleHandle = IntPtr.Zero;

        using (Process currentProcess = Process.GetCurrentProcess())
        using (ProcessModule currentModule = currentProcess.MainModule)
        {
            moduleHandle = GetModuleHandle(currentModule.ModuleName);
        }

        keyboardHook = SetHook(WH_KEYBOARD_LL, KeyboardProc, moduleHandle);
        mouseHook = SetHook(WH_MOUSE_LL, MouseProc, moduleHandle);

        if (keyboardHook == IntPtr.Zero || mouseHook == IntPtr.Zero)
        {
            int error = Marshal.GetLastWin32Error();
            Cleanup();
            Console.Error.WriteLine("Unable to install user input hooks. Win32 error: " + error);
            Console.Error.Flush();
            return 1;
        }

        Console.WriteLine("ready");
        Console.Out.Flush();

        MSG message;
        int result;
        while ((result = GetMessage(out message, IntPtr.Zero, 0, 0)) > 0)
        {
            TranslateMessage(ref message);
            DispatchMessage(ref message);
        }

        Cleanup();
        return result < 0 ? 1 : 0;
    }

    private static IntPtr SetHook(int hookId, LowLevelProc callback, IntPtr moduleHandle)
    {
        IntPtr hook = SetWindowsHookEx(hookId, callback, moduleHandle, 0);
        if (hook == IntPtr.Zero)
        {
            hook = SetWindowsHookEx(hookId, callback, IntPtr.Zero, 0);
        }

        return hook;
    }

    private static IntPtr KeyboardHookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            int message = unchecked((int)wParam.ToInt64());
            if (message == WM_KEYDOWN || message == WM_SYSKEYDOWN)
            {
                KBDLLHOOKSTRUCT hookData = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(KBDLLHOOKSTRUCT));
                if ((hookData.flags & LLKHF_INJECTED) == 0 && (hookData.flags & LLKHF_LOWER_IL_INJECTED) == 0)
                {
                    ReportAndStop("keyboard");
                }
            }
        }

        return CallNextHookEx(keyboardHook, nCode, wParam, lParam);
    }

    private static IntPtr MouseHookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            int message = unchecked((int)wParam.ToInt64());
            if (message == WM_LBUTTONDOWN || message == WM_RBUTTONDOWN || message == WM_MBUTTONDOWN ||
                message == WM_XBUTTONDOWN || message == WM_MOUSEWHEEL || message == WM_MOUSEHWHEEL)
            {
                MSLLHOOKSTRUCT hookData = (MSLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(MSLLHOOKSTRUCT));
                if ((hookData.flags & LLMHF_INJECTED) == 0 && (hookData.flags & LLMHF_LOWER_IL_INJECTED) == 0)
                {
                    ReportAndStop("mouse");
                }
            }
        }

        return CallNextHookEx(mouseHook, nCode, wParam, lParam);
    }

    private static void ReportAndStop(string inputType)
    {
        if (Interlocked.Exchange(ref reported, 1) == 0)
        {
            Console.WriteLine(inputType);
            Console.Out.Flush();
            PostQuitMessage(0);
        }
    }

    private static void Cleanup()
    {
        if (keyboardHook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(keyboardHook);
            keyboardHook = IntPtr.Zero;
        }

        if (mouseHook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(mouseHook);
            mouseHook = IntPtr.Zero;
        }
    }

    private delegate IntPtr LowLevelProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int x;
        public int y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSG
    {
        public IntPtr hwnd;
        public uint message;
        public UIntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public POINT pt;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KBDLLHOOKSTRUCT
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSLLHOOKSTRUCT
    {
        public POINT pt;
        public uint mouseData;
        public uint flags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);

    [DllImport("user32.dll")]
    private static extern int GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

    [DllImport("user32.dll")]
    private static extern bool TranslateMessage(ref MSG lpMsg);

    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessage(ref MSG lpMsg);

    [DllImport("user32.dll")]
    private static extern void PostQuitMessage(int nExitCode);
}
"@

Add-Type -TypeDefinition $source -Language CSharp
[void][UserInputWatcher]::Run()
