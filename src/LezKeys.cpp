#include "LezKeys.h"

#include <cstring>

namespace lezkeys {
namespace {

// 256-bit unsigned, little-endian 64-bit limbs.
struct U256 { uint64_t v[4]; };
using u128 = unsigned __int128;

const U256 P = {{0xFFFFFFFEFFFFFC2FULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL}};
const U256 N = {{0xBFD25E8CD0364141ULL, 0xBAAEDCE6AF48A03BULL, 0xFFFFFFFFFFFFFFFEULL, 0xFFFFFFFFFFFFFFFFULL}};
const U256 GX = {{0x59F2815B16F81798ULL, 0x029BFCDB2DCE28D9ULL, 0x55A06295CE870B07ULL, 0x79BE667EF9DCBBACULL}};
const U256 GY = {{0x9C47D08FFB10D4B8ULL, 0xFD17B448A6855419ULL, 0x5DA4FBFC0E1108A8ULL, 0x483ADA7726A3C465ULL}};

int cmp(const U256& a, const U256& b) {
    for (int i = 3; i >= 0; --i) {
        if (a.v[i] < b.v[i]) return -1;
        if (a.v[i] > b.v[i]) return 1;
    }
    return 0;
}
bool isZero(const U256& a) { return !(a.v[0] | a.v[1] | a.v[2] | a.v[3]); }

uint64_t addTo(U256& r, const U256& a, const U256& b) {
    u128 c = 0;
    for (int i = 0; i < 4; ++i) { c += (u128)a.v[i] + b.v[i]; r.v[i] = (uint64_t)c; c >>= 64; }
    return (uint64_t)c;
}
uint64_t subTo(U256& r, const U256& a, const U256& b) {
    uint64_t borrow = 0;
    for (int i = 0; i < 4; ++i) {
        u128 t = (u128)a.v[i] - b.v[i] - borrow;
        r.v[i] = (uint64_t)t;
        borrow = (uint64_t)(t >> 64) ? 1 : 0;
    }
    return borrow;
}

U256 fadd(const U256& a, const U256& b) {
    U256 r; uint64_t c = addTo(r, a, b);
    if (c || cmp(r, P) >= 0) subTo(r, r, P);
    return r;
}
U256 fsub(const U256& a, const U256& b) {
    U256 r; if (subTo(r, a, b)) addTo(r, r, P);
    return r;
}
// p = 2^256 - C, C = 0x1000003D1: fold the high half twice.
U256 fmul(const U256& a, const U256& b) {
    uint64_t t[8] = {0};
    for (int i = 0; i < 4; ++i) {
        u128 c = 0;
        for (int j = 0; j < 4; ++j) {
            c += (u128)a.v[i] * b.v[j] + t[i + j];
            t[i + j] = (uint64_t)c; c >>= 64;
        }
        t[i + 4] = (uint64_t)c;
    }
    const uint64_t C = 0x1000003D1ULL;
    uint64_t r[5]; u128 c = 0;
    for (int i = 0; i < 4; ++i) { c += (u128)t[i + 4] * C + t[i]; r[i] = (uint64_t)c; c >>= 64; }
    r[4] = (uint64_t)c;
    U256 out; c = (u128)r[4] * C;
    for (int i = 0; i < 4; ++i) { c += r[i]; out.v[i] = (uint64_t)c; c >>= 64; }
    if (c) { // one more fold
        u128 d = (u128)C;
        for (int i = 0; i < 4; ++i) { d += out.v[i]; out.v[i] = (uint64_t)d; d >>= 64; }
    }
    if (cmp(out, P) >= 0) subTo(out, out, P);
    return out;
}
U256 fpow(U256 a, const U256& e) {
    U256 r = {{1, 0, 0, 0}};
    for (int i = 255; i >= 0; --i) {
        r = fmul(r, r);
        if ((e.v[i / 64] >> (i % 64)) & 1) r = fmul(r, a);
    }
    return r;
}
U256 finv(const U256& a) { U256 e; U256 two = {{2, 0, 0, 0}}; subTo(e, P, two); return fpow(a, e); }

struct Pt { U256 x, y; bool inf; };

Pt dbl(const Pt& p) {
    if (p.inf || isZero(p.y)) return {{}, {}, true};
    U256 x2 = fmul(p.x, p.x);
    U256 num = fadd(fadd(x2, x2), x2);           // 3x^2 (a = 0)
    U256 lam = fmul(num, finv(fadd(p.y, p.y)));
    U256 x3 = fsub(fsub(fmul(lam, lam), p.x), p.x);
    U256 y3 = fsub(fmul(lam, fsub(p.x, x3)), p.y);
    return {x3, y3, false};
}
Pt add(const Pt& p, const Pt& q) {
    if (p.inf) return q;
    if (q.inf) return p;
    if (cmp(p.x, q.x) == 0) {
        if (cmp(p.y, q.y) == 0) return dbl(p);
        return {{}, {}, true};
    }
    U256 lam = fmul(fsub(q.y, p.y), finv(fsub(q.x, p.x)));
    U256 x3 = fsub(fsub(fmul(lam, lam), p.x), q.x);
    U256 y3 = fsub(fmul(lam, fsub(p.x, x3)), p.y);
    return {x3, y3, false};
}

U256 fromBE(const Bytes32& b) {
    U256 r;
    for (int i = 0; i < 4; ++i) {
        uint64_t w = 0;
        for (int j = 0; j < 8; ++j) w = (w << 8) | b[(3 - i) * 8 + j];
        r.v[i] = w;
    }
    return r;
}
Bytes32 toBE(const U256& a) {
    Bytes32 b{};
    for (int i = 0; i < 4; ++i)
        for (int j = 0; j < 8; ++j) b[(3 - i) * 8 + j] = (uint8_t)(a.v[i] >> (56 - 8 * j));
    return b;
}

// Minimal SHA-256.
struct Sha256 {
    uint32_t h[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
    uint8_t buf[64]; size_t len = 0; uint64_t total = 0;
    static uint32_t ror(uint32_t x, int n) { return (x >> n) | (x << (32 - n)); }
    void block(const uint8_t* p) {
        static const uint32_t k[64] = {
            0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
            0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
            0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
            0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};
        uint32_t w[64];
        for (int i = 0; i < 16; ++i) w[i] = (uint32_t)p[4*i] << 24 | (uint32_t)p[4*i+1] << 16 | (uint32_t)p[4*i+2] << 8 | p[4*i+3];
        for (int i = 16; i < 64; ++i) {
            uint32_t s0 = ror(w[i-15], 7) ^ ror(w[i-15], 18) ^ (w[i-15] >> 3);
            uint32_t s1 = ror(w[i-2], 17) ^ ror(w[i-2], 19) ^ (w[i-2] >> 10);
            w[i] = w[i-16] + s0 + w[i-7] + s1;
        }
        uint32_t a=h[0],b=h[1],c=h[2],d=h[3],e=h[4],f=h[5],g=h[6],hh=h[7];
        for (int i = 0; i < 64; ++i) {
            uint32_t t1 = hh + (ror(e,6)^ror(e,11)^ror(e,25)) + ((e&f)^(~e&g)) + k[i] + w[i];
            uint32_t t2 = (ror(a,2)^ror(a,13)^ror(a,22)) + ((a&b)^(a&c)^(b&c));
            hh=g; g=f; f=e; e=d+t1; d=c; c=b; b=a; a=t1+t2;
        }
        h[0]+=a;h[1]+=b;h[2]+=c;h[3]+=d;h[4]+=e;h[5]+=f;h[6]+=g;h[7]+=hh;
    }
    void update(const uint8_t* p, size_t n) {
        total += n;
        while (n--) { buf[len++] = *p++; if (len == 64) { block(buf); len = 0; } }
    }
    Bytes32 final() {
        uint64_t bits = total * 8;
        uint8_t one = 0x80, zero = 0;
        update(&one, 1);
        while (len != 56) update(&zero, 1);
        for (int i = 7; i >= 0; --i) { uint8_t b = (uint8_t)(bits >> (8 * i)); update(&b, 1); }
        Bytes32 out{};
        for (int i = 0; i < 8; ++i) for (int j = 0; j < 4; ++j) out[4*i+j] = (uint8_t)(h[i] >> (24 - 8*j));
        return out;
    }
};

} // namespace

bool isValidSecret(const Bytes32& secret) {
    const U256 s = fromBE(secret);
    return !isZero(s) && cmp(s, N) < 0;
}

Bytes32 xOnlyPublicKey(const Bytes32& secret) {
    const U256 k = fromBE(secret);
    Pt r{{}, {}, true};
    Pt g{GX, GY, false};
    for (int i = 0; i < 256; ++i) {
        if ((k.v[i / 64] >> (i % 64)) & 1) r = add(r, g);
        g = dbl(g);
    }
    return toBE(r.x);
}

bool isValidXOnly(const Bytes32& xonly) {
    const U256 x = fromBE(xonly);
    if (cmp(x, P) >= 0)
        return false;
    const U256 seven = {{7, 0, 0, 0}};
    const U256 y2 = fadd(fmul(fmul(x, x), x), seven);
    if (isZero(y2))
        return true;
    // Euler's criterion: y2^((p-1)/2) == 1.
    U256 e; const U256 one = {{1, 0, 0, 0}};
    subTo(e, P, one);
    for (int i = 0; i < 4; ++i) { // e >>= 1
        e.v[i] = (e.v[i] >> 1) | (i < 3 ? (e.v[i + 1] << 63) : 0);
    }
    return cmp(fpow(y2, e), one) == 0;
}

std::array<uint8_t, 34> depositMetadata(const Bytes32& xonly) {
    std::array<uint8_t, 34> m{};
    m[0] = 0x01; // DepositRecipient::Identified
    m[1] = 0x00; // PublicAccountEvidence::Key
    std::memcpy(m.data() + 2, xonly.data(), 32);
    return m;
}

Bytes32 accountIdFromPublicKey(const Bytes32& xonly) {
    uint8_t prefix[32] = {0};
    const char* tag = "/LEE/v0.3/AccountId/Public/";
    std::memcpy(prefix, tag, std::strlen(tag));
    Sha256 s;
    s.update(prefix, 32);
    s.update(xonly.data(), 32);
    return s.final();
}

std::string base58(const uint8_t* data, size_t len) {
    static const char* al = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    std::string digits;
    std::basic_string<uint8_t> num(data, data + len);
    size_t zeros = 0;
    while (zeros < len && data[zeros] == 0) ++zeros;
    size_t start = zeros;
    while (start < num.size()) {
        int rem = 0;
        for (size_t i = start; i < num.size(); ++i) {
            int acc = rem * 256 + num[i];
            num[i] = (uint8_t)(acc / 58);
            rem = acc % 58;
        }
        digits.push_back(al[rem]);
        while (start < num.size() && num[start] == 0) ++start;
    }
    std::string out(zeros, '1');
    out.append(digits.rbegin(), digits.rend());
    return out;
}

std::string hex(const uint8_t* data, size_t len) {
    static const char* h = "0123456789abcdef";
    std::string s; s.reserve(len * 2);
    for (size_t i = 0; i < len; ++i) { s.push_back(h[data[i] >> 4]); s.push_back(h[data[i] & 15]); }
    return s;
}

} // namespace lezkeys
