/// Runtime state of the auto-clicker.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum RunState {
    #[default]
    Ready,
    Starting,
    Clicking,
    Stopped,
    Error,
    Closing,
}

/// State machine for managing auto-clicker lifecycle transitions.
///
/// Ensures valid state transitions and prevents race conditions.
#[derive(Debug, Default)]
pub struct StateMachine {
    state: RunState,
}

impl StateMachine {
    /// Returns the current state.
    pub const fn state(&self) -> RunState {
        self.state
    }

    /// Attempts to transition to the Starting state.
    ///
    /// Returns true if the transition was allowed, false otherwise.
    pub fn request_start(&mut self) -> bool {
        match self.state {
            RunState::Ready | RunState::Stopped | RunState::Error => {
                self.state = RunState::Starting;
                true
            }
            RunState::Starting | RunState::Clicking | RunState::Closing => false,
        }
    }

    /// Transitions from Starting to Clicking state.
    ///
    /// Returns true if the state was Starting, false otherwise.
    pub fn started(&mut self) -> bool {
        if self.state == RunState::Starting {
            self.state = RunState::Clicking;
            true
        } else {
            false
        }
    }

    /// Attempts to stop the auto-clicker.
    ///
    /// Returns true if the transition to Stopped was allowed, false otherwise.
    pub fn stop(&mut self) -> bool {
        match self.state {
            RunState::Starting | RunState::Clicking => {
                self.state = RunState::Stopped;
                true
            }
            RunState::Ready | RunState::Stopped | RunState::Error | RunState::Closing => false,
        }
    }

    /// Transitions to the Error state.
    ///
    /// Does nothing if already in the Closing state.
    pub fn fail(&mut self) {
        if self.state != RunState::Closing {
            self.state = RunState::Error;
        }
    }

    /// Transitions to the terminal Closing state.
    pub fn close(&mut self) {
        self.state = RunState::Closing;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prevents_double_start() {
        let mut machine = StateMachine::default();
        assert!(machine.request_start());
        assert!(!machine.request_start());
        assert!(machine.started());
        assert!(!machine.request_start());
    }

    #[test]
    fn stops_while_active() {
        let mut machine = StateMachine::default();
        assert!(machine.request_start());
        assert!(machine.started());
        assert!(machine.stop());
        assert_eq!(machine.state(), RunState::Stopped);
    }

    #[test]
    fn stops_while_starting() {
        let mut machine = StateMachine::default();
        assert!(machine.request_start());
        assert!(machine.stop());
        assert_eq!(machine.state(), RunState::Stopped);
        assert!(!machine.started());
    }

    #[test]
    fn close_is_terminal() {
        let mut machine = StateMachine::default();
        assert!(machine.request_start());
        machine.close();
        assert_eq!(machine.state(), RunState::Closing);
        assert!(!machine.request_start());
        assert!(!machine.stop());
    }
}
