import 'dart:math';

/// Generates a friendly room code that reads like a tiny **magic sentence**,
/// e.g. `sleepy-otter-counts-cozy-stars`.
///
/// ## Why a sentence
/// On a public Syncplay server the room name is the only thing that keeps a room
/// private: rooms are isolated and unlisted, and the wire `password` field is a
/// *server* password that public servers ignore. So privacy here comes from
/// making the room name unguessable. The generated string IS the room. For
/// sharing, `room_share.dart` may wrap it in a self-contained code that appends
/// a non-default server (`room@host:port`), but the room name itself is never
/// split apart or re-sent as a server password; that's a separate axis (the
/// Advanced "Server password" field), and conflating the two would both mangle
/// real room names and misuse the server password.
///
/// Earlier builds bought unguessability with a random gibberish suffix
/// (`cozy-fox-42-k3pn`). This generator instead spends the entropy on *real,
/// friendly words* so the code stays cute and easy to dictate aloud — the threat
/// model is blocking accidental / guessed joins, not resisting a determined
/// brute-forcer.
///
/// ## The 35-character ceiling (why it's a short sentence, not a long one)
/// Syncplay caps room names at `MAX_ROOM_NAME_LENGTH = 35` and silently
/// *truncates* anything longer (it does not reject it). A truncated code is
/// quietly corrupted — the copied string no longer matches the real room, and
/// any entropy past char 35 is thrown away — so the generator must keep *every*
/// code within 35 characters. [maxGeneratedRoomCodeLength] asserts this against
/// the word lists below; the structure (adjective-animal-verb-adjective-noun
/// with words capped at six letters) keeps the worst case at 34.
///
/// ## Entropy
/// `64 adjectives * 64 animals * 48 verbs * 64 adjectives * 56 nouns ≈ 7.0e8`
/// distinct codes. That is far below the ~2e10 of the random-suffix scheme it
/// replaces — the 35-char ceiling makes that unreachable with real words — but
/// still ~700 million, three orders of magnitude past the point where accidental
/// or guessed joins are a concern on an unlisted public room.
///
/// ## Backward compatibility
/// Falls out for free: an old room-only code (`cozy-fox-42`) or a folded
/// `…-k3pn` code is just some string, and any string is a valid room name. A
/// friend pasting one into "Enter code from friend" joins that exact room, so
/// existing saved profiles and already-shared codes keep working unchanged.

/// Friendly, easy-to-say adjectives (all ≤6 letters). Drawn twice — once for the
/// animal subject, once for the noun object (`sleepy-otter-counts-cozy-stars`).
const List<String> roomAdjectives = <String>[
  'cozy',
  'sleepy',
  'fuzzy',
  'happy',
  'silly',
  'mellow',
  'sunny',
  'snug',
  'witty',
  'jolly',
  'breezy',
  'plucky',
  'dreamy',
  'peppy',
  'swift',
  'gentle',
  'brave',
  'calm',
  'chirpy',
  'chubby',
  'classy',
  'clever',
  'comfy',
  'dapper',
  'eager',
  'fancy',
  'fluffy',
  'frisky',
  'golden',
  'jaunty',
  'kindly',
  'lively',
  'lucky',
  'merry',
  'nifty',
  'nimble',
  'perky',
  'proud',
  'quiet',
  'quirky',
  'rosy',
  'sandy',
  'shiny',
  'smiley',
  'snowy',
  'soft',
  'spry',
  'starry',
  'sturdy',
  'sweet',
  'tender',
  'tidy',
  'tiny',
  'toasty',
  'velvet',
  'warm',
  'wavy',
  'wise',
  'zesty',
  'amber',
  'bouncy',
  'bubbly',
  'cuddly',
  'dusky',
];

/// Friendly, easy-to-say animals (all ≤6 letters).
const List<String> roomAnimals = <String>[
  'fox',
  'cat',
  'owl',
  'panda',
  'otter',
  'koala',
  'lynx',
  'hare',
  'wolf',
  'seal',
  'crow',
  'moth',
  'newt',
  'toad',
  'wren',
  'yak',
  'deer',
  'bear',
  'hawk',
  'dove',
  'swan',
  'mole',
  'mouse',
  'finch',
  'robin',
  'magpie',
  'badger',
  'beaver',
  'bison',
  'camel',
  'crab',
  'duck',
  'eagle',
  'ferret',
  'gecko',
  'goat',
  'goose',
  'heron',
  'jay',
  'lamb',
  'lark',
  'llama',
  'lemur',
  'mink',
  'parrot',
  'pony',
  'quail',
  'rabbit',
  'raven',
  'shrew',
  'skunk',
  'sloth',
  'snail',
  'stoat',
  'stork',
  'puffin',
  'tapir',
  'tiger',
  'turtle',
  'vole',
  'walrus',
  'weasel',
  'whale',
  'zebra',
];

