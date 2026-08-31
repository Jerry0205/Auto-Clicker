use std::time::Duration;

/// Click scheduling state tracker.
///
/// Tracks the interval between clicks and the remaining count for finite sequences.
#[derive(Debug, Clone)]
pub struct Schedule {
    interval: Duration,
    remaining: Option<u64>,
    emitted: u64,
}

impl Schedule {
    /// Creates a new schedule with the given interval and optional repeat count.
    ///
    /// If `remaining` is None, the schedule runs indefinitely until manually stopped.
    pub const fn new(interval: Duration, remaining: Option<u64>) -> Self {
        Self {
            interval,
            remaining,
            emitted: 0,
        }
    }

    /// Returns the interval duration between clicks.
    pub const fn interval(&self) -> Duration {
        self.interval
    }

    /// Returns the total number of clicks emitted so far.
    pub const fn emitted(&self) -> u64 {
        self.emitted
    }

    /// Returns whether the schedule has completed (for finite sequences).
    pub const fn is_finished(&self) -> bool {
        matches!(self.remaining, Some(0))
    }

    /// Records one click tick, updating counters.
    ///
    /// Returns true if the click should proceed, false if the schedule is finished.
    pub fn record_tick(&mut self) -> bool {
        if self.is_finished() {
            return false;
        }
        self.emitted = self.emitted.saturating_add(1);
        if let Some(remaining) = &mut self.remaining {
            *remaining = remaining.saturating_sub(1);
        }
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn repeat_counter_stops_exactly() {
        let mut schedule = Schedule::new(Duration::from_millis(100), Some(3));
        assert!(schedule.record_tick());
        assert!(schedule.record_tick());
        assert!(schedule.record_tick());
        assert!(!schedule.record_tick());
        assert_eq!(schedule.emitted(), 3);
    }

    #[test]
    fn ten_minute_simulation_has_constant_state() {
        for cps in [1_u64, 10, 50, 100] {
            let interval = Duration::from_millis(1_000 / cps);
            let expected = 600 * cps;
            let mut schedule = Schedule::new(interval, Some(expected));
            for _ in 0..expected {
                assert!(schedule.record_tick());
            }
            assert!(schedule.is_finished());
            assert_eq!(schedule.emitted(), expected);
            assert_eq!(
                std::mem::size_of_val(&schedule),
                std::mem::size_of::<Schedule>()
            );
        }
    }
}
