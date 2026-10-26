/// Reviewed wildlife footage only. Gift events cannot supply media URLs.
const pulseGiftMovies = <String, String>{
  'lion': 'lion', 'royal_lions': 'royal_lions',
  'gorilla': 'gorilla', 'thunder_falcon': 'thunder_falcon',
};
const pulseGiftVideoPrices = <String, int>{
  'lion': 5000, 'royal_lions': 34000, 'gorilla': 30000, 'thunder_falcon': 39999,
};
bool pulseGiftHasVideo(Map event) {
  final price = event['coins'] is num ? (event['coins'] as num).toInt() : pulseGiftVideoPrices[event['sku']];
  return price != null && price >= 300 && pulseGiftMovies.containsKey(event['sku']);
}
const pulseGiftCredits = <String, String>{
  'lion': 'Lions in the wild · Coverr · CC0 1.0\nhttps://commons.wikimedia.org/wiki/File:Lions_in_the_wild.webm\nhttps://creativecommons.org/publicdomain/zero/1.0/\nTrimmed, resized and re-encoded for Pulse.',
  'royal_lions': 'Lions in the wild · Coverr · CC0 1.0\nhttps://commons.wikimedia.org/wiki/File:Lions_in_the_wild.webm\nhttps://creativecommons.org/publicdomain/zero/1.0/\nDifferent excerpt, resized and re-encoded for Pulse.',
  'gorilla': 'Wild Western Lowland gorilla and his family foraging for figs · TheLeftCoast · CC BY 4.0\nhttps://commons.wikimedia.org/wiki/File:Wild_Western_Lowland_gorilla_and_his_family_foraging_for_figs.webm\nhttps://creativecommons.org/licenses/by/4.0/\nTrimmed, resized and re-encoded for Pulse. No endorsement implied.',
  'thunder_falcon': 'Peregrine falcon in West Reno, Nevada, USA · Paul Hurtado · CC BY-SA 2.0\nhttps://commons.wikimedia.org/wiki/File:Peregrine_falcon_(Falco_peregrinus)_in_West_Reno,_Nevada,_USA.webm\nhttps://creativecommons.org/licenses/by-sa/2.0/\nTrimmed, resized and re-encoded. This video excerpt and thumbnail remain CC BY-SA 2.0. No endorsement implied.',
};
