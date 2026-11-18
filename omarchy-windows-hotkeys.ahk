#Requires AutoHotkey v2.0
#SingleInstance Force

; ------------------------------------------------------------
; Omarchy-style Windows hotkeys
; Super key = Windows key
;
; AutoHotkey symbols:
; # = Win / Super
; ! = Alt
; + = Shift
; ^ = Ctrl
; ------------------------------------------------------------

global GamingMode := false


; ------------------------------------------------------------
; Gaming Mode Toggle
; Win + Shift + G = disable/enable most Super hotkeys
; ------------------------------------------------------------

#+g::{
    global GamingMode
    GamingMode := !GamingMode

    if GamingMode {
        TrayTip "Omarchy Hotkeys", "Gaming Mode ON - Super hotkeys disabled", 1500
    } else {
        TrayTip "Omarchy Hotkeys", "Gaming Mode OFF - Super hotkeys enabled", 1500
    }
}


#HotIf !GamingMode


; ------------------------------------------------------------
; Window controls
; ------------------------------------------------------------

; Win + Q = close active window
#q::WinClose "A"

; Win + W = close active window
#w::WinClose "A"

; Win + Shift + Q = force close active app process
#+q::{
    pid := WinGetPID("A")
    if pid {
        ProcessClose pid
    }
}

; Win + F = maximize/restore active window
#f::{
    if WinGetMinMax("A") = 1 {
        WinRestore "A"
    } else {
        WinMaximize "A"
    }
}

; Win + Shift + F = fullscreen-ish via Alt + Enter
#+f::Send "!{Enter}"

; Win + M = minimize active window
#m::WinMinimize "A"


; ------------------------------------------------------------
; App launchers
; ------------------------------------------------------------

; Win + Enter = Windows Terminal
#Enter::Run "wt.exe"

; Win + E = File Explorer
#e::Run "explorer.exe"

; Win + B = Brave
#b::Run "brave.exe"

; Win + Alt + B = Brave new window
#!b::Run "brave.exe --new-window"

; Win + Shift + Y = YouTube app profile
#+y::Run '"' EnvGet("LOCALAPPDATA") '\BraveSoftware\Brave-Browser\Application\brave.exe" --user-data-dir="' EnvGet("LOCALAPPDATA") '\WebDesk\Profiles\youtube" --app=https://www.youtube.com --disable-gpu --no-first-run'

; Win + Shift + A = ChatGPT
#+a::Run '"' EnvGet("LOCALAPPDATA") '\BraveSoftware\Brave-Browser\Application\brave.exe" --app=https://chatgpt.com/ --no-first-run'

; Win + Alt + C = VS Code
#!c::Run "code"

; Win + Shift + Alt + C = Cursor
#+!c::Run "cursor"

; Win + O = Obsidian
#o::Run "obsidian"

; Win + N = Notepad
#n::Run "notepad.exe"

; Win + Alt + T = Task Manager
#!t::Run "taskmgr.exe"


; ------------------------------------------------------------
; Terminal helpers
; These call your PowerShell functions from the profile.
; ------------------------------------------------------------

; Win + Alt + F = fzf open selected file's folder in Explorer
#!f::Run 'wt.exe pwsh -NoExit -Command openfdir'

; Win + Shift + Alt + F = fzf open selected file's folder in VS Code
#+!f::Run 'wt.exe pwsh -NoExit -Command codefdir'

; Win + Alt + D = fzf cd into selected file's folder
#!d::Run 'wt.exe pwsh -NoExit -Command cdf'


; ------------------------------------------------------------
; Screenshots / utility
; ------------------------------------------------------------

; Win + Shift + S = Windows screenshot tool
; Left native Windows shortcut alone.

; Win + Alt + R = open Run dialog
#!r::Send "#r"

; Win + Alt + V = clipboard history
#!v::Send "#v"


#HotIf