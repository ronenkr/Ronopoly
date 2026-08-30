# Ronopoly

A complete Monopoly game — London board, in pounds — written entirely in
**Windows PowerShell 5.1 calling into .NET**. No `dotnet build`, no compiled
project, no dependencies to install. A `.cmd`, a folder of `.ps1` files, and a
WPF window.

Hot-seat, solo against bots, or over a LAN. Auctions, trading, mortgages,
houses and hotels, the full Chance and Community Chest decks, bankruptcy
cascades, and a settings screen for the house rules everyone argues about.

```
.\Ronopoly.cmd
```

---

## Running it

| What | Command |
|---|---|
| Play | `.\Ronopoly.cmd` |
| Light theme, no animations | `.\Ronopoly.cmd -Theme Light -Fast` |
| Silence | `.\Ronopoly.cmd -Mute` |
| Host a LAN game | `.\Ronopoly.cmd -Mode Host` |
| Join one | `.\Ronopoly.cmd -Mode Join -HostAddress 192.168.1.42 -Name Ada` |
| Two clients on one machine | `.\Ronopoly.cmd -Mode Host -LoopbackOnly` then `-Mode Join -HostAddress 127.0.0.1` |

The launcher passes `-ExecutionPolicy Bypass -STA -NoProfile`. **Bypass**
because this machine's LocalMachine policy is `Restricted`, which blocks `.ps1`
files outright; **STA** because WPF cannot create a window on an MTA thread
(`Start-Ronopoly.ps1` relaunches itself if you start it in one anyway).

**In game:** click any property to read its title deed. `Space` takes the
obvious action — roll, or end the turn. `Esc` closes a panel. **Save / load**
keeps a game on disk *including the dice stream*, so a reloaded game plays out
exactly as it would have. **Sound** mutes. Closing the window asks first, and
offers to save the position on the way out.

A panel you opened yourself — composing a trade, answering the close prompt —
holds the game still while it is up: the bots stop, and the phase cannot
replace the panel underneath you. Composing an offer against a board that is
still moving is not a decision, it is a race. In a LAN game the *host* keeps
playing, naturally — you cannot freeze other people's table — so an offer
composed slowly there can come back rejected as stale.

Sound effects are **synthesised**, not shipped: filtered noise and summed
partials, worked out in PowerShell and cached as `.wav` beside the artwork. The
**Sound** button cycles full, quiet and off.

### Requirements

Windows PowerShell 5.1 and .NET Framework 4.8, both of which ship with Windows.
PowerShell 7 is *not* required and is not used. Nothing to install.

---

## Rules

Official rules by default, including the ones clones usually skip:

- **Auctions.** Decline a property and it goes under the hammer, opening with
  the player to your left. If everybody passes without bidding, it simply stays
  with the bank.
- **The building shortage.** 32 houses and 12 hotels, and no more. Building a
  hotel *returns four houses to the bank*, and when the bank is short you
  cannot break a hotel back down.
- **Even build.** You may only add to a site at the group's minimum, and only
  sell from one at its maximum.
- **Raising money is legal whenever it is your turn**, including while a deed
  you have just landed on is still on the table. Land on a £320 site holding
  £140 and you can mortgage, sell buildings or trade your way to the price and
  still buy it — the Buy button sits there greyed out with the shortfall on it
  rather than vanishing. Clones that leave this out quietly turn "short of
  cash" into "forced to auction", which is not what the rules say.
- **Trades and counter-offers.** Deeds, cash and Get Out Of Jail Free cards,
  in any combination, both ways at once. An offer can be *countered* rather
  than merely accepted or refused: the answering player gets the deal opened in
  front of them, reversed, and edits it. The turn does not move while an offer
  is on the table, so haggling costs nobody a roll — but one negotiation may
  only cross the table six times, which is enough for a deal and not enough for
  a stalemate.
- **Mortgages.** Half the price to raise, plus 10% interest to redeem. A
  mortgaged deed received in a trade or a bankruptcy charges the *receiver* that
  interest immediately — which can bankrupt them in turn, and the cascade is
  handled.
