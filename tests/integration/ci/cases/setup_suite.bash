# shellcheck shell=bash
# Once per run, around every test: prepare the repos, then clean them up.

setup_suite() {
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/lifecycle.sh"
  lifecycle__setup_suite
}

teardown_suite() {
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/lifecycle.sh"
  lifecycle__teardown_suite
}
