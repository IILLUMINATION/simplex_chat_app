#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <glib/gstdio.h>
#include <unistd.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* window_channel;
  FlMethodChannel* clipboard_channel;
  GtkWindow* window;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Timestamp for _NET_WM_MOVERESIZE / xdg_toplevel requests. Wayland ignores
// it (GDK substitutes the last input serial), X11 needs the server time.
static guint32 window_event_time(GtkWindow* window) {
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(window));
  if (gdk_window == nullptr) {
    return GDK_CURRENT_TIME;
  }
#ifdef GDK_WINDOWING_X11
  if (GDK_IS_X11_WINDOW(gdk_window)) {
    return gdk_x11_get_server_time(gdk_window);
  }
#endif
  return GDK_CURRENT_TIME;
}

static void window_start_move(GtkWindow* window) {
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  GdkSeat* seat = gdk_display_get_default_seat(display);
  GdkDevice* pointer = gdk_seat_get_pointer(seat);
  GdkScreen* screen = nullptr;
  gint x = 0;
  gint y = 0;
  gdk_device_get_position(pointer, &screen, &x, &y);
  gtk_window_begin_move_drag(window, 1, x, y, window_event_time(window));
}

static void window_start_resize(GtkWindow* window, gint64 edge) {
  static const GdkWindowEdge edges[] = {
      GDK_WINDOW_EDGE_NORTH_WEST, GDK_WINDOW_EDGE_NORTH,
      GDK_WINDOW_EDGE_NORTH_EAST, GDK_WINDOW_EDGE_WEST,
      GDK_WINDOW_EDGE_EAST,       GDK_WINDOW_EDGE_SOUTH_WEST,
      GDK_WINDOW_EDGE_SOUTH,      GDK_WINDOW_EDGE_SOUTH_EAST,
  };
  if (edge < 0 || edge >= (gint64)G_N_ELEMENTS(edges)) {
    return;
  }
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  GdkSeat* seat = gdk_display_get_default_seat(display);
  GdkDevice* pointer = gdk_seat_get_pointer(seat);
  GdkScreen* screen = nullptr;
  gint x = 0;
  gint y = 0;
  gdk_device_get_position(pointer, &screen, &x, &y);
  gtk_window_begin_resize_drag(window, edges[edge], 1, x, y,
                               window_event_time(window));
}

// Handles window controls requested from the Flutter title bar.
static void window_channel_method_cb(FlMethodChannel* channel,
                                     FlMethodCall* method_call,
                                     gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  GtkWindow* window = self->window;
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (window == nullptr) {
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        "no-window", "Window is not available", nullptr));
  } else if (g_strcmp0(method, "minimize") == 0) {
    gtk_window_iconify(window);
  } else if (g_strcmp0(method, "toggleMaximize") == 0) {
    if (gtk_window_is_maximized(window)) {
      gtk_window_unmaximize(window);
    } else {
      gtk_window_maximize(window);
    }
  } else if (g_strcmp0(method, "close") == 0) {
    gtk_window_close(window);
  } else if (g_strcmp0(method, "startDrag") == 0) {
    window_start_move(window);
  } else if (g_strcmp0(method, "startResize") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* edge = (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP)
                        ? fl_value_lookup_string(args, "edge")
                        : nullptr;
    window_start_resize(window, edge != nullptr ? fl_value_get_int(edge) : -1);
  } else if (g_strcmp0(method, "isMaximized") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(gtk_window_is_maximized(window));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  if (response == nullptr) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  fl_method_call_respond(method_call, response, nullptr);
}

static gboolean window_state_changed_cb(GtkWidget* widget,
                                        GdkEventWindowState* event,
                                        gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->window_channel == nullptr) {
    return FALSE;
  }
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(
      args, "maximized",
      fl_value_new_bool((event->new_window_state & GDK_WINDOW_STATE_MAXIMIZED) != 0));
  fl_value_set_string_take(
      args, "active",
      fl_value_new_bool((event->new_window_state & GDK_WINDOW_STATE_FOCUSED) != 0));
  fl_method_channel_invoke_method(self->window_channel, "state", args, nullptr,
                                  nullptr, nullptr);
  return FALSE;
}

// Writes a clipboard bitmap to a temp PNG the Dart side can read and send.
static gchar* clipboard_save_image(GdkPixbuf* pixbuf) {
  g_autofree gchar* dir = g_dir_make_tmp("tanglex-paste-XXXXXX", nullptr);
  if (dir == nullptr) {
    return nullptr;
  }
  g_autofree gchar* path = g_build_filename(dir, "Pasted image.png", nullptr);
  GError* error = nullptr;
  if (!gdk_pixbuf_save(pixbuf, path, "png", &error, nullptr)) {
    g_warning("Failed to save clipboard image: %s",
              error != nullptr ? error->message : "unknown error");
    g_clear_error(&error);
    return nullptr;
  }
  return g_steal_pointer(&path);
}

// `tanglex/clipboard#readFiles`: local file URIs first, a raw bitmap second,
// the same order Telegram's QMimeData hook uses in `confirmSendingFiles`
// (Telegram/SourceFiles/history/history_widget.cpp).
static void clipboard_channel_method_cb(FlMethodChannel* channel,
                                        FlMethodCall* method_call,
                                        gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "readFiles") == 0) {
    GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
    g_autoptr(FlValue) paths = fl_value_new_list();
    gchar** uris = gtk_clipboard_wait_for_uris(clipboard);
    if (uris != nullptr) {
      for (gchar** uri = uris; *uri != nullptr; ++uri) {
        g_autofree gchar* path = g_filename_from_uri(*uri, nullptr, nullptr);
        if (path != nullptr) {
          fl_value_append_take(paths, fl_value_new_string(path));
        }
      }
      g_strfreev(uris);
    }
    g_autofree gchar* image_path = nullptr;
    if (fl_value_get_length(paths) == 0) {
      GdkPixbuf* pixbuf = gtk_clipboard_wait_for_image(clipboard);
      if (pixbuf != nullptr) {
        image_path = clipboard_save_image(pixbuf);
        g_object_unref(pixbuf);
      }
    }
    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "paths", g_steal_pointer(&paths));
    fl_value_set_string_take(
        result, "imagePath",
        image_path != nullptr ? fl_value_new_string(image_path)
                              : fl_value_new_null());
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Telegram-faithful chrome: the app draws its own 24px title strip with
  // window controls, so the window itself is frameless on every desktop.
  gtk_window_set_title(window, "TangleX");
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_default_size(window, 1280, 720);
  self->window = window;

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Matches the night palette window background so the first frame and the
  // resize gutter never flash white.
  gdk_rgba_parse(&background_color, "#17212B");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  FlEngine* engine = fl_view_get_engine(view);
  self->window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine), "tanglex/window",
      FL_METHOD_CODEC(fl_standard_method_codec_new()));
  fl_method_channel_set_method_call_handler(self->window_channel,
                                            window_channel_method_cb, self,
                                            nullptr);
  self->clipboard_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine), "tanglex/clipboard",
      FL_METHOD_CODEC(fl_standard_method_codec_new()));
  fl_method_channel_set_method_call_handler(self->clipboard_channel,
                                            clipboard_channel_method_cb, self,
                                            nullptr);
  g_signal_connect(window, "window-state-event",
                   G_CALLBACK(window_state_changed_cb), self);

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

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
  g_clear_object(&self->window_channel);
  g_clear_object(&self->clipboard_channel);
  self->window = nullptr;
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
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
