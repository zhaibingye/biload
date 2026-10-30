#include "my_application.h"

// GLib caches these directories on first use. Keep the override inside this
// process so a player launched by biload still uses its own normal profile.
static bool pin_directory(const char* variable, const char* path,
                          const gchar* (*lookup)()) {
  g_autofree gchar* previous = g_strdup(g_getenv(variable));
  g_setenv(variable, path, TRUE);
  const bool pinned = g_strcmp0(lookup(), path) == 0;
  if (previous != nullptr) {
    g_setenv(variable, previous, TRUE);
  } else {
    g_unsetenv(variable);
  }
  return pinned;
}

int main(int argc, char** argv) {
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
  if (executable == nullptr) {
    g_printerr("Cannot locate the biload installation directory.\n");
    return 1;
  }
  g_autofree gchar* root = g_path_get_dirname(executable);
  g_autofree gchar* data = g_build_filename(root, "user-data", nullptr);
  g_autofree gchar* config = g_build_filename(data, "config", nullptr);
  g_autofree gchar* web = g_build_filename(data, "web-data", nullptr);
  g_autofree gchar* cache = g_build_filename(data, "cache", nullptr);
  if (!pin_directory("XDG_CONFIG_HOME", config, g_get_user_config_dir) ||
      !pin_directory("XDG_DATA_HOME", web, g_get_user_data_dir) ||
      !pin_directory("XDG_CACHE_HOME", cache, g_get_user_cache_dir)) {
    g_printerr("Cannot initialize user-data beside the biload executable.\n");
    return 1;
  }
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
