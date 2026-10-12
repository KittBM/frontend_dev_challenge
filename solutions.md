# Rescu — Solutions

All seven Part A tickets are fixed on this branch. Part B (F-1, F-2, F-3) was
not started; see [What's next](#time-spent-and-whats-next).

Every fix has a regression test under `test/`. I ran each test against the
code before its fix to check that it actually fails there. A few are guards
that pass on both on purpose: two RES-104 paging tests, "the open deal page
still re-checks its stock" (RES-103) and "in-app navigation still uses the
passed deal" (RES-107). Run them with:

```sh
fvm flutter test
```

Toolchain: Flutter 3.27.0 via FVM (`.fvmrc`), as pinned.

---

## Part A — Bug tickets

### RES-106 · Wrong pickup times; "Pickup today" misses deals

**Root cause.** The API sends ISO-8601 UTC instants (`2026-10-07T23:00:00Z`).
`DateTime.parse` keeps a `Z` string as a UTC `DateTime`, and nothing converted
it. `DateFormat('HH:mm')` formats a UTC `DateTime` in UTC, so a bakery open
06:00–09:30 Bangkok time (UTC+7) was labelled 23:00–02:30. `isToday` compared
`start.day` (the UTC day) with `DateTime.now().day` (the local day), so any
window before 07:00 local counted as "yesterday" and was dropped by the
filter. A second, latent bug: it compared only the day of the month, so
8 October also matched 8 November.

**Fix.** `PickupWindowModel.fromJson` converts both instants with
`.toLocal()`. Everything downstream (labels, the filter, the "today" suffix)
then works in the user's wall-clock time without needing to know about UTC.
`isToday` now compares year, month and day through
`startsOnSameDayAs(DateTime moment)`, which takes the reference time as a
parameter so tests do not depend on the clock.

**Rejected alternative.** Adding a hardcoded `+7h`. It only works for one
timezone, and it double-shifts if the device is already on UTC+7 and anyone
later adds `.toLocal()`.

**Edge cases.**
- Overnight windows (22:00–01:00) are tested and keep their local times.
- *Not handled:* "today" means the **device's** day, not the market's
  (Asia/Bangkok). A user travelling abroad with a phone in another timezone
  sees times in their own timezone. That is arguably correct for a countdown
  but wrong for "the store opens at 06:00". Fixing it would need the market
  timezone from the API and the `timezone` package.
- `OrderModel`, `flashSaleEndsAt` and reservations stay in UTC on purpose.
  They are only used for differences and comparisons between instants, which
  do not depend on the timezone.
- The existing `test/model_test.dart` asserted `start.isUtc == true`, which
  locked the bug in. It now asserts the same instant in local time.

### RES-101 · Search shows results for the wrong query

**Root cause.** Every keystroke started a search, and every response was
written to `results` in whatever order it arrived. Responses do not arrive in
order: `FakeApiService.searchDeals` takes `180 + max(0, 1200 − 280·length)` ms,
so broad queries are slower. Typing "sushi" letter by letter reliably makes the
response for "s" (~1.1 s) land after the one for "sushi" (~0.2 s) and
overwrite it. This is a race condition, not a performance problem. Also,
`isLoading` was switched off by whichever response came back first.

**Fix (2 commits).**
1. *Latest-wins:* each search gets an increasing id, and a response or error
   is applied only if it still belongs to the latest search. Clearing the box
   also bumps the id, so a slow search still in flight cannot refill an empty
   box.
2. *Debounce 300 ms:* only the text the user pauses on is sent. This reduces
   load (5 requests → 1 for "sushi"). The timer is cancelled in `onClose`.

**Rejected alternative.** Debounce on its own. It makes overlaps rarer but
does not remove them: pausing longer than the debounce window between two
queries still leaves two requests in flight, and the race returns.

**Edge cases.** An error on the latest query is logged and the previous
results stay on screen. There is no error UI, which was already the case
before; I left it as is. Results from the previous query stay visible during
the 300 ms debounce, which I think is better than flashing a spinner.

### RES-102 · Crash after leaving My orders

**Root cause.** `PickupCountdown` started `Timer.periodic` in `initState` and
discarded the returned `Timer`, so nothing could ever cancel it. After leaving
My orders the `State` was disposed, but the timer kept calling `setState`
every second. That asserts in debug builds, and in release it silently leaked
the timer, the `State` and its widget for the rest of the session.

**Fix.** Keep the `Timer` and cancel it in `dispose()`.

**Rejected alternative.** `if (mounted) setState(...)`. That hides the
assertion, but the timer and everything it references would keep leaking and
waking up once a second.

**Edge cases.** Once the window is open the widget still ticks every second.
That is harmless for a few order rows. For many rows a single shared ticker
would be better, the same design F-1 needs.

### RES-104 · Duplicate deals in the home feed

**Root cause.** `refreshDeals` and `loadMore` shared the `_page` counter, and
nothing ordered the two. If you pull to refresh while page 2 is still loading,
refresh resets `_page` to 1 and replaces the list. The old page-2 response
then gets appended to the fresh list while `_page` is still 1, so the next
`loadMore` asks for page 2 again. Reproduced in a test: the feed became
`[11, 12, 21, 22, 21, 22]`. A related bug: a `loadMore` that failed after a
refresh could decrement `_page` to 0.

**Fix.** A feed *generation* counter. Every refresh increments it, and a page
response that arrives under an older generation is dropped. `_page` only moves
forward when a page actually arrives (`nextPage` is committed on success), so
a failure needs no rollback. Refresh also releases the `loadMore` lock and
resets the footer (`refreshCompleted(resetFooterState: true)`), so paging
works again straight away.

**Rejected alternative.** De-duplicating by deal id when rendering. That hides
the symptom, but the paging state would still be wrong: pages would be
skipped or fetched twice.

**Edge cases.** *Not handled:* if `refreshDeals` itself throws, the error
propagates and the pull-to-refresh header is never reset. That bug already
existed and is outside this ticket. It would need a `try/catch` that calls
`refreshFailed()`.

### RES-103 · Requests pile up the longer you browse

**Root cause.** `DealDetailsController.onInit` subscribed to
`CartService.itemCount` with `ever(...)` and never cancelled the subscription.
The controller itself is scoped to the route (`lazyPut` in
`DealDetailsBinding`), and GetX *does* delete it on pop; the test confirms
`Get.isRegistered<DealDetailsController>()` is false afterwards. But
`CartService` is permanent, and a GetX `Worker` lives as long as the `Rx` it
listens to. So every deal page ever opened left a listener behind, and one
"Add to bag" fired a `GET /deals/:id` for each deal viewed in the session.
Each listener also kept its dead controller in memory.

**Fix.** Keep the `Worker` returned by `ever()` and `dispose()` it in
`onClose`.

**Rejected alternative.** Skipping the fetch when the page is not the current
route. The listeners and dead controllers would still pile up.

**Edge cases.** A re-check that is still in flight when the page closes
completes and writes to the dead controller's `Rx`. This is harmless, so I
did not add cancellation.

### RES-107 · Deep link opens to a crash

**Root cause.** The controller did `deal = Get.arguments as DealModel`. Taps
inside the app pass the loaded deal as `arguments`, but a deep link
(`rescu://open/deal?id=42&source=push`) only carries query parameters, so
`arguments` was `null` and the cast threw before the page could build.

**Fix.** The controller uses the passed `DealModel` when there is one.
Otherwise it parses `id` from `Get.parameters` (query parameters arrive as
`String`) and fetches `GET /deals/:id`. The deal is held in an `Rxn`; the
screen shows a spinner until it arrives and then renders the normal page.
Add to bag and the stock re-check both work for deep-linked deals. The
`deal_details_view` event now carries the real `deal_id` and `source: push`.

**Rejected alternative.** A fallback or error page. The link contains
everything needed to show the deal; it just has to be fetched (the ticket
also rules this out).

**Edge cases.**
- *Not handled:* if the fetch fails, or the link has a missing or
  non-numeric `id`, the error is logged and the page keeps showing the
  spinner. I deliberately added no error/fallback UI for this ticket. The
  simulated `GET /deals/:id` only fails for unknown ids, and deal 42 exists.
- **Cold start.** I tested the `adb shell am start …` repro on a device
  (Xiaomi Pad 5): the app launches straight onto a working deal 42 page, and
  Add to bag works. `/deal` is then the only route, so system Back leaves
  the app and returns the user to wherever they opened the link from. I
  kept this deliberately. I tried a synthetic back stack (Back → Home) and
  reverted it.

### RES-105 · Home feed is janky and memory keeps climbing

Three independent causes, one commit each.

**1. The whole screen rebuilt on every scroll pixel.** `HomeScreen` wrapped
its entire `Scaffold` in one `Obx` that read `scrollOffset`, and the scroll
listener wrote `scrollController.offset` into that `Rx` on every scroll event.
So every scroll frame rebuilt the app bar, `SmartRefresher`, the list
(re-filtering `visibleDeals` and allocating a `DealCard` for every loaded
deal) and every card on screen. The screen only needs two facts from the
offset: shadow on/off (> 4 px) and scroll-to-top visible (> 800 px). These are
now `RxBool`s in the controller, and `Rx` only notifies when the value
actually changes, so they fire when a threshold is crossed, not on every
pixel. The single `Obx` is split into three narrow ones (app bar, body, FAB).

**2. Every rebuild re-created the whole list.** The feed was
`ListView(children: [...])` with one `DealCard` per loaded deal. Flutter still
only *mounts* the cards near the viewport (I first assumed it built all of
them; a test showed 3 of 20 mounted), but every rebuild of the body allocated
a widget for every deal loaded so far, so the cost grew with scroll depth. The
feed is now a `CustomScrollView` with `SliverList.builder`.

**3. Images were decoded at full source size.** The API serves 1600×1200
photos, and `TheNetworkImage` decoded them at full size: ~7.7 MB of pixels per
image, whether shown as a 360×160 card or a 64×64 thumbnail. The default
`ImageCache` (100 MB) only holds ~13 of those, so scrolling keeps decoding
and evicting full-size bitmaps. `TheNetworkImage` now measures
its box and passes `memCacheWidth` *or* `memCacheHeight` × devicePixelRatio
(~2.9 MB for a feed card at 2.75×, ~0.17 MB for a thumbnail). It passes only
one dimension because `cached_network_image` resizes exactly to both, which
would distort the image. For `BoxFit.cover`, a wide box is matched on width
and a square or tall one on height.

**Rejected alternatives.** Changing `imageCache.maximumSize` (the cache size
was not the problem, the size of each entry was). Throttling the scroll
listener (it would still rebuild the whole screen, just less often).

**Evidence.**

From the widget test (`test/home_screen_test.dart`), 4 small scroll steps
with no new card entering the viewport:

| | Before | After |
|---|---|---|
| `DealCard` rebuilds | 12 (every mounted card, every step) | 0 |

On real devices, in profile mode. An integration test runs the same scripted
scroll on both builds: from the top of the feed to the end of the catalog
(122 deals, all 7 pages) in 1200 px steps at constant speed, about 73 s. It
records every frame's `FrameTiming` (the build and raster durations behind
DevTools' frame chart), the `ImageCache`, and process RSS. The harness is
not committed: it would add `integration_test` and `flutter_driver` as dev
dependencies, and I preferred to leave `pubspec.yaml` untouched.

*Samsung Galaxy S22+ (SM-S906E), Android 16, 120 Hz (8.3 ms frame budget),
1080 px wide, DPR 2.625.* Four runs in A-B-B-A order (`main`, branch,
branch, `main`) to cancel out drift. Before **every** run the script waited
until the phone reported thermal status 0 with a skin temperature below
37 °C. Every run started at 35.8–35.9 °C. Shown as `main` run 1 / run 4 and
branch run 2 / run 3:

| Metric | Before (`main`) | After |
|---|---|---|
| UI thread build time, p90 | 3.7 / 3.7 ms | 2.1 / 2.1 ms |
| UI thread build time, p99 | 5.5 / 4.9 ms | 3.4 / 3.3 ms |
| Raster time, p90 | 4.2 / 4.1 ms | 4.0 / 4.0 ms |
| Raster time, p99 | 6.2 / 7.4 ms | 4.9 / 5.0 ms |
| Janky frames (build or raster > 8.3 ms) | 46 / 64 (0.5% / 0.7%) | 6 / 10 (0.1% / 0.1%) |
| Frames rendered during the ~73 s scroll | 8,584 / 8,635 | 8,808 / 8,810 |
| Decoded size per cached image | 7.3 MB (95 MB / 13 images) | 2.6 MB (99 MB / 38 images) |
| Peak process RSS | 276 / 279 MB | 255 / 259 MB |

*Xiaomi Pad 5 (21051182G), Android 13, 120 Hz tablet, DPR 2.* Two runs per
build, back to back without cooling, so only the build-phase and image
numbers are reported (see the note on raster below):

| Metric | Before (`main`) | After |
|---|---|---|
| UI thread build time, p90 | 4.8 / 5.2 ms | 3.1 / 3.9 ms |
| UI thread build time, p99 | 8.1 / 8.6 ms | 5.6 / 7.2 ms |
| Frames whose build exceeded the 8.3 ms budget | 63 / 86 | 12 / 31 |
| Decoded size per cached image | 7.3 MB (95 MB / 13 images) | 5.1 MB (96 MB / 19 images) |

What this does and does not show:

- **Rebuild fix: confirmed.** UI thread build time dropped ~40% at p90 on
  both devices, in every run.
- **Jank: ~85% fewer janky frames.** On the cooled phone, janky frames went
  from 46–64 to 6–10 per scroll, and the after-build hit more vsyncs in the
  same time. Raster p99 also dropped (6.2–7.4 → 4.9–5.0 ms), consistent with
  uploading smaller image textures. The two fixes ship together on the
  branch, so this benchmark cannot split the gain between them. In absolute
  terms the S22+ is a flagship and both builds are smooth (< 1% janky). The
  mid-range device in the ticket would have far less headroom.
- **Image fix: confirmed on the phone.** On the S22+ each decoded image is
  2.8× smaller, matching the ~995×746 px decode the card needs, so the same
  cache holds 38 images instead of 13 and scrolling back re-decodes far
  less. Peak RSS dropped by ~20 MB. On the tablet the feed cards are
  ~2,500 px wide, *larger* than the 1,600 px source, and the resize never
  upscales, so only the flash-rail images shrink there. The fix is working
  as designed; the tablet simply displays the images at more than their
  source resolution.
- **"Memory keeps climbing until the OS kills the app": not reproduced.** On
  both builds and both devices the `ImageCache` stopped at its 100 MB byte
  cap and RSS did not grow with scroll distance. The unbounded growth in the
  ticket probably needs a lower-RAM device than I had. I did not find a
  source of unbounded growth in the feed code itself.
- **A measurement trap worth recording.** My first S22+ runs (not used
  above) were taken while the phone sat on a wireless charger. Janky frames
  swung from 2% to 72% between runs *of the same build*, and the phone
  reported thermal status 3 (severe) afterwards. Those raster numbers
  measured heat, not code. Once the phone was off the charger and cooled to
  status 0 before each run, raster time was stable at ~4 ms p90 on both
  builds. The tablet runs were not temperature-controlled, which is why
  their raster numbers are left out.

**Edge cases.** Choosing which dimension to decode by assumes landscape
photos. A portrait image in a square thumbnail would be slightly soft.

---

## AI usage log

**Tools.** I used Claude Code (in VS Code) to read the codebase against each
ticket, write the reproduction tests, draft fixes and commit messages, and
review the diffs. I used my own written analysis of the tickets (hypotheses
before seeing the code) as the starting point and checked each hypothesis
against the code and a failing test before changing anything.

**Where the AI (or the hypothesis it built on) was wrong:**

1. **RES-103: wrong root cause.** The initial theory was that the deal
   controller was registered as permanent or not tied to the route. A test
   showed GetX *does* delete the controller on pop
   (`isRegistered == false`) while the requests still piled up. The real
   leak was the `ever()` worker on the permanent `CartService`. Fixing the
   registration would have changed nothing.
2. **RES-105: "the list is not lazy".** The AI listed a non-lazy list as a
   cause of the memory growth. Counting mounted cards in a widget test showed
   only 3 of 20 were built: `ListView(children:)` still mounts lazily. The
   real cost was allocating every card widget on each rebuild, which is a
   much smaller problem. I kept the builder change but described it
   accurately, and moved the memory explanation to image decode size.
3. **RES-105: "cards are remounted on every scroll tick".** Based on
   `debugOnRebuildDirtyWidget` reporting `builtOnce == false`, the AI claimed
   the cards were being torn down and remounted. Checking element identity
   before and after scrolling showed the same elements, so they were rebuilt,
   not remounted, and the flag could not be trusted for this. The test now
   counts builds over scroll steps where no new card enters the viewport.
4. **RES-101: a test that tested nothing.** The first "clearing the box drops
   in-flight results" test used the query `bakery`, whose response arrives
   *before* the box is cleared, so it passed on the buggy code too. Running
   every new test against the pre-fix code caught it; I switched it to a slow
   one-letter query.
5. **RES-105: measuring memory with the profiler running.** The first
   device measurement used `traceAction` with `--endless-trace-buffer`. That
   buffer lives in the app's own memory, so RSS "grew" to 1.7 GB, which
   would have looked like proof of the leak. It was the trace. The final
   numbers come from in-app `FrameTiming` collection with no trace buffer.
   Even then, the raster numbers turned out to track device temperature
   (the phone was on a wireless charger). Rather than picking the run that
   looked best, I reran A-B-B-A with a cool-down to thermal status 0 before
   each run; those are the numbers reported.

---

## Design questions

**Q1 — `GetxController` lifecycle vs widget `State` lifecycle.**
A `State` lives exactly as long as its element in the tree: `initState` when
it is mounted, `dispose` when it is removed. Anything it starts (timers,
subscriptions) must be stopped in `dispose`. A `GetxController` here is tied
to a *route*, not a widget: the binding registers it lazily, it is created on
the first `Get.find`, gets `onInit`/`onReady`, and gets `onClose` when GetX
removes the route. It survives rebuilds, and the `GetView` showing it has no
`dispose` at all, so whatever the controller owns must be released in
`onClose`. That includes subscriptions to objects that outlive it, which
neither GetX nor Dart's GC releases for you. RES-103 is exactly this: the
controller was cleaned up with its route, but the `ever()` worker it created
on the session-long `CartService` was not. RES-102 is the same mistake on the
`State` side: a timer started in `initState` with no `dispose`.

**Q2 — When does a single big `Obx` hurt?**
An `Obx` rebuilds its *whole* builder whenever *any* `Rx` it read changes. It
hurts when the subtree is large and at least one of those values changes
often. RES-105 is the extreme case: a value written at scroll frequency
(60–120 Hz) read at the root of the screen. It also hurts more subtly when
unrelated state shares one builder, so a filter chip toggle rebuilds the app
bar. I decide the scope by *how often the value changes × how much it
rebuilds*. Put the `Obx` around the smallest widget that actually displays the
value. Do not expose high-frequency values when the UI only needs a coarse
fact: derive it in the controller (`offset > 800` → `RxBool`), because `Rx`
does not notify when the value is set to the same thing. Values that change
rarely (`isLoading`, a newly loaded page) can afford a wider scope. The same
rule is why F-1's per-second countdown has to live in a `Text`-sized `Obx`,
not around the card.

**Q3 — A test that would have caught RES-106.**
`test/pickup_window_model_test.dart` builds the expected values from *local*
wall-clock times (`DateTime(2026, 10, 8, 6, 0)`), converts them to the UTC
string the API would send, parses, and asserts `label == '06:00 – 09:30'` and
the "today" result. The trap is that CI machines usually run in UTC, where the
buggy code *passes* because UTC equals local. So the test alone is not enough.
The suite should also run under a non-UTC timezone, e.g. a CI step with
`TZ=Asia/Bangkok fvm flutter test` (the Dart VM reads `TZ` on Linux and
macOS). The code change that made it testable was removing the hidden
`DateTime.now()` from the "today" check: `startsOnSameDayAs(moment)` takes the
reference time, so the test can pin "now" to 00:05 or 23:55 without touching
the clock. A further step would be injecting a clock or market timezone into
the controller that applies the filter.

---

## Time spent and what's next

**Time spent:** TODO: roughly __ hours (honest total, including reading and
testing).

**With one more day:**
1. **F-1 (live countdowns)**: one shared 1-second ticker in a service. Each
   card's countdown text listens to it through its own `Obx`, so only that
   `Text` rebuilds. Expiry logic (disable the card, remove the deal from the
   bag with a notice) lives in the service, so it also works for cards that
   are off screen.
2. Reproduce RES-105's memory growth on a low-RAM device. I could not make
   it happen on the devices I had, so the memory explanation is unproven.
3. Fix the `refreshDeals` error path (pull-to-refresh header stuck on failure).
4. Handle a failed RES-107 fetch or a malformed link (missing or
   non-numeric `id`) instead of leaving the spinner up.
5. Then F-2, then F-3.
