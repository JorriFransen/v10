#include <stdlib.h>

extern void* tinyobj_malloc(size_t size);
extern void* tinyobj_calloc(size_t num, size_t size);
extern void tinyobj_free(void* ptr);
extern void* tinyobj_realloc(void* ptr, size_t size);

#define TINYOBJ_MALLOC tinyobj_malloc
#define TINYOBJ_CALLOC tinyobj_calloc
#define TINYOBJ_FREE tinyobj_free
#define TINYOBJ_REALLOC tinyobj_realloc

#define TINYOBJ_LOADER_C_IMPLEMENTATION
#include "tiny_obj_loader.h"
