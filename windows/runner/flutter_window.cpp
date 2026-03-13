#include "flutter_window.h"

#include <optional>
#include "flutter/generated_plugin_registrant.h"
#include <flutter/standard_method_codec.h>
#include <flutter/event_stream_handler_functions.h>
#include <windows.h>
#include <comdef.h>
#include "utils.h"

FlutterWindow::FlutterWindow(const flutter::DartProject &project)
    : project_(project)
{
}

FlutterWindow::~FlutterWindow()
{
}

bool FlutterWindow::OnCreate()
{
  if (!Win32Window::OnCreate())
  {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  
  if (!flutter_controller_->engine() || !flutter_controller_->view())
  {
    return false;
  }

  // Register plugins for the main engine
  RegisterPlugins(flutter_controller_->engine());

  // Initialize the RecordingBridge
  bridge_ = std::make_unique<RecordingBridge>(GetHandle(), project_);
  
  // Register channels on the main engine's messenger
  bridge_->RegisterChannels(flutter_controller_->engine()->messenger());

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]()
                                                      { this->Show(); });

  flutter_controller_->ForceRedraw();

  // Initialize Tray Icon
  CreateTrayIcon();

  return true;
}

void FlutterWindow::OnDestroy()
{
  DestroyTrayIcon();

  if (flutter_controller_)
  {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT const message, WPARAM const wparam, LPARAM const lparam) noexcept
{
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_)
  {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result)
    {
      return *result;
    }
  }

  // Handle RecordingBridge messages (Audio Data, State, etc.)
  if (bridge_) {
    auto result = bridge_->HandleMessage(message, wparam, lparam);
    if (result) {
      return *result;
    }
  }

  switch (message)
  {
  case WM_FONTCHANGE:
    flutter_controller_->engine()->ReloadSystemFonts();
    break;

  case WM_CLOSE:
    // Intercept close button and hide to tray instead
    ShowWindow(GetHandle(), SW_HIDE);
    return 0;

  case WM_TRAY_ICON:
    if (LOWORD(lparam) == WM_LBUTTONDBLCLK) {
        ShowWindow(GetHandle(), SW_SHOW);
    } else if (LOWORD(lparam) == WM_RBUTTONUP) {
        ShowTrayContextMenu();
    }
    break;

  case WM_COMMAND:
    if (LOWORD(wparam) == ID_TRAY_RESTORE) {
        ShowWindow(GetHandle(), SW_SHOW);
    } else if (LOWORD(wparam) == ID_TRAY_EXIT) {
        DestroyTrayIcon();
        PostQuitMessage(0);
    }
    break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::CreateTrayIcon() {
    memset(&nid_, 0, sizeof(nid_));
    nid_.cbSize = sizeof(nid_);
    nid_.hWnd = GetHandle();
    nid_.uID = 1;
    nid_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    nid_.uCallbackMessage = WM_TRAY_ICON;
    
    // Load the app icon
    nid_.hIcon = LoadIcon(GetModuleHandle(NULL), MAKEINTRESOURCE(101)); //IDI_APP_ICON usually 101
    if (!nid_.hIcon) {
        nid_.hIcon = LoadIcon(NULL, IDI_APPLICATION);
    }

    wcscpy_s(nid_.szTip, sizeof(nid_.szTip) / sizeof(WCHAR), L"LEDFx Background Engine");

    Shell_NotifyIcon(NIM_ADD, &nid_);
    tray_icon_created_ = true;
}

void FlutterWindow::DestroyTrayIcon() {
    if (tray_icon_created_) {
        Shell_NotifyIcon(NIM_DELETE, &nid_);
        tray_icon_created_ = false;
    }
}

void FlutterWindow::ShowTrayContextMenu() {
    POINT curPoint;
    GetCursorPos(&curPoint);
    HMENU hMenu = CreatePopupMenu();
    if (hMenu) {
        InsertMenu(hMenu, static_cast<UINT>(-1), MF_BYPOSITION, static_cast<UINT_PTR>(ID_TRAY_RESTORE), L"Restore");
        InsertMenu(hMenu, static_cast<UINT>(-1), MF_BYPOSITION, static_cast<UINT_PTR>(ID_TRAY_EXIT), L"Exit");
        
        // TrackPopupMenu needs the window to be foreground to handle clicks correctly
        SetForegroundWindow(GetHandle());
        TrackPopupMenu(hMenu, TPM_BOTTOMALIGN, curPoint.x, curPoint.y, 0, GetHandle(), NULL);
        DestroyMenu(hMenu);
    }
}