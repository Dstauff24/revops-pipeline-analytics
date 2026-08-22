# Building the data: four rounds of finding out I was wrong

The generator in `data/generate.py` did not work the first time.
It ran, it produced 2,500 opportunities, and every number it
produced was wrong in a way that was not obvious from the fact
that the script exited zero.

This is the log of the four rounds it took to fix, written up
because the fixing is the part worth reading. Writing a query is
the easy half. Looking at the output, deciding it is wrong, and
working out why is the half that takes judgment, and it is the
half that never shows up in a finished repo.

**A note on reproducing these.** The before numbers below came
from intermediate builds that no longer exist: the generator
changed, and because the random draws shift when the code shifts,
you cannot get them back by rewinding the seed. Each round names
the exact constants that moved, so you can revert them in
`generate.py` and watch the same failure reappear. That is the
only honest way to present a before number I cannot regenerate on
demand.

---

## Round 1: a 9.6 percent win rate

**Problem.** The first full build produced 222 closed won deals
against 2,093 closed lost. A 9.6 percent win rate. Open pipeline
was 233 deals. Both numbers are wrong for B2B: real teams run 15
to 30 percent on opportunities, and a 24 month window ending at
the as of date should leave several hundred deals live.

The trap was that nothing looked broken. Every source was ordered
correctly (Referral 27.3 percent, Inbound 15.9, Outbound 4.4).
The seasonality curve was visible. The ramp curve was visible.
Each individual behavior I had built was present and pointing the
right way. Only the level was wrong.

**Diagnosis.** Compounding gates. I had set each stage transition
to a probability that looked reasonable on its own:

```
Prospecting -> Discovery   0.74
Discovery   -> Proposal    0.63
Proposal    -> Negotiation 0.60
win at Negotiation         0.44 (before quality adjustment)
```

Every one of those is defensible in isolation. Multiplied, they
are not: 0.74 x 0.63 x 0.60 = 0.280 reach Negotiation, and the
quality multiplier pulled the 0.44 down to roughly 0.35, which
gives 0.280 x 0.35 = 9.8 percent. The observed 9.6 percent
matched the arithmetic almost exactly, which is what confirmed
the diagnosis rather than merely suggesting it.

I had reasoned about four numbers one at a time and never
multiplied them together. That is the whole error.

**Fix.** Raised the gates to 0.86 / 0.78 / 0.74 (product 0.496)
and `BASE_WIN_P` from 0.44 to 0.52. Two related changes went in at
the same time: a growth trend on lead volume, `1.0 + 0.50 *
progress` across the window, because a flat run rate leaves too
little live pipeline at the end; and the summer slowdown deepened
from 0.85 / 0.82 to 0.78 / 0.74 for July and August so seasonality
would still be visible once the noise floor came down.

**Result.** Win rate 19.7 percent. 348 open deals worth 31.1
million dollars, which is enough for the coverage query to
produce ratios in the 1.1x to 2.7x range instead of nonsense. The
funnel now reads 77.2 / 70.1 / 68.1 / 45.3, which is the shape
finding 1 in `ANALYSIS.md` is built on. Commit category
conversion moved from 34.9 percent, which is not a forecast
process anyone would recognize, to 56.6, which is a forecast
process with a real problem.

---

## Round 2: the Q3 ramp penalty was invisible

**Problem.** I had deliberately built a slower ramp for reps
hired in Q3. When I ran query 02 against the fixed data, Q3 came
out at 26.4 percent attainment at months seven to twelve against
Q1 at 18.7 and Q2 at 14.6. The cohort I had penalized was
outperforming. The planted effect was not merely missing, it had
the wrong sign.

**Diagnosis.** Two separate faults, and I found the wrong one
first.

The measurement was broken before the data was. My first version
of query 02 divided won revenue by rep headcount per tenure band.
But the bands were `01-03`, `04-06`, `07-12` and `13+`, and that
last band is open ended: it was collecting up to two years of
revenue and being compared against a three month band. Every ramp
curve looked flat because the denominator was wrong. Fixing that
meant switching to rep months and prorated quota, so a cohort's
production is measured against the quota it was actually carrying
for those months. That also removed the segment mix problem,
since an enterprise cohort and an SMB cohort could finally be
compared.

With the metric fixed, the real fault showed. I had implemented
the penalty as widening the gap to full productivity by 40
percent, but it still expired at month six. Median won cycle in
this data is 103 days for Mid-Market and 169 for Enterprise. A
deal a rep sources in month five closes in month eight or nine,
by which point the penalty is over and the revenue lands in a
band where the cohort is already running at full speed. The
penalty was real, it was just structurally unable to reach any
band where I was measuring revenue.

Cohort sizes made it worse: 5, 4, 6 and 2 reps, with individual
skill drawn at sigma 0.19. One good rep in a two rep cohort was
louder than the effect.

**Fix.** Reimplemented the penalty as a speed multiplier on
tenure itself, `m = m * 0.55`, so Q3 hires reach full productivity
around month ten rather than month six and the penalty is still
live when their first deals close. Rebalanced hire dates to
exactly five reps per hire quarter. Narrowed skill sigma from 0.19
to 0.14 so the cohort effect could clear the individual variance.

**Result.** Q3 is now lowest in every early band on the leading
indicator: 1.27 opportunities created per rep month at months one
to three against 1.80, 1.67 and 2.21 for the other cohorts, and
2.15 at months four to six against 3.07, 2.60 and 5.00. On
attainment it is the only cohort still at zero at months four to
six and the lowest at 15.8 percent through month twelve. It goes
into `ANALYSIS.md` with an explicit five reps per cohort caveat,
because that is what five reps per cohort is worth.

---

## Round 3: referral returning 2,055x

