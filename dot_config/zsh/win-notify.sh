# Windows toast notification from WSL2
#
# usage: win-notify [message] [title]
#   message : toast body text        (default: "Done.")
#   title   : toast title / app name (default: $WIN_NOTIFY_TITLE, else "Notify")
#
# The AppUserModelID is derived from the title (or $WIN_NOTIFY_APPID) and
# registered in HKCU on each call, so Windows delivers the toast instantly
# instead of delaying it as an "unregistered app" notification.
# Set WIN_NOTIFY_TITLE per environment to brand the toast, e.g.:
#   export WIN_NOTIFY_TITLE=Claude   # or Codex, etc.
win-notify() {
  command -v powershell.exe >/dev/null 2>&1 || return 0
  local msg="${1:-Done.}"
  local title="${2:-${WIN_NOTIFY_TITLE:-Notify}}"
  local appid="${WIN_NOTIFY_APPID:-${title// /}.Notify}"
  powershell.exe -NoProfile -Command "
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] > \$null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType=WindowsRuntime] > \$null
    New-Item -Path 'HKCU:\Software\Classes\AppUserModelId\${appid}' -Force | Out-Null
    Set-ItemProperty -Path 'HKCU:\Software\Classes\AppUserModelId\${appid}' -Name DisplayName -Value '${title}'
    \$tpl = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
    \$nodes = \$tpl.GetElementsByTagName('text')
    \$nodes.Item(0).AppendChild(\$tpl.CreateTextNode('${title}')) > \$null
    \$nodes.Item(1).AppendChild(\$tpl.CreateTextNode('${msg}')) > \$null
    \$toast = [Windows.UI.Notifications.ToastNotification]::new(\$tpl)
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('${appid}').Show(\$toast)
  " 2>/dev/null
}
