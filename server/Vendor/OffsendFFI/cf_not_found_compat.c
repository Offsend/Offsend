/* HTTPTypes (prebuilt against older SDKs) still references an exported
 * kCFNotFound. macOS 26 SDKs changed it to a static inline in the header, so
 * the linker never sees a global symbol. Define one without including CFBase.h
 * (which would make it static again).
 */
typedef long CFIndex;
const CFIndex kCFNotFound = -1;
