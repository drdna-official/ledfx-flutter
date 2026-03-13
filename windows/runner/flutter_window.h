#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/encodable_value.h>

#include "win32_window.h"
#include "recording_bridge.h"
#include <shellapi.h>

#define WM_TRAY_ICON (WM_APP + 300)
#define ID_TRAY_RESTORE 1001
#define ID_TRAY_EXIT 1002

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window
{
public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject &project);
  virtual ~FlutterWindow();

protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

private:
  void CreateTrayIcon();
  void DestroyTrayIcon();
  void ShowTrayContextMenu();

  // The project to run.
  flutter::DartProject project_;
  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // The bridge between Flutter and the native Windows audio system.
  std::unique_ptr<RecordingBridge> bridge_;

  // System tray icon data
  NOTIFYICONDATA nid_ = {};
  bool tray_icon_created_ = false;
};

#endif // RUNNER_FLUTTER_WINDOW_H_
