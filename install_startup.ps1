# Start the News Sniper in the background at Windows Startup
$shortcutPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\NewsSniper.lnk"
$wscript = New-Object -ComObject WScript.Shell
$shortcut = $wscript.CreateShortcut($shortcutPath)
$pythonPath = (Get-Command python).Source
$scriptPath = "$PSScriptRoot\desktop_hud\app.py"

$shortcut.TargetPath = "pythonw.exe"
$shortcut.Arguments = "`"$scriptPath`""
$shortcut.WorkingDirectory = "$PSScriptRoot"
$shortcut.WindowStyle = 1
$shortcut.Description = "Fundamental News Sniper & Reminder HUD"
$shortcut.Save()

Write-Host "✅ News Sniper has been added to Windows Startup."
Write-Host "Whenever you open your PC, it will notify you of upcoming news for today and tomorrow!"
