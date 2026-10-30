# shellcheck shell=bash
# The app's log as the test runs see it. Sourced by e2e.sh and perf.sh after they set LOG.
# log_lines_before and log_first_before are set by the script when its run starts.
# shellcheck disable=SC2154
# The log is the person's own: a run notes where it ended (log_lines_before) and its first line
# (log_first_before), reads only the lines after that, and never deletes the file.
log_line_count() { { wc -l < "$LOG"; } 2>/dev/null || echo 0; }
log_first_line() { head -n 1 "$LOG" 2>/dev/null || true; }

# True when the app started the file over (past 2 MB) since the run began: it is shorter than it
# was, or its first line is another one.
log_started_over() {
    if [ "$(log_line_count)" -lt "$log_lines_before" ]; then
        return 0
    fi
    if [ "$log_lines_before" -gt 0 ] && [ "$(log_first_line)" != "$log_first_before" ]; then
        return 0
    fi
    return 1
}

# The lines this run wrote. If the log started over, the lines before that are gone: this says so
# on stderr and adds an ERROR line, so the "no errors in the log" check fails instead of a negative
# check passing on half a log; then it gives the whole file.
run_log() {
    if log_started_over; then
        echo "The app started its log over during this run (past 2 MB): lines written before that are lost. Run the tests again." >&2
        echo "ERROR test run: the log started over during the run, its first lines are lost"
        cat "$LOG"
        return
    fi
    tail -n +"$((log_lines_before + 1))" "$LOG"
}
