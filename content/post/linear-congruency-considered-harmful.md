+++
title = "Linear Congruency Considered Harmful"
date = 2013-12-15T21:43:32
draft = false
math = true
tags = ["linear congruential generator", "monte carlo", "openmp", "random numbers"]
categories = []

# Featured image
# Place your image in the `static/img/` folder and reference its filename below, e.g. `image = "example.jpg"`.
[header]
image = ""
caption = ""
+++

Recently I stumbled upon [this Stack Overflow question](http://stackoverflow.com/questions/20452420/correct-openmp-pragmas-for-pi-monte-carlo-in-c-with-not-thread-safe-random-numbe).
The question author was puzzled with why he doesn't see any improvement in the resultant value of $\pi$ approximated using a parallel implementation of the well-known Monte Carlo method when he increase the number of OpenMP threads.
His expectation was that, since the number of Monte Carlo trials that each thread performs was kept constant, adding more threads would increase linearly the sample size and therefore improve the precision of the approximation.
He did not observe such improvement and blamed it on possible data races although all proper locks were in place.
The question seems to be related to an assignment that he got at his university.
What strikes me is the part of the assignment, which requires that he should use a specific [linear congruential pseudo-random number generator](https://en.wikipedia.org/wiki/Linear_congruential_generator) (LCPRNG for short).
In his case a terrible LCPRNG.

An inherent problem with all algorithmic pseudo-random number generators is that they are deterministic and only mimic randomness since each new output is a well-defined function of the previous output(s) (thus the _pseudo-_ prefix).
The more previous outputs are related together, the better the "randomness" of the output sequence could be made.
Since the internal state can only be of a finite length, every now and then the generator function would map the current state to one of the previous ones.
At that point the generator starts repeating the same output sequence again and again.
The length of the unique part of the sequence is called the cycle length of the generator.
The longer the cycle length, the better the PRNG.

**Linear congruency is the worst method for generating pseudo-random numbers.**
The only reason it is still used is that it is extremely easy to be implemented, takes very small amount of memory, and it works acceptably well in some cases if the parameters are [chosen wisely](https://en.wikipedia.org/wiki/Linear_congruential_generator#Period_length).
It's just that Monte Carlo simulations are rarely that cases.
So what is the problem with LCPRNGs?
The problem is that their output depends solely on the previous one as the congruential relation is

$$p_{i+1} \equiv (A \cdot p_i + B)\,(mod\,C),$$

where $A$, $B$ and $C$ are constants.
If the initial state (the seed of the generator) is $p_0$, then the *i*-th output is the result of $i$ applications of the generator function $f$ to the initial state, $p_i = f^i(p_0)$.
When it happens that an output repeats the initial state, i.e., $p_N = p_0$ for some $N > 0$, the generator loops since

$$p_{N+i} = f^{N+i}(p_0) = f^i(f^N(p_0)) = f^i(p_N) = f^i(p_0) = p_i.$$

As is also true with the human society, short memory leads to history repeating itself in (relatively short) cycles.

The generator from the question uses $C = 741025$ and therefore it produces pseudo-random numbers in the range $[0, 741024]$.
For each test point two numbers are sampled consecutively from the output sequence, therefore a total of $C^2$ or about 550 billion points are possible.
Right?
Wrong!
The choice of parameters results in this particular LCPRNG having a cycles length of 49400, which is orders of magnitude worse than the otherwise considered bad ANSI C pseudo-random generator `rand()`.
Since the cycle length is even, once the sequence folds over, the same set of 24700 points is repeated over and over again.
The unique sequence covers $49400/C$ or about 6,7% of the output range (which is already quite small).

A central problem in Monte Carlo simulations is the so called ergodicity or the ability of the simulated system to pass through all possible states.
Because of the looping character of the LCPRNG and the very short cycle length, there are many states that remain unvisited and therefore the simulation exhibits really bad ergodicity.
Not only this, but the output space is partitioned into 16 ($\lceil C/49400\rceil$) disjoint sets and there are only 16 unique initial values (seeds) possible.
Therefore only 32 different sets of points can be drawn from that generator (why 32 and not 16 is left as an exercise to the reader).

How this relates to the bad approximation of $\pi$?
The method used in the question is a geometric approximation based on the idea that if a set of points $\{ P_i \}$ is drawn randomly and uniformly from $ [0, 1) \times [0, 1) $, the probability that such a point lies inside a unit circle centred at the origin of the coordinate system is $\frac{\pi}{4}$.
Therefore:

$$\pi \approx 4\frac{\sum_{i=1}^N \theta{}(P_i)}{N},$$

where $\theta{}(P_i)$ is an indicator function that has a value of 1 for all points $\{ P(x,y): x^2+y^2 \leq 1\}$ and 0 for all other points and $N$ is the number of trials.
Now, it is well known that the precision of the approximation is proportional to $1/\sqrt{N}$ and therefore more trials give better results.
The problem in this case is that due to the looping nature of the LCPRNG, the sum in the nominator is simply $m \times S_0$, where

<div>$$S_0 = \sum_{i=1}^{24700} \theta{}(P_i).$$</div>

For large $N$ we have $m \approx N/24700$ and therefore the approximation is stuck at the value of:

$$\tilde{\pi} = 4 \frac{\sum_{i=1}^{24700} \theta(P_i)}{24700}.$$

It doesn't matter if one samples 24700 points or if one samples 247000000 points.
The result is going to be the same and the precision in the latter case is not going to be 100 times better but rather exactly the same as in the former case with 9999 times the computational resources used in the former case now effectively wasted.

Adding more threads could improve the precision if:

 *  each thread has its own PRNG, i.e. the generator state is thread-private and not
    globally shared, and
 *  the seed in each thread is chosen carefully so not to reproduce some other thread's
    generator output.

It was already shown that there are at most 32 unique sets of points and therefore using only up to 32 threads makes sense with an expected 5,7-fold increase of the precision of the approximation (less than one decimal digit).

This leaves me scratching my head: was his docent grossly incompetent or did s/he deliberately give him an exercise with such a bad PRNG so that he could learn how easily beautiful Monte Carlo methods are spoiled by bad pseudo-random generators?

It should be noted that having a cyclic PRNG is not necessarily a bad thing.
Even if two different seed values result in the same unique sequence, they usually start the generator output at different positions in the sequence.
And if the sample size is small relative to the cycle length (or respectively the cycle length is huge relative to the sample size), it would appear as if two independent sequences are being sampled.
Not in this case though.

Some final words.
Never use linear congruential PRNGs for Monte Carlo simulations!
Ne-ver!
Use something like [Mersenne twister MT19937](https://en.wikipedia.org/wiki/Mersenne_twister) instead.
Also don't try to reinvent [RANDU](https://en.wikipedia.org/wiki/RANDU) with all its ill consequences to the simulation science.
Thank you!
