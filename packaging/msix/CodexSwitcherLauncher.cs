using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class CodexSwitcherLauncher
{
    [STAThread]
    private static int Main(string[] args)
    {
#if CONFIGURE_KEYS
        const string scriptName = "ConfigureProviderKeys.ps1";
#else
        const string scriptName = "CodexProviderSwitcher.ps1";
#endif

        string appDirectory = AppDomain.CurrentDomain.BaseDirectory;
        string scriptPath = Path.Combine(appDirectory, scriptName);
        string powershellPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.Windows),
            "System32",
            "WindowsPowerShell",
            "v1.0",
            "powershell.exe");

        if (!File.Exists(scriptPath))
        {
            MessageBox.Show(
                "The application package is incomplete. Missing: " + scriptName,
                "Codex Three-Provider Switcher",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 2;
        }

        try
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = powershellPath,
                WorkingDirectory = appDirectory,
                UseShellExecute = false,
#if CONFIGURE_KEYS
                Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File \"" + scriptPath + "\""
#else
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
                Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + scriptPath + "\""
#endif
            };

            Process process = Process.Start(startInfo);
            return process == null ? 3 : 0;
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                "Unable to start the application.\r\n\r\n" + exception.Message,
                "Codex Three-Provider Switcher",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }
    }
}
