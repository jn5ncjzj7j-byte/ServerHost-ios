#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>

typedef int (*JLI_LaunchFunction)(int, const char **, int, const char **, int, const char **, const char *, const char *, const char *, const char *, unsigned char, unsigned char, unsigned char, int);
typedef void (*ServerOutputCallback)(const char *, void *);

typedef struct {
    char java_home[4096];
    char working_directory[4096];
    char jar_path[4096];
    int heap_mb;
    ServerOutputCallback callback;
    void *context;
} ServerLaunchArguments;

typedef struct {
    int descriptor;
    ServerOutputCallback callback;
    void *context;
} ServerOutputArguments;

static int server_input_fd = -1;
static pthread_mutex_t server_lock = PTHREAD_MUTEX_INITIALIZER;

static void emit_output(ServerLaunchArguments *arguments, const char *message) {
    if (arguments->callback) arguments->callback(message, arguments->context);
}

static void *read_server_output(void *value) {
    ServerOutputArguments *arguments = value;
    int descriptor = arguments->descriptor;
    char buffer[2048];
    char line[8192];
    size_t used = 0;
    ssize_t count;
    while ((count = read(descriptor, buffer, sizeof(buffer))) > 0) {
        for (ssize_t index = 0; index < count; index++) {
            char character = buffer[index];
            if (used < sizeof(line) - 1) line[used++] = character;
            if (character == '\\n' || used == sizeof(line) - 1) {
                line[used] = 0;
                if (arguments->callback) arguments->callback(line, arguments->context);
                used = 0;
            }
        }
    }
    if (used) {
        line[used] = 0;
        if (arguments->callback) arguments->callback(line, arguments->context);
    }
    close(descriptor);
    free(arguments);
    return NULL;
}

static void *launch_server(void *value) {
    ServerLaunchArguments *arguments = value;
    int output_read = *(int *)((char *)value + sizeof(ServerLaunchArguments));
    int output_write = *(int *)((char *)value + sizeof(ServerLaunchArguments) + sizeof(int));
    int input_read = *(int *)((char *)value + sizeof(ServerLaunchArguments) + sizeof(int) * 2);
    int input_write = *(int *)((char *)value + sizeof(ServerLaunchArguments) + sizeof(int) * 3);

    char java8_path[8192];
    char java_path[8192];
    snprintf(java8_path, sizeof(java8_path), "%s/lib/jli/libjli.dylib", arguments->java_home);
    snprintf(java_path, sizeof(java_path), "%s/lib/libjli.dylib", arguments->java_home);

    const char *jli_path = access(java8_path, F_OK) == 0 ? java8_path : java_path;
    setenv("JAVA_HOME", arguments->java_home, 1);
    setenv("HOME", arguments->working_directory, 1);
    setenv("TMPDIR", arguments->working_directory, 1);
    setenv("HACK_IGNORE_START_ON_FIRST_THREAD", "1", 1);
    setenv("LC_ALL", "en_US.UTF-8", 1);
    chdir(arguments->working_directory);

    int saved_stdout = dup(STDOUT_FILENO);
    int saved_stderr = dup(STDERR_FILENO);
    int saved_stdin = dup(STDIN_FILENO);
    dup2(output_write, STDOUT_FILENO);
    dup2(output_write, STDERR_FILENO);
    dup2(input_read, STDIN_FILENO);
    close(output_write);
    close(input_read);

    pthread_t reader;
    ServerOutputArguments *reader_arguments = calloc(1, sizeof(ServerOutputArguments));
    if (!reader_arguments) {
        dup2(saved_stdout, STDOUT_FILENO);
        dup2(saved_stderr, STDERR_FILENO);
        dup2(saved_stdin, STDIN_FILENO);
        close(saved_stdout);
        close(saved_stderr);
        close(saved_stdin);
        close(output_read);
        close(input_write);
        pthread_mutex_lock(&server_lock);
        server_input_fd = -1;
        pthread_mutex_unlock(&server_lock);
        emit_output(arguments, "[ServerHost] Could not allocate the server output reader.");
        emit_output(arguments, "[ServerHost] EXIT: -1");
        free(arguments);
        return NULL;
    }
    reader_arguments->descriptor = output_read;
    reader_arguments->callback = arguments->callback;
    reader_arguments->context = arguments->context;
    int reader_result = pthread_create(&reader, NULL, read_server_output, reader_arguments);
    if (reader_result != 0) {
        free(reader_arguments);
        dup2(saved_stdout, STDOUT_FILENO);
        dup2(saved_stderr, STDERR_FILENO);
        dup2(saved_stdin, STDIN_FILENO);
        close(saved_stdout);
        close(saved_stderr);
        close(saved_stdin);
        close(output_read);
        close(input_write);
        pthread_mutex_lock(&server_lock);
        server_input_fd = -1;
        pthread_mutex_unlock(&server_lock);
        emit_output(arguments, "[ServerHost] Could not create the server output reader thread.");
        emit_output(arguments, "[ServerHost] EXIT: -1");
        free(arguments);
        return NULL;
    }

    void *library = dlopen(jli_path, RTLD_NOW | RTLD_GLOBAL);
    if (!library) {
        const char *error = dlerror();
        dup2(saved_stdout, STDOUT_FILENO);
        dup2(saved_stderr, STDERR_FILENO);
        dup2(saved_stdin, STDIN_FILENO);
        char message[4096];
        snprintf(message, sizeof(message), "[ServerHost] Java runtime load failed: %s", error ? error : "unknown error");
        emit_output(arguments, message);
        close(saved_stdout);
        close(saved_stderr);
        close(saved_stdin);
        close(input_write);
        pthread_mutex_lock(&server_lock);
        server_input_fd = -1;
        pthread_mutex_unlock(&server_lock);
        emit_output(arguments, "[ServerHost] EXIT: -1");
        pthread_join(reader, NULL);
        free(arguments);
        return NULL;
    }

    JLI_LaunchFunction launch = (JLI_LaunchFunction)dlsym(library, "JLI_Launch");
    if (!launch) {
        emit_output(arguments, "[ServerHost] JLI_Launch symbol was not found.");
        emit_output(arguments, "[ServerHost] EXIT: -1");
    } else {
        char heap_argument[64];
        snprintf(heap_argument, sizeof(heap_argument), "-Xmx%dM", arguments->heap_mb);
        const char *argv[] = {
            "java",
            "-Xms128M",
            heap_argument,
            "-Djava.awt.headless=true",
            "-Dfile.encoding=UTF-8",
            "-Duser.dir=.",
            "-Duser.home=.",
            "-jar",
            arguments->jar_path,
            "nogui",
            NULL
        };
        emit_output(arguments, "[ServerHost] Java runtime loaded. Launching server...");
        int result = launch(10, argv, 0, NULL, 0, NULL, "1.8.0", "1.8", "java", "openjdk", 0, 1, 0, 1);
        char exit_message[128];
        snprintf(exit_message, sizeof(exit_message), "[ServerHost] EXIT: %d", result);
        emit_output(arguments, exit_message);
    }

    dup2(saved_stdout, STDOUT_FILENO);
    dup2(saved_stderr, STDERR_FILENO);
    dup2(saved_stdin, STDIN_FILENO);
    close(saved_stdout);
    close(saved_stderr);
    close(saved_stdin);
    close(input_write);
    pthread_mutex_lock(&server_lock);
    server_input_fd = -1;
    pthread_mutex_unlock(&server_lock);
    pthread_join(reader, NULL);
    free(arguments);
    return NULL;
}

