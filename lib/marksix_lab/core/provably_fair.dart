import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'combinatorics.dart';
import 'drbg.dart';

String toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List fromHex(String hex) {
  final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Inputs that fully determine a generated ticket.
class DrawRecipe {
  const DrawRecipe({
    required this.serverSeedHex,
    required this.clientSeedHex,
    required this.publicContext,
    required this.drawLabel,
  });

  final String serverSeedHex;
  final String clientSeedHex;

  /// Public, third-party-verifiable data (space weather, moon phase, tide...).
  final String publicContext;
  final String drawLabel;

  List<int> get ikm => <int>[
    ...fromHex(serverSeedHex),
    ...fromHex(clientSeedHex),
    ...utf8.encode(publicContext),
    ...utf8.encode(drawLabel),
  ];
}

class GeneratedTicket {
  const GeneratedTicket({
    required this.numbers,
    required this.recipe,
    required this.commitment,
    required this.rerollCount,
  });

  final List<int> numbers;
  final DrawRecipe recipe;
  final String commitment;

  /// How many candidate combinations the anti-crowd filter rejected. Recorded
  /// so the result stays reproducible from the recipe alone.
  final int rerollCount;
}

/// Commit-reveal generation.
///
/// Before generating, the app publishes `commitment = SHA256(serverSeed)`.
/// After the draw it reveals `serverSeed`, and anyone can recompute the numbers
/// and confirm nothing was altered after the fact.
class ProvablyFair {
  static String commit(String serverSeedHex) =>
      toHex(sha256.convert(fromHex(serverSeedHex)).bytes);

  static bool verifyCommitment(String serverSeedHex, String commitment) =>
      commit(serverSeedHex).toLowerCase() == commitment.toLowerCase().trim();

  static Drbg drbg(DrawRecipe recipe) => Drbg.fromMaterial(
    ikm: recipe.ikm,
    salt: utf8.encode('marksix-physics-lab/v1'),
    info: utf8.encode('draw:${recipe.drawLabel}'),
  );

  /// Deterministically regenerate the numbers for a recipe.
  ///
  /// [reject] lets the anti-crowd filter discard popular combinations; the
  /// number of rejections is returned so verification is exact.
  static GeneratedTicket generate(
    DrawRecipe recipe, {
    bool Function(List<int> candidate)? reject,
    int maxRerolls = 200,
  }) {
    final rng = drbg(recipe);
    var rerolls = 0;
    var numbers = rng.chooseSubset(kBallCount, kPickCount);
    while (reject != null && reject(numbers) && rerolls < maxRerolls) {
      rerolls++;
      numbers = rng.chooseSubset(kBallCount, kPickCount);
    }
    return GeneratedTicket(
      numbers: numbers,
      recipe: recipe,
      commitment: commit(recipe.serverSeedHex),
      rerollCount: rerolls,
    );
  }
}
