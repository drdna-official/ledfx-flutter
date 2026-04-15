#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include "recording_bridge.h"

#if __has_include(<libayatana-appindicator/app-indicator.h>)
#include <libayatana-appindicator/app-indicator.h>
#else
#include <libappindicator/app-indicator.h>
#endif

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  RecordingBridge* recording_bridge;
  AppIndicator* indicator;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static gboolean on_delete_event(GtkWidget *widget, GdkEvent *event, gpointer data) {
    // Hide window instead of destroying
    gtk_widget_hide(widget);
    return TRUE; // Stop the event from propagating
}

// Helper to find icon path relative to executable
static gchar* get_icon_path() {
    g_autofree gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
    if (!exe_path) return nullptr;
    g_autoptr(GFile) exe_file = g_file_new_for_path(exe_path);
    g_autoptr(GFile) exe_dir = g_file_get_parent(exe_file);
    
    // 1. Check in bundle data (Production/Installed)
    g_autoptr(GFile) bundle_icon = g_file_get_child(exe_dir, "data/app_icon.png");
    if (g_file_query_exists(bundle_icon, nullptr)) {
        return g_file_get_path(bundle_icon);
    }
    
    // 2. Check relative to build directory (Development)
    // When running 'flutter run', the binary is in build/linux/x64/debug/bundle/
    // or build/linux/x64/debug/intermediates_do_not_run/
    g_autoptr(GFile) project_root = g_file_get_parent(g_file_get_parent(g_file_get_parent(g_file_get_parent(exe_dir))));
    if (project_root) {
        g_autoptr(GFile) dev_icon = g_file_get_child(project_root, "linux/runner/assets/app_icon.png");
        if (g_file_query_exists(dev_icon, nullptr)) {
            return g_file_get_path(dev_icon);
        }
    }
    
    // 3. Fallback to current working directory
    if (g_file_test("linux/runner/assets/app_icon.png", G_FILE_TEST_EXISTS)) {
        return g_strdup("linux/runner/assets/app_icon.png");
    }

    return nullptr;
}

static void on_tray_restore(GtkMenuItem *item, gpointer data) {
    MyApplication* self = MY_APPLICATION(data);
    GList* windows = gtk_application_get_windows(GTK_APPLICATION(self));
    if (windows) {
        GtkWindow* window = GTK_WINDOW(windows->data);
        gtk_window_present(window);
    }
}

static void on_tray_quit(GtkMenuItem *item, gpointer data) {
    MyApplication* self = MY_APPLICATION(data);
    g_application_quit(G_APPLICATION(self));
}

static void setup_tray_icon(MyApplication* self, GtkWindow* window) {
    g_autofree gchar* icon_path = get_icon_path();
    
    self->indicator = app_indicator_new("drdna-ledfx",
                                        icon_path ? icon_path : "multimedia-audio-player",
                                        APP_INDICATOR_CATEGORY_APPLICATION_STATUS);
    
    app_indicator_set_status(self->indicator, APP_INDICATOR_STATUS_ACTIVE);
    app_indicator_set_title(self->indicator, "LEDFx Background Engine");

    GtkWidget *menu = gtk_menu_new();
    
    GtkWidget *restore_item = gtk_menu_item_new_with_label("Restore");
    g_signal_connect(G_OBJECT(restore_item), "activate", G_CALLBACK(on_tray_restore), self);
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), restore_item);
    
    GtkWidget *quit_item = gtk_menu_item_new_with_label("Quit");
    g_signal_connect(G_OBJECT(quit_item), "activate", G_CALLBACK(on_tray_quit), self);
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), quit_item);

    gtk_widget_show_all(menu);
    app_indicator_set_menu(self->indicator, GTK_MENU(menu));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "ledfx");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "ledfx");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  // Catch the delete-event logic to minimize to tray
  g_signal_connect(window, "delete-event", G_CALLBACK(on_delete_event), self);
  setup_tray_icon(self, window);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // Initialize RecordingBridge
  self->recording_bridge = new RecordingBridge(view, project);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(fl_view_get_engine(view));
  self->recording_bridge->RegisterChannels(messenger);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  
  if (self->recording_bridge) {
      delete self->recording_bridge;
      self->recording_bridge = nullptr;
  }
  
  if (self->indicator) {
      // Indicator cleanup (internal ref counting happens if needed, typically ok to leave to app exit)
      self->indicator = nullptr;
  }

  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

#pragma GCC diagnostic pop

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