- **Bankrupt to the bank** auctions the estate to the survivors.
- **Jail.** Pay £50, use a card, or roll for doubles; on the third failure the
  fine is compulsory and you then move the amount rolled. Doubles that free you
  do **not** earn another roll.
- **The card rules everyone gets wrong.** "Advance to the nearest station" pays
  *double* the normal station rent. "Advance to the nearest utility" makes you
  *throw again and pay ten times the roll* — even when the owner holds only one.

House rules live behind the **House rules** button, all off by default: Free
Parking jackpot, no auctions, unlimited buildings, double salary on exact Go, no
rent while jailed, snake-eyes bonus, interest-free mortgages, bidding beyond
your cash, and a turn limit.

---

## The AI

Four difficulties. Every decision reduces to one question — *what is this deed
worth to me, right now, in pounds* — and buying, bidding, building, mortgaging
and trading are all comparisons against that number.

The valuation weights groups by **landing frequency and payback period, not
price**: the orange and red sets sit one or two rolls past Jail, the busiest
region of the board, and comfortably out-earn the dark blues.

|  | Buy threshold | Aggression | Cash reserve | Trades | Denial bids | Mistakes |
|---|---|---|---|---|---|---|
| Easy | 1.15 | 0.60 | 0.4 | accepts | no | 15% |
| Normal | 1.00 | 0.85 | 0.8 | accepts | no | 5% |
| Hard | 0.85 | 1.05 | 1.0 | proposes | no | — |
| Expert | 0.75 | 1.25 | 1.2 | proposes | yes | — |

Difficulty is a *parameter table*, not a set of code paths — there is one
implementation of each decision. Easy's `MistakeRate` makes it occasionally play
a random legal move instead of the best one, which feels far more human than a
bot that is merely bad at arithmetic.

Bots haggle rather than just refusing. Handed a deal they do not like, Hard
and Expert work out whether a price exists that suits both sides — using the
same valuation from the *opponent's* seat — and counter with that number
instead of saying no. The shape of the deal is left alone and only the cash
moves, because the proposer already searched for the swap it wanted; re-opening
that search just produces a different deal it will also refuse.

Bots build to three houses across a group before pushing any site to four,
because the third house is the sharpest rent jump on the board. They stay in
jail late in the game, when it is the safest square there is, and get out early,
when the board is still worth walking. Expert bids up a lot that would complete
an *opponent's* monopoly, stopping just below the point where winning it would
hurt.

---

## LAN play

The host runs the game; clients send requests and render what comes back. A
client never decides legality — it asks, and the host answers using the *same*
`Test-RonActionLegal` that hot-seat uses. There is one rules implementation in
the project.

The wire format is a 4-byte length prefix plus UTF-8 JSON. The host sends the
full authoritative state alongside every event batch rather than having clients
replay events into a local replica; a snapshot is ~20 KB and ~2 ms to build,
which is nothing on a LAN, and it removes the largest correctness risk in the
whole layer — a replay path that has to mirror the rules exactly and desyncs
silently when it does not.

**Firewall.** The first time the game listens on a real network interface,
Windows Defender will ask about `powershell.exe`. Allow it. If the prompt was
dismissed, `Tools\Add-FirewallRule.ps1` (run as administrator) adds the rule
permanently. `-LoopbackOnly` never triggers it, which is what makes testing
several clients on one machine painless.

If a player drops, their seat is held for a grace period and then handed to the
AI, so the game continues instead of stalling. Reconnecting reclaims it.

---

## Layout

```
Ronopoly.cmd            launcher
Start-Ronopoly.ps1      entry point, STA self-check
src/
  Bootstrap.ps1         the ordered dot-source loader
  Core/                 classes, JSON discipline, logging
  Data/                 board, cards, rules, tokens, strings  (.psd1, data only)
  Engine/               the rules. No WPF, no ambient state
  AI/                   valuation, profiles, decisions, trades
  Net/                  inline C# sockets, protocol, session
  UI/                   art, sound, board, tokens, dice, HUD, overlays, controller
Assets/                 pre-rendered PNGs and WAVs + manifest (a cache; see below)
Tools/                  asset builder, simulator, test runner, firewall helper
Tests/                  the suite
```

