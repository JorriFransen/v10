
void zigAssert(int x);

#define STB_IMAGE_IMPLEMENTATION

#define STBI_ASSERT(x) zigAssert(x)

#include "stb_image.h"
