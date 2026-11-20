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
// true if `xonly` is the x coordinate of a curve point (x < p and x^3 + 7 is a
// square mod p): what LEZ's PublicKey::try_new (k256 schnorr VerifyingKey)
// accepts. A deposit naming any other 32 bytes is skipped by the sequencer.
bool isValidXOnly(const Bytes32& xonly);
// LEZ 0.4 bridge deposit metadata for a public account: borsh of
// DepositMetadata { recipient: DepositRecipient::Identified(
//     PublicAccountEvidence::Key(pk)) } = 0x01 0x00 || pk (34 bytes).
// (0.3.x took the bare 32-byte account id; 0.4 skips that form.)
std::array<uint8_t, 34> depositMetadata(const Bytes32& xonly);
// Raw 32-byte account id for an x-only public key.
Bytes32 accountIdFromPublicKey(const Bytes32& xonly);
std::string base58(const uint8_t* data, size_t len);
std::string hex(const uint8_t* data, size_t len);

} // namespace lezkeys
