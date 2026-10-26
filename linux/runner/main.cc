#include <dlfcn.h>
#include <sys/types.h>
#include <unistd.h>

#include <cstdio>
#include <string>

#include "my_application.h"

// The bundled SimpleX core (libsimplex.so + Haskell deps) carries its own
// SQLCipher and is linked with -Bsymbolic, while libHSsqlcipher-simple resolves
// sqlite3_* from the global scope. Where GTK3 pulls libtinysparql (-> system
// libsqlite3) into the global scope, one DB session ends up split between two
// SQLite builds and crashes in sqlite3_finalize. Loading the core with
// RTLD_DEEPBIND keeps its own symbol scope ahead of the global one.
static void preload_simplex_core() {
  std::string path = "libsimplex.so";

  char exe[4096];
  ssize_t len = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
  if (len > 0) {
    exe[len] = '\0';
    std::string dir(exe);
    const size_t slash = dir.find_last_of('/');
    if (slash != std::string::npos) {
      path = dir.substr(0, slash) + "/lib/libsimplex.so";
    }
  }

  if (dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL | RTLD_DEEPBIND) == nullptr) {
    fprintf(stderr, "failed to preload simplex core: %s\n", dlerror());
  }
}

int main(int argc, char** argv) {
  preload_simplex_core();
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