/// Playful verbs (3rd-person singular, all ≤6 letters) joining the subject to
/// the object so each code reads as a little sentence.
const List<String> roomVerbs = <String>[
  'chases',
  'counts',
  'guards',
  'paints',
  'finds',
  'greets',
  'hugs',
  'sniffs',
  'nudges',
  'stacks',
  'bakes',
  'spots',
  'shares',
  'saves',
  'seeks',
  'minds',
  'keeps',
  'pets',
  'draws',
  'rolls',
  'spins',
  'tends',
  'hoards',
  'trails',
  'herds',
  'rides',
  'picks',
  'packs',
  'sorts',
  'tastes',
  'grooms',
  'wears',
  'pokes',
  'waves',
  'names',
  'calls',
  'meets',
  'leads',
  'feeds',
  'holds',
  'lifts',
  'tosses',
  'throws',
  'paws',
  'boops',
  'nabs',
  'bops',
  'sways',
];

/// Cute, concrete nouns (all ≤6 letters) for the object of the sentence.
const List<String> roomNouns = <String>[
  'moon',
  'star',
  'stars',
  'cloud',
  'comet',
  'acorn',
  'pebble',
  'ribbon',
  'bubble',
  'muffin',
  'teapot',
  'mitten',
  'pillow',
  'cookie',
  'maple',
  'willow',
  'meadow',
  'river',
  'breeze',
  'petal',
  'daisy',
  'clover',
  'honey',
  'berry',
  'candle',
  'marble',
  'button',
  'noodle',
  'waffle',
  'donut',
  'cherry',
  'peach',
  'plum',
  'mango',
  'lemon',
  'melon',
  'carrot',
  'pickle',
  'bagel',
  'scone',
  'jelly',
  'gummy',
  'fairy',
  'dragon',
  'castle',
  'puddle',
  'kitten',
  'puppy',
  'bunny',
  'teddy',
  'cocoa',
  'latte',
  'tulip',
  'rose',
  'lily',
  'fern',
];

/// The number of distinct codes this generator can produce: an independent draw
/// of (adjective, animal, verb, adjective, noun).
final int roomCodeCombinations =
    roomAdjectives.length *
    roomAnimals.length *
    roomVerbs.length *
    roomAdjectives.length *
    roomNouns.length;

/// The longest code [generateRoomCode] can ever emit, computed from the word
/// lists. Syncplay truncates room names past 35 characters, so this MUST stay
/// ≤35 — a unit test guards it so growing a word list can't silently break the
/// generated codes.
int get maxGeneratedRoomCodeLength {
  int longest(List<String> words) => words.map((w) => w.length).reduce(max);
  // adjective-animal-verb-adjective-noun + 4 hyphens.
  return 2 * longest(roomAdjectives) +
      longest(roomAnimals) +
      longest(roomVerbs) +
      longest(roomNouns) +
      4;
}

/// Generates a friendly room code like `sleepy-otter-counts-cozy-stars`.
///
/// The five slots are drawn independently, so a code may occasionally repeat the
/// adjective (`sleepy-otter-counts-sleepy-stars`); that still reads fine and a
/// redraw would only muddy the deterministic seeding below.
///
/// Pass a seeded [Random] in tests for deterministic output. In production no
/// argument is passed, so a cryptographically secure [Random.secure] backs the
/// draw — privacy now rests entirely on the code being unguessable, so the
/// generator must not lean on a predictable PRNG.
String generateRoomCode([Random? random]) {
  final r = random ?? Random.secure();
  String pick(List<String> words) => words[r.nextInt(words.length)];
  final subjectAdjective = pick(roomAdjectives);
  final animal = pick(roomAnimals);
  final verb = pick(roomVerbs);
  final objectAdjective = pick(roomAdjectives);
  final noun = pick(roomNouns);
  return '$subjectAdjective-$animal-$verb-$objectAdjective-$noun';
}