### Three decisions worth knowing about

**Everything is dot-sourced, never a module.** A PowerShell 5.1 class defined
inside a `.psm1` is not reachable as a type literal from outside it —
`[GameState]` fails with *"Unable to find type"* even after a successful
`Import-Module`. Dot-sourcing works. All classes live in one file,
`src/Core/Types.ps1`, in dependency order.

**There is no game loop.** The engine exposes three functions —
`Get-RonLegalActions`, `Test-RonActionLegal`, `Invoke-RonAction` — over an
explicit `GameState`, and returns an event list. A human click, an AI timer tick
and an inbound network frame are three sources of the same action object, which
is why hot-seat, solo and LAN are one code path rather than three. All three
*enqueue*; a single pump drains one at a time behind an in-flight flag, so
double-clicks and laggy bursts are harmless.

**Implicit styles do not reach a panel built before it is attached.** WPF
resolves an element's implicit style — the one keyed by its type — at the
moment it is added to its parent. Every overlay here builds its whole subtree
detached and attaches the finished card at the end, so that lookup runs while
the subtree can still see no resources, and the answer is never revisited. The
theme's `TextBlock` style was silently skipped for every label in every panel,
which left them at the WPF default: black text, on a dark grey card. The fix is
not to style each label but to set `Foreground`, `FontFamily` and `FontSize` on
the *window*: those are inherited properties, and inheritance **is**
re-evaluated when the tree changes, so the readable value flows down to
whatever the styles miss, whenever it is finally attached.

**No PowerShell ever runs off the UI thread.** Only compiled C# touches a
background thread, and it touches nothing but a `ConcurrentQueue`; the UI
*polls* it from a `DispatcherTimer`. This deletes rather than works around the
hardest problem in PowerShell + WPF work: a scriptblock handed to
`Dispatcher.Invoke` from another runspace carries that runspace's session state
and fails intermittently with *"There is no Runspace available to run scripts in
this thread"*.

### Who owns what

The trade panels put each player's name on their own token colour — the chip
you pick to trade with, and the heading over each column of deeds. Which pile
belongs to whom is the thing a trade panel is *about*, and a name in the same
grey as everything else sends you back to the board to work it out.

The text colour on those chips is measured, not guessed. A lightness threshold
picked by eye put white on the blue token, where it manages only 4.2:1 — under
the 4.5:1 that counts as readable — while black clears it at 5.0:1. The ink is
now chosen by computing the actual WCAG contrast ratio, and a test asserts
every token colour clears the bar, which is how that was found in the first
place.

### The sound

There is no audio to ship. Every effect is arithmetic — noise through a
resonant filter for anything struck, summed partials for anything that rings —
and two rules account for most of the difference between a sound effect and a
beep:

**Never start or stop a waveform abruptly.** A sample stepping from silence to
full amplitude in one go *is* a click, and it is louder than the sound it
introduces. Every voice gets a few milliseconds of raised-cosine attack, and
every finished effect is faded to true zero at both ends — measurably, in
`Sound.Tests.ps1`, because audio is the one part of this project that cannot be
checked by looking at it.

**Nothing real is a bare sine or a bare square.** A die landing is a noise
burst through a resonant filter, twice — a bright tick for the corner striking
and a lower one for the body — five times over, with the gaps *shortening* as
it settles. That deceleration is most of what makes a series of ticks read as a
die rather than a drum roll. A cell door is three inharmonic partials at
roughly the ratios of a struck bar, the high ones dying first, because a bell
whose partials decay together sounds like an organ.

Each effect is normalised to a chosen level rather than trusting its gains,
which makes clipping structurally impossible and means one sound can be
redesigned without re-checking the volume of every other. Levels are set by
average loudness, not peak: a sustained tone at the same peak as a transient is
far louder to the ear.

Synthesising the set takes about a second and a half, which is fine once and
much too slow every launch, so it caches to `Assets\sounds` on exactly the same
terms as the PNGs — with a version stamp, so a redesigned effect is rebuilt
rather than played in its old form forever. From cache, audio startup is ~60 ms.

