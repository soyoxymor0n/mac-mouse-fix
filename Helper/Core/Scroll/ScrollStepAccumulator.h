//
// --------------------------------------------------------------------------
// ScrollStepAccumulator.h
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

#ifndef ScrollStepAccumulator_h
#define ScrollStepAccumulator_h

#include <stdint.h>

/// Turns a stream of scroll ticks into discrete steps. Used by the volume and brightness scroll effects (See Scroll.m).
///     Pure C without dependencies, so it can be unit tested on its own.
///     Notches are the scroll amount in lines. A classic wheel sends about 1.0 per notch. High-res wheels send many fractions of a notch.

typedef struct {
    double residual;    /// Notches that haven't turned into a step yet. Its sign is the direction of the last tick.
    double lastTickTS;  /// Timestamp of the last tick that added to `residual`.
} MFScrollStepAccumulator;

/// Adds one tick to `acc` and returns the number of steps to send for it.
///     - notches:     Signed amount of this tick. Positive is up, negative is down. Zero and NaN are ignored.
///     - timestamp:   Time of the tick in seconds. Must not go backwards.
///     - stepSize:    Notches per step. Use 1.0 for one step per notch. Must be positive.
///     - idleTimeout: If this much time passes without a tick, the leftover `residual` is dropped.
///
///     Returns: Positive for steps up, negative for steps down, zero if no step is due.
///
///     A direction reversal also drops the `residual`. So the first notch in the new direction counts fully.
///     A `residual` that is only float error is dropped. Ten ticks of 0.1 should make exactly one step.

static inline int64_t MFScrollStepAccumulatorAddTick(MFScrollStepAccumulator *acc, double notches, double timestamp, double stepSize, double idleTimeout) {

    /// Ignore empty ticks. `!(x > 0 || x < 0)` is also true for NaN.
    if (!(notches > 0 || notches < 0)) return 0;

    /// Drop leftovers after a pause
    if (acc->residual != 0 && timestamp - acc->lastTickTS > idleTimeout) {
        acc->residual = 0;
    }

    /// Drop leftovers when the direction reverses
    if (acc->residual != 0 && ((notches > 0) != (acc->residual > 0))) {
        acc->residual = 0;
    }

    /// Accumulate
    acc->residual += notches;
    acc->lastTickTS = timestamp;

    /// Turn whole steps into output
    ///     Truncating toward zero keeps the sign. The 1e-9 tolerance stops float error from holding back a step.
    double units = acc->residual / stepSize;
    int64_t steps = (int64_t)(units + (units > 0 ? 1e-9 : -1e-9));
    acc->residual -= (double)steps * stepSize;

    /// Clean up float dust
    if (acc->residual < 1e-9 && acc->residual > -1e-9) {
        acc->residual = 0;
    }

    return steps;
}

#endif /* ScrollStepAccumulator_h */
