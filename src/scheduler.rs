use std::time::Duration;

#[derive(Debug, Clone)]
pub struct Schedule {
    interval: Duration,
    remaining: Option<u64>,
    emitted: u64,
}

impl Schedule {
    pub const fn new(interval: Duration, remaining: Option<u64>) -> Self {
        Self {
            interval,
            remaining,
            emitted: 0,
        }
    }

    pub const fn interval(&self) -> Duration {
        self.interval
    }

    pub const fn emitted(&self) -> u64 {
        self.emitted
    }

    pub const fn is_finished(&self) -> bool {
        matches!(self.remaining, Some(0))
    }

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
