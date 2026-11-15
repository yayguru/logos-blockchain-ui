#pragma once

#include <array>
#include <cstdint>
#include <string>

// LEZ public-account keys, the way the LEZ wallet makes them (logos-execution-
// zone lee/state_machine/src/signature): a random secp256k1 secret key, its
// BIP-340 x-only public key, and
//   AccountId = SHA-256("/LEE/v0.3/AccountId/Public/" padded to 32 bytes || x)
// shown in base58. Verified against the testnet's genesis public accounts.
// The secret key is importable into the official wallet with
//   wallet account import public --private-key <hex>
//
// Self-contained (no OpenSSL / libsecp256k1 in the Windows build). Key
// generation happens once, locally, so the plain affine double-and-add here is
// fine; it is not used for signing.
namespace lezkeys {

using Bytes32 = std::array<uint8_t, 32>;

// false if `secret` is 0 or >= the curve order.
bool isValidSecret(const Bytes32& secret);
// x-only public key of `secret` (must be valid).
Bytes32 xOnlyPublicKey(const Bytes32& secret);
// Raw 32-byte account id for an x-only public key.
Bytes32 accountIdFromPublicKey(const Bytes32& xonly);
std::string base58(const uint8_t* data, size_t len);
std::string hex(const uint8_t* data, size_t len);

} // namespace lezkeys
