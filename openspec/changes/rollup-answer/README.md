# Rollup answer

This change wires the approved `answered_pending` contract into Mission Control. It is branch-only and hermetic: implementation and verification use temporary Mission Control homes and chat-graph stores, with no install, deployment, provider send, or live-store write.

The OpenSpec artifacts are the canonical design and executable plan. `hotl-workflow-rollup-answer.md` is the step-level execution binding.