int server_runtime_start(const char *java_home, const char *working_directory, const char *jar_path, int heap_mb, ServerOutputCallback callback, void *context) {
    if (!java_home || !working_directory || !jar_path) return -1;
    pthread_mutex_lock(&server_lock);
    if (server_input_fd >= 0) {
        pthread_mutex_unlock(&server_lock);
        return -2;
    }

    int output_pipe[2];
    int input_pipe[2];
    if (pipe(output_pipe) != 0) {
        pthread_mutex_unlock(&server_lock);
        return -3;
    }
    if (pipe(input_pipe) != 0) {
        close(output_pipe[0]);
        close(output_pipe[1]);
        pthread_mutex_unlock(&server_lock);
        return -3;
    }

    ServerLaunchArguments *arguments = calloc(1, sizeof(ServerLaunchArguments) + sizeof(int) * 4);
    if (!arguments) {
        pthread_mutex_unlock(&server_lock);
        return -4;
    }
    snprintf(arguments->java_home, sizeof(arguments->java_home), "%s", java_home);
    snprintf(arguments->working_directory, sizeof(arguments->working_directory), "%s", working_directory);
    snprintf(arguments->jar_path, sizeof(arguments->jar_path), "%s", jar_path);
    arguments->heap_mb = heap_mb;
    arguments->callback = callback;
    arguments->context = context;

    int *descriptors = (int *)((char *)arguments + sizeof(ServerLaunchArguments));
    descriptors[0] = output_pipe[0];
    descriptors[1] = output_pipe[1];
    descriptors[2] = input_pipe[0];
    descriptors[3] = input_pipe[1];
    server_input_fd = input_pipe[1];

    pthread_t thread;
    pthread_attr_t attributes;
    pthread_attr_init(&attributes);
    pthread_attr_setstacksize(&attributes, 8 * 1024 * 1024);
    int result = pthread_create(&thread, &attributes, launch_server, arguments);
    pthread_attr_destroy(&attributes);
    if (result != 0) {
        server_input_fd = -1;
        close(output_pipe[0]);
        close(output_pipe[1]);
        close(input_pipe[0]);
        close(input_pipe[1]);
        free(arguments);
        pthread_mutex_unlock(&server_lock);
        return -5;
    }
    pthread_detach(thread);
    pthread_mutex_unlock(&server_lock);
    return 0;
}

int server_runtime_send_command(const char *command) {
    if (!command) return -1;
    pthread_mutex_lock(&server_lock);
    int descriptor = server_input_fd;
    if (descriptor < 0) {
        pthread_mutex_unlock(&server_lock);
        return -2;
    }
    size_t length = strlen(command);
    ssize_t written = write(descriptor, command, length);
    if (written == (ssize_t)length) write(descriptor, "\n", 1);
    pthread_mutex_unlock(&server_lock);
    return written < 0 ? -3 : 0;
}
