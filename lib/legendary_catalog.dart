class PulseLegendaryGift {
  const PulseLegendaryGift(
    this.title,
    this.coins,
    this.durationMs, [
    this.aspectRatio = 1.8,
  ]);
  final String title;
  final int coins, durationMs;
  final double aspectRatio;
}

/// Fixed paths only: neither gift events nor users can supply effect/audio URLs.
const pulseLegendaryGifts = <String, PulseLegendaryGift>{
  'legend_lion_king': PulseLegendaryGift(
    'Lion King',
    1000,
    5167,
    1.791044776119403,
  ),
  'legend_phoenix': PulseLegendaryGift(
    'Phoenix',
    5000,
    5167,
    1.791044776119403,
  ),
  'legend_thunder_god': PulseLegendaryGift(
    'Thunder God',
    7500,
    5167,
    1.791044776119403,
  ),
  'legend_phantom_supercar': PulseLegendaryGift(
    'Phantom Supercar',
    10000,
    5042,
    1.8181818181818181,
  ),
  'legend_cosmic_rocket': PulseLegendaryGift(
    'Cosmic Rocket',
    15000,
    5042,
    1.7391304347826086,
  ),
  'legend_royal_palace': PulseLegendaryGift(
    'Royal Palace',
    20000,
    5042,
    1.7391304347826086,
  ),
  'legend_galaxy_dragon': PulseLegendaryGift(
    'Galaxy Dragon',
    30000,
    5167,
    1.791044776119403,
  ),
  'legend_pulse_legend': PulseLegendaryGift(
    'Pulse Legend',
    50000,
    5042,
    1.8181818181818181,
  ),
  'legend_pulse_universe': PulseLegendaryGift(
    'Pulse Universe',
    60000,
    5042,
    1.7391304347826086,
  ),
};
PulseLegendaryGift? pulseLegendaryForEvent(Map event) {
  if (event['notification_only'] == true) return null;
  final gift = pulseLegendaryGifts[event['sku']];
  final price = event['coins'];
  return gift != null && (price is! num || price >= 300) ? gift : null;
}
