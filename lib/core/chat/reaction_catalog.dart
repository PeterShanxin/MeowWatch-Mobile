/// Picker choices only. Peers may send other reactions through the protocol.
const standardReactions = <String>['❤️', '😂', '😮', '👏', '🍿', '🥰'];

const movieNightReactions = <String>['🐱', '🎬', '🎞️', '✨', '👀', '☕'];

const premiumReactions = <String>{...movieNightReactions};

bool isPremiumReaction(String emoji) => premiumReactions.contains(emoji);