**Problem.** Query 03 came back with revenue per marketing dollar
of 2,055.89 for Referral, 236.52 for Inbound, 51.49 for Outbound,
33.85 for Event and 9.86 for Paid. Every channel wildly
profitable and one of them returning two thousand times its cost.

**Diagnosis.** This one is a magnitude tell, not a logic tell.
There is no bug in a ratio that produces 2,055; a join error or a
double count gets you 2x or 10x, not three orders of magnitude.
When a ratio is that far out, the numerator and denominator are
on different scales, and the only question is which one I set
carelessly.

It was the denominator. I had written cost per lead as 12 dollars
for Referral, 48 for Inbound, 190 for Event, 240 for Paid and 34
for Outbound. Those are consumer marketing numbers. The deals
were averaging 70,000 dollars. Referral alone works out to 0.84
lead to opportunity times roughly 0.56 win rate times 71,000
dollars, which is about 33,000 dollars of revenue per lead
against a 12 dollar cost.

The second error was conceptual and worse. Pricing referral at
almost nothing encodes the assumption that referrals are free.
They are not. Referral programs cost partner commissions and
customer incentives, and treating that as zero is exactly the
mistake that produces a strategy memo recommending a company move
its entire budget into a channel it cannot buy.

No amount of SQL fixes either problem. The data was wrong.

**Fix.** Repriced cost per lead to Referral 800 (partner
commission), Inbound 400, Outbound 650 (loaded SDR cost), Event
2,100, Paid 2,600. One useful property: cost is drawn from a
lognormal, and changing the median changes the value without
changing the number of random draws, so the rest of the dataset
was left byte for byte identical. Only the cost column moved.

**Result.** Referral 30.89x, Inbound 28.28x, Event 2.96x,
Outbound 2.38x, Paid 0.92x. Blended, 25.4 million dollars of
revenue on 5.5 million of spend. Cost per win runs 2,154 dollars
for Referral against 55,161 for Paid.

Paid below 1.0 is the outcome that made the query worth having.
A channel returning 92 cents on the dollar is a finding with a
decision attached to it, which is what the query header promised
and what the earlier version could not have produced, since
everything was profitable. The repricing also turned Referral
versus Inbound into a near tie on raw return, 30.89 against
28.28, that only separates on the cycle adjusted column, 37.57
against 28.76. That is the column the header exists to justify.

---

## Round 4: a fake inverted-U in query 09

**Problem.** Query 09 bucketed deals into quintiles by activity
per week and reported win rate. The result rose and then fell off
a cliff:

```
Enterprise   14.3  18.2  30.9  18.2   0.0
Mid-Market   15.2  26.8  27.0  25.7   4.3
SMB          14.0  24.5  31.8  27.3   4.9
```

Read naively that is a real and interesting finding: there is an
optimum, and past it, hammering a deal kills it. It is a story
that sounds true, which is what made it dangerous.

**Diagnosis.** The shape was the tell before the mechanism was.
Monotonic and then a collapse to near zero in the top bucket, in
all three segments, is not how a behavioral relationship
degrades. It is how a denominator artifact looks.

The confirming detail was in the quintile boundaries. The top
quintile ceilings were 32.67, 56.0 and 70.0 touches per week. No
rep works a deal 70 times in a week. Those are not intensely
worked deals, they are deals with a tiny denominator.

`activities_per_week` was `total_activities / (deal_age_days /
7.0)`. A deal that died in nine days with four touches scores 3.1
per week. A deal worked steadily for eight months scores lower.
Quintile 5 was not measuring effort at all, it was collecting
deals that died fast, and deals that die fast lose by
construction. Normalizing per week does not remove the deal
length bias that counting lifetime activity has, it inverts it.

**Fix.** Replaced the rate with a fixed window: count only
activity in the deal's first 30 days, and restrict the population
to deals that lived at least 30 days, so every deal in the set
had the same opportunity to be worked and the same window in
which to be counted.

**Result.** Mid-Market runs 19.4 to 41.5 percent across the
quintiles, SMB 20.2 to 58.0. Both climb monotonically. Enterprise
climbs from 11.4 to 29.5 and then turns back down to 18.2 in the
top quintile, which I have left in the output rather than
smoothed away: at 44 deals per quintile that is 13 wins against
8, and it is not a large enough difference to claim either an
optimum or a clean line.

The part I would actually talk about in an interview is the
column I added rather than the one I fixed. `median_deal_age_days`
falls from 179 to 61 in Enterprise and 123 to 53 in Mid-Market as
intensity rises. Heavily worked deals also close faster, which
means buyer engagement is sitting behind both variables and I
cannot separate it from rep effort with this data. The fixed
window removed one confound. It did not remove that one. So the
query prints it as a column and the caveat block says out loud
that the causation plausibly runs backwards.

Dropping that column would have made the finding look stronger.
It would also have made it a chart instead of an analysis.

---

## What generalizes

Four rounds, four different tells:

- **Round 1 was an arithmetic tell.** Each input was defensible
  and the product was not. Multiply your assumptions together
  before you trust them individually.
- **Round 2 was a sign tell.** I planted an effect and the
  measurement returned the opposite. When something you know is
  there does not show up, suspect the measurement before the
  mechanism, and check the denominator first.
- **Round 3 was a magnitude tell.** A ratio three orders of
  magnitude off is never a logic error, it is two quantities on
  different scales.
- **Round 4 was a shape tell.** Monotonic then collapse is a
  denominator artifact until proven otherwise, and the bucket
  boundaries usually say so if you print them.

The common thread is that none of these were caught by the code
failing. Every one of these builds ran clean and produced a
plausible looking table. They were caught by knowing roughly what
the number should have been before running the query, which is
the only reliable defense against output that is confidently
wrong.
