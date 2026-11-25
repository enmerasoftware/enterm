---
title: "Kata: a token bucket rate limiter in Python"
summary: "Race to build a token bucket and a per-key limiter with an injectable clock and bounded memory, verified by a fixed pytest suite."
kind: race
test: python3 -m pytest -q kata/token_bucket
programs: [claude, codex, gemini]
tags: [backend, testing]
author: enmerasoftware
title_tr: "Kata: Python ile token bucket hız sınırlayıcı"
summary_tr: "Saati dışarıdan verilebilen ve belleği sınırlı, anahtar başına çalışan bir token bucket hız sınırlayıcıyı sabit bir pytest paketiyle doğrulanacak şekilde yazma yarışı."
---
Build a token bucket rate limiter as a standalone Python module. This task is self-contained: it works in any git repository, an empty one included, and needs Python 3.9 or later with pytest. If `python3 -m pytest` does not work, use a virtual environment for yourself, but do not install anything globally.

Create `kata/token_bucket/token_bucket.py` (and no `__init__.py`), using only the standard library:

- `TokenBucket(capacity, refill_per_second, clock=time.monotonic)`. Both numbers must be positive, otherwise raise `ValueError`. The bucket starts full, refills continuously at `refill_per_second` tokens per second up to `capacity`, and reads time only through `clock()`. If the clock goes backwards, no tokens are added or removed, and refilling resumes from the new reading.
  - `available()` returns the current number of tokens as a float.
  - `try_acquire(tokens=1)` takes the tokens and returns `True` if they are all there, otherwise takes nothing and returns `False`.
  - `wait_time(tokens=1)` returns how many seconds until `try_acquire(tokens)` would succeed, `0` if it would now.
  - Asking for `tokens` below 1 or above `capacity` raises `ValueError` in both methods, since it can never succeed.
  - Avoid floating point surprises: after exactly enough refill time, the acquire must succeed.
- `KeyedLimiter(capacity, refill_per_second, clock=time.monotonic, max_keys=10000)` keeps one bucket per key.
  - `try_acquire(key, tokens=1)` works like the bucket's method, creating a full bucket for a new key.
  - `len(limiter)` is the number of buckets held.
  - Memory is bounded: when adding a new key would exceed `max_keys`, drop buckets that are full again (they are the same as new ones), oldest use first. Never drop a bucket that is not full, since that would hand out extra tokens; in that case it may go over `max_keys`.

Create `kata/token_bucket/test_acceptance.py` with exactly the content below and do not change it. You may add more tests in other files in the same folder, for example `kata/token_bucket/test_extra.py`.

```python
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from token_bucket import KeyedLimiter, TokenBucket  # noqa: E402


class FakeClock:
    def __init__(self, t=1000.0):
        self.t = t

    def __call__(self):
        return self.t

    def advance(self, seconds):
        self.t += seconds


@pytest.mark.parametrize("capacity,rate", [(0, 1), (-1, 1), (1, 0), (1, -2)])
def test_rejects_bad_arguments(capacity, rate):
    with pytest.raises(ValueError):
        TokenBucket(capacity=capacity, refill_per_second=rate)


def test_starts_full_and_spends_tokens():
    clock = FakeClock()
    b = TokenBucket(capacity=3, refill_per_second=1, clock=clock)
    assert b.available() == pytest.approx(3)
    assert [b.try_acquire() for _ in range(4)] == [True, True, True, False]
    assert b.available() == pytest.approx(0)


def test_refills_over_time_up_to_capacity():
    clock = FakeClock()
    b = TokenBucket(capacity=2, refill_per_second=4, clock=clock)
    assert b.try_acquire(2)
    clock.advance(0.25)
    assert b.available() == pytest.approx(1)
    clock.advance(10)
    assert b.available() == pytest.approx(2)


def test_acquiring_several_tokens_is_all_or_nothing():
    clock = FakeClock()
    b = TokenBucket(capacity=5, refill_per_second=1, clock=clock)
    assert b.try_acquire(4)
    assert not b.try_acquire(2)
    assert b.available() == pytest.approx(1)


def test_fractional_refill_accumulates():
    clock = FakeClock()
    b = TokenBucket(capacity=1, refill_per_second=0.5, clock=clock)
    assert b.try_acquire()
    for _ in range(3):
        clock.advance(0.5)
        assert not b.try_acquire()
    clock.advance(0.5)
    assert b.try_acquire()


def test_wait_time():
    clock = FakeClock()
    b = TokenBucket(capacity=4, refill_per_second=2, clock=clock)
    assert b.wait_time(1) == 0
    assert b.try_acquire(4)
    assert b.wait_time(1) == pytest.approx(0.5)
    assert b.wait_time(3) == pytest.approx(1.5)
    clock.advance(0.5)
    assert b.wait_time(1) == pytest.approx(0)


def test_more_than_capacity_is_an_error_not_a_wait():
    b = TokenBucket(capacity=2, refill_per_second=1, clock=FakeClock())
    with pytest.raises(ValueError):
        b.try_acquire(3)
    with pytest.raises(ValueError):
        b.wait_time(3)
    with pytest.raises(ValueError):
        b.try_acquire(0)


def test_clock_going_backwards_does_not_add_or_remove_tokens():
    clock = FakeClock()
    b = TokenBucket(capacity=2, refill_per_second=1, clock=clock)
    b.try_acquire(2)
    clock.advance(-100)
    assert b.available() == pytest.approx(0)
    clock.advance(1)
    assert b.available() == pytest.approx(1)


def test_keyed_limiter_keeps_one_bucket_per_key():
    clock = FakeClock()
    limiter = KeyedLimiter(capacity=1, refill_per_second=1, clock=clock)
    assert limiter.try_acquire("alice")
    assert not limiter.try_acquire("alice")
    assert limiter.try_acquire("bob")
    clock.advance(1)
    assert limiter.try_acquire("alice")


def test_keyed_limiter_forgets_full_idle_buckets():
    clock = FakeClock()
    limiter = KeyedLimiter(capacity=2, refill_per_second=1, clock=clock, max_keys=100)
    for i in range(1000):
        limiter.try_acquire(f"user-{i}")
        clock.advance(0.02)
    assert len(limiter) <= 100
    clock.advance(10)
    limiter.try_acquire("late")
    assert len(limiter) <= 100


def test_keyed_limiter_never_forgets_a_bucket_that_is_not_full():
    clock = FakeClock()
    limiter = KeyedLimiter(capacity=2, refill_per_second=0.001, clock=clock, max_keys=2)
    assert limiter.try_acquire("a", 2)
    assert limiter.try_acquire("b")
    assert limiter.try_acquire("c")
    assert not limiter.try_acquire("a")
```

Done means `python3 -m pytest -q kata/token_bucket` passes. Run it, and include the output in your final message together with how you handled floating point and memory. Then commit your work as the instructions below say.
