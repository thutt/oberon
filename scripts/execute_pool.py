#!/usr/bin/python3
# Copyright (c) 2026 Logic Magicians Software
#
"""Bounded-concurrency task runner.

A fixed pool of worker threads pulls callables off a queue and runs
them.  Submit as many tasks as you like, whenever they become
available; at most 'max_workers' run at once, no matter how long the
stream of submissions continues.  Each task's result or exception is
captured in an Outcome and handed to an optional per-task callback,
so a failure in one task never silently kills its worker thread or
the rest of the run -- the caller decides what to do about it.
"""
import queue
import threading
from dataclasses import dataclass, field
from typing import Any, Callable, Optional, Tuple


@dataclass
class Outcome:
    fn: Callable
    args: Tuple
    kwargs: dict
    result: Any = None
    exception: Optional[BaseException] = None

    @property
    def ok(self):
        return self.exception is None


class ExecutePool:
    def __init__(self, max_workers=4):
        self._q = queue.Queue()
        self._workers = [
            threading.Thread(target=self._worker, daemon=True)
            for _ in range(max_workers)
        ]
        for w in self._workers:
            w.start()

    def submit(self, fn, *args, callback=None, **kwargs):
        """Queue 'fn(*args, **kwargs)' to run as soon as a worker is
        free.  'callback', if given, is invoked with the Outcome
        from a worker thread -- keep it fast and thread-safe.
        """
        self._q.put((fn, args, kwargs, callback))

    def _worker(self):
        while True:
            item = self._q.get()
            try:
                if item is None:              # Shutdown sentinel.
                    return
                fn, args, kwargs, callback = item
                outcome = Outcome(fn, args, kwargs)
                try:
                    outcome.result = fn(*args, **kwargs)
                except BaseException as e:    # noqa: BLE001 -- reported
                    outcome.exception = e     # to the caller, not lost.
                if callback is not None:
                    callback(outcome)
            finally:
                self._q.task_done()

    def join(self):
        """Block until every task submitted so far has completed.
        Safe to call, then submit() more, then join() again.
        """
        self._q.join()

    def shutdown(self):
        """Stop all worker threads once the queue drains.  Call
        join() first if you need to know outstanding work is done.
        """
        for _ in self._workers:
            self._q.put(None)
        for w in self._workers:
            w.join()
