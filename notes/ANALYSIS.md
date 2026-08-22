# What the data says

Notes from running the fourteen queries. The data is synthetic
(see `data/README.md`), so the numbers are not the point. What I
would do on Monday if a real CRM handed me these is the point.

---

## 1. This is not a prospecting problem. Half the pipeline dies in the last stage.

Query 01: 77.2 percent of opportunities reach Discovery, 70.1
percent of those reach Proposal, 68.1 percent of those reach
Negotiation. Then it falls off a cliff. Only 45.3 percent of
deals that reach Negotiation close won, which is 514 deals lost
at the final step, more than at any other step, and the most
expensive losses in the set because the full cycle was already
spent on them.

Query 08 says it from the time side: Negotiation runs a 34 day
median and an 81 day p90, and accounts for 37.8 percent of the
median cycle by itself.

So the team is generating pipeline and getting meetings. It is
losing qualified late stage deals slowly, which is a pricing,
procurement or competitive problem, and none of the three gets
fixed by more activity or another discovery training.

I would put an entry gate on Negotiation instead of an exit gate:
nothing enters without an identified economic buyer, a known
procurement path and a named competitor. Then a hard 45 day clock
at roughly the p75, forcing signed or Closed Lost. A 34 day
median with an 81 day tail says much of that stage is not
negotiating, it is waiting.

Separately, 77.2 percent clearing the first gate is too high. A
step that passes three quarters of what enters it is not
qualifying anything, and some of those Negotiation losses were
bad deals that should have died in month one.

## 2. Paid does not pay for itself, and the two channels that work are starved.

Query 03 is the one I would take to a budget meeting. Paid
consumed 2.37 million of the 5.5 million spent and returned 2.18
million in closed revenue. That is 92 cents on the dollar. It is
not underperforming, it is losing money, and it has been for two
years.

Referral returned 30.89 dollars per dollar and Inbound 28.28.
Together they took 10.1 percent of spend and produced 16.3
million, which is 64 percent of all closed revenue. Cost per win:
2,154 for Referral, 2,220 for Inbound, 55,161 for Paid.

Weighting for cycle length widened the gap instead of closing it,
which I did not expect. Referral also closes fastest, 74 days
against 115 for Paid, so per dollar per quarter of capital tied
up it goes to 37.57 against 0.72.

The obvious move is still wrong. You cannot shift the Paid budget
into Referral, because Referral is not a channel you can buy: 249
leads in 24 months, supply constrained by definition. So cap Paid
at brand defense and take the rest to zero, move that money into
Inbound, which has headroom at a 78.4 percent lead to opportunity
rate, and spend a slice standing up a formal referral program so
the scarce channel stops being an accident.

Before anyone acts: cost is allocated single touch at the lead.
Directional for a budget shift, not an attribution model.

## 3. Commit means ninety percent and delivers fifty-eight.

Query 05. Deals sitting in Commit at close converted at 56.6
percent against the roughly 90 percent the category is understood
to promise. On 33.9 million of Commit pipeline that is a 14.4
million dollar variance, and won deals landed an average of 41
days after the date the rep entered.

The tenure split is the useful part. Reps under a year converted
Commit at 41.2 percent; reps at one to two years hit 64.7. The
newest sellers are not only producing less, they are the least
reliable input into the number, and they are the ones a manager
is least likely to challenge.

I would not respond by leaning on reps to be conservative, which
mostly teaches people to sandbag. Give Commit observable exit
criteria instead: order form with the buyer, procurement engaged,
close date confirmed by someone who is not the rep. Until those
are enforced, haircut the submitted roll up by tenure, around
0.45 on Commit from reps under a year and 0.60 above that.

One honest note. The pattern is not monotonic: reps over two
years converted Commit at 57.9 percent, below the one to two year
band. I checked the two explanations I would expect, that the
tenured band is enterprise heavy and that it is contaminated by
reps who later left. Neither holds: segment mix is within half a
point across all three bands, and only three of 152 tenured
Commit deals belonged to someone who later departed. At that
sample size the gap sits inside normal rep to rep variation, so
it is not a finding until somebody pulls the per rep cut.

## 4. Nineteen percent are at quota, and any replacement is three quarters away.

Query 11 is why I do not report an average. Mean attainment is
61.7 percent and the median 68.8, but the distribution is
barbelled: four reps of 21 cleared 100 percent, nine sit in the
50 to 79 band and produce 56.7 percent of all revenue, six are
under 25 percent, and the 80 to 99 band is empty. Nobody is near
the number.

Stack that against query 02. New hires close essentially nothing
in their first two quarters: zero attainment through month three,
under 2 percent at months four to six for three of the four
cohorts, and 17 to 61 percent at months seven to twelve. Full
contribution arrives after month thirteen.

Now add the attrition: 8 of 25 reps have a termination date. A
team losing a third of its sellers, where the replacement takes
three quarters to contribute and a fifth of the survivors are at
quota, does not have a problem it can coach its way out of. It
has a capacity plan running structurally behind, and hiring needs
to lead the gap by two quarters rather than react to it.

The timing piece is softer. Q3 hires created 1.27 opportunities
per rep month in their first quarter against 1.8, 1.67 and 2.21
for Q1, Q2 and Q4, and stayed lowest through month six. That fits
onboarding through the summer and then competing for a manager's
attention in Q4. It is also five reps per cohort, which is not
enough to move a hiring calendar. Watch the next two cohorts on
the leading indicator rather than on revenue, and shift Q3 starts
to early Q2 if it holds.

---

## What I would fix before trusting any of the above

Query 12, first, always. Around 5 percent of opportunities carry
no amount, so every revenue figure above is understated by
whatever those were worth. Thirty deals close before they were
created, enough to poison a naive cycle time. Twenty seven
records have `is_won` disagreeing with `stage`, so the win rate
depends on which column the report was written against.

None of that stops the analysis. It does mean every query here
had to take an explicit position on the broken rows, which is
what the caveat block at the top of each file is for. The habit
worth having is not clean data, which nobody gets. It is a stated
position on the dirt.
