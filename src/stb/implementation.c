#include "stddef.h"

void stbiZigAssert(int x);
void* stbiZigMalloc(size_t size);
void* stbiZigRealloc(void *p, size_t size);
void stbiZigFree(void *p);

#define STB_IMAGE_IMPLEMENTATION
#define STBI_ASSERT(x) stbiZigAssert(x)
#define STBI_MALLOC(size) stbiZigMalloc(size)
#define STBI_REALLOC(p,newsz) stbiZigRealloc(p,newsz)
#define STBI_FREE(p) stbiZigFree(p)
#include "stb_image.h"

#define STB_RECT_PACK_IMPLEMENTATION
#include "stb_rect_pack.h"

#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"
