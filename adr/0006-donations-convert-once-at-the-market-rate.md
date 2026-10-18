# Donations convert once, at the market rate, from exactly one source

A goal sums donations given in toman, dollars, euros, crypto, Bits, KICKs and subscriptions, so
every donation is converted into the goal currency once, when it arrives, and keeps that value.
The toman rate is the free market's (Nobitex's toman per USDT, times the European Central Bank's
euro-dollar rate for euros), never the official rial rate, which is a fraction of what toman
trades at. Each donation is counted from exactly one source: the platform's own event or the
donation site's API, never also from a bot's chat announcement of the same money.

## Considered Options

- **Revaluing every donation at today's rate** -- rejected: the rial moves enough that the bar
  would climb or fall with nobody donating, and it would no longer match what donors saw.
- **The official rial rate** -- rejected: it undervalues a dollar donation several times over.
- **Counting every report and matching duplicates by name, amount and time** -- rejected: two
  viewers can give the same amount seconds apart, so matching either double-counts or drops
  real money.

## Consequences

Each stored donation keeps its original amount and currency next to the converted value, so a
mistake in a rate can be found and corrected by hand. A donation that arrives with no rate under
24 hours old (and no streamer-set rate) waits as pending instead of using a stale or invented
one. Bots that announce donations count only for money nothing more direct reports.
