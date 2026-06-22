/*
 * evp_stub.h - drop-in no-op replacement for the handful of OpenSSL EVP
 * symbols clawmon used (portlist.cpp only), so the ARM64 / llvm-mingw build
 * needs no OpenSSL (the bundled libeay32 is x86/x64-only).
 *
 * clawmon used AES only to obfuscate a "run-as fixed user" password stored in
 * the registry. We don't use fixed-user command launching (commands run as the
 * printing user, RunAsPUser=TRUE by default), so the password is never needed.
 *
 * Each stub returns 0 (failure). The existing code already treats a crypto
 * failure as "no password": it stores an empty string on load and writes a
 * zero-length REG_BINARY on save. So behaviour stays well-defined with zero deps.
 */
#ifndef EVP_STUB_H
#define EVP_STUB_H

typedef int  EVP_CIPHER_CTX;
typedef void EVP_CIPHER;

static __inline const EVP_CIPHER* EVP_aes_256_cbc(void) { return 0; }

static __inline int EVP_DecryptInit(EVP_CIPHER_CTX* c, const EVP_CIPHER* t,
        const unsigned char* k, const unsigned char* iv)
{ (void)c; (void)t; (void)k; (void)iv; return 0; }

static __inline int EVP_DecryptUpdate(EVP_CIPHER_CTX* c, unsigned char* out,
        int* outl, const unsigned char* in, int inl)
{ (void)c; (void)out; (void)in; (void)inl; if (outl) *outl = 0; return 0; }

static __inline int EVP_DecryptFinal(EVP_CIPHER_CTX* c, unsigned char* out, int* outl)
{ (void)c; (void)out; if (outl) *outl = 0; return 0; }

static __inline int EVP_EncryptInit(EVP_CIPHER_CTX* c, const EVP_CIPHER* t,
        const unsigned char* k, const unsigned char* iv)
{ (void)c; (void)t; (void)k; (void)iv; return 0; }

static __inline int EVP_EncryptUpdate(EVP_CIPHER_CTX* c, unsigned char* out,
        int* outl, const unsigned char* in, int inl)
{ (void)c; (void)out; (void)in; (void)inl; if (outl) *outl = 0; return 0; }

static __inline int EVP_EncryptFinal(EVP_CIPHER_CTX* c, unsigned char* out, int* outl)
{ (void)c; (void)out; if (outl) *outl = 0; return 0; }

static __inline void EVP_CIPHER_CTX_cleanup(EVP_CIPHER_CTX* c) { (void)c; }

#endif /* EVP_STUB_H */
