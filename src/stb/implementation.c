#include "stddef.h"

void stbZigAssert(int x);

void* stbiZigMalloc(size_t size);
void* stbiZigRealloc(void *p, size_t size);
void stbiZigFree(void *p);

#define STB_IMAGE_IMPLEMENTATION
#define STBI_ASSERT(x) stbZigAssert(x)
#define STBI_MALLOC(size) stbiZigMalloc(size)
#define STBI_REALLOC(p,newsz) stbiZigRealloc(p, newsz)
#define STBI_FREE(p) stbiZigFree(p)
#include "stb_image.h"




#define STB_RECT_PACK_IMPLEMENTATION
#include "stb_rect_pack.h"




int stbttZigIFloor(double x);
int stbttZigICeil(double x);
double stbttZigSqrt(double x);
double stbttZigPow(double x, double y);
double stbttZigFmod(double x, double y);
double stbttZigCos(double x);
double stbttZigACos(double x);
double stbttZigFabs(double x);
void *stbttZigMalloc(size_t x, void *u);
void stbttZigFree(void *x, void *u);
size_t stbttZigStrlen(const char *x);
void *stbttZigMemcpy(void *dest, const void *restrict src, size_t count);
void *stbttZigMemset(void *dest, int ch, size_t count);

#define STB_TRUETYPE_IMPLEMENTATION
#define STBTT_ifloor(x)    stbttZigIFloor(x)
#define STBTT_iceil(x)     stbttZigICeil(x)
#define STBTT_sqrt(x)      stbttZigSqrt(x)
#define STBTT_pow(x, y)    stbttZigPow(x, y)
#define STBTT_fmod(x, y)   stbttZigFmod(x, y)
#define STBTT_cos(x)       stbttZigCos(x)
#define STBTT_acos(x)      stbttZigACos(x)
#define STBTT_fabs(x)      stbttZigFabs(x)
#define STBTT_malloc(x, u) stbttZigMalloc(x, u)
#define STBTT_free(x, u)   stbttZigFree(x, u)
#define STBTT_assert(x)    stbZigAssert(x)
#define STBTT_strlen(x)    stbttZigStrlen(x)
#define STBTT_memcpy       stbttZigMemcpy
#define STBTT_memset       stbttZigMemset
#include "stb_truetype.h"