Playback goes through WPF `MediaPlayer`. `SoundPlayer` wraps the Win32
`PlaySound` API, which has exactly **one** asynchronous voice: the second sound
to start cuts the first one off, so rolling the dice and landing on rent was
two truncated sounds rather than two sounds. It stays as the fallback for a
machine with no media stack, where it is still better than silence.

### The artwork

`src/UI/Art.ps1` is dot-sourced by *both* the asset builder and the running
game. The builder calls `Draw-Tile` and saves a PNG; at runtime the loader
returns that PNG, or — if it is missing, stale, or the whole `Assets` folder has
been deleted — calls the *same* routine and draws it live. The PNGs are a pure
cache. Delete them and the game looks identical, just slower to first paint.

```powershell
.\Tools\Build-Assets.ps1            # ~94 assets, about 2 seconds
.\Tools\Build-Assets.ps1 -Force     # after changing the art
```

The title deed is drawn half again the size it used to be — it is the one
place in the game where a player sits and reads a rent table. The panel is
sized from the card rather than the other way round, and the wanted size is a
ceiling rather than a promise: a fixed height that looks right on a 1010-tall
window clips its own Close button on the 760-tall minimum, so the card shrinks
to whatever the window can actually show. The pre-rendered PNGs are @2x, so
the bigger card is still sampled down rather than up.

Tile names size themselves. Wrapping at a space is how a real board prints
NORTHUMB AVE, so that is left alone; a single word snapping in half is not, so
the longest *word* is measured and the type shrinks only far enough to fit it.
Every name that already fits keeps the full size, which is why MARLBOROUGH is a
point smaller than its neighbours and nothing else is.

---

## Testing

```powershell
.\Tools\Run-Tests.ps1                                    # the whole suite
.\Tools\Run-Tests.ps1 -Filter Bankruptcy                 # one file
.\Tools\Invoke-Simulation.ps1 -Games 200 -AssertInvariants
.\Tools\Invoke-Simulation.ps1 -Games 50 -RandomBots -MaxTurns 100 -AssertInvariants
```

The runner spawns **a fresh PowerShell process per test file**. This is not
optional: a PowerShell 5.1 class cannot be redefined in a live session, so a
long-lived test host silently keeps running the *old* definition of every class
after an edit — and reports green while doing it.

`UiSmoke.Tests.ps1` opens the real window, runs a real dispatcher loop with real
timers, and then asserts on what actually *happened*: turns played, and zero
errors logged. "Does it launch?" is not a test — an exception inside a
`DispatcherTimer` tick is swallowed, so the game silently stops moving and the
process still exits 0. Every timer handler now runs through `Invoke-RonGuarded`,
which logs and counts the failure and shows it to the player instead.

`UiSmoke.Tests.ps1` also drives the window by *clicking* it. `Start-RonApp`
takes an `-OnReady` scriptblock that runs once on the UI thread after the
window opens — the only way into a live window, since `ShowDialog` does not
return until it closes — and the close-prompt test uses it to press the X,
check that the close was cancelled and the prompt appeared, then find the Quit
button in the visual tree and click it.

`Seeds.Tests.ps1` exists because the rest of the suite used small hand-picked
seeds, while `New-RonGame` picks one anywhere up to 2^31. Deriving a per-seat AI
seed as `seed * 31 + playerId` is fine for 42 and overflows Int32 for anything
above ~69 million — PowerShell silently widens the product to a double rather
than wrapping, and it surfaced much later as a failed cast. `Get-RonSeedMix`
folds any number of values into a valid Int32, and every derived seed uses it.

The simulator plays complete AI-vs-AI games with no UI, and reports any failure
*with its seed*, so a crash 800 turns deep is exactly reproducible. `-RandomBots`
replaces the AI with uniformly random legal moves; it has no strategy at all,
which is precisely why it walks into rule paths a competent bot avoids.

Under `-AssertInvariants` the engine checks, after **every event**: that the
total money in the game changed only through the Go salary, cards and taxes;
that houses on the board plus houses in the bank still equal 32; that exactly
two Get Out of Jail Free cards exist somewhere. That first check alone catches
most rules bugs — double payments, missed debits, phantom money in a bankruptcy
transfer — without anyone having had to predict them.
