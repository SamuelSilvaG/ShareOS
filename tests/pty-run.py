#!/usr/bin/env python3
"""Run a full-screen terminal program in a pseudo terminal, send keys, print what it drew.

    tests/pty-run.py <seconds> <keys> <command …>

Waits until the program has drawn something (or <seconds>/2), sends <keys>,
and kills it after <seconds>. Escape sequences are removed from the output."""
import os, pty, re, select, signal, sys, time

secs, keys, cmd = float(sys.argv[1]), sys.argv[2], sys.argv[3:]
pid, fd = pty.fork()
if pid == 0:
    os.environ['TERM'] = 'xterm-256color'
    os.execvp(cmd[0], cmd)
os.set_blocking(fd, False)
out, t0, sent = b'', time.time(), False
while time.time() - t0 < secs:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try:
            d = os.read(fd, 65536)
        except OSError:
            break
        if not d: break
        out += d
    if not sent and (len(out) > 2000 or time.time() - t0 > secs / 2):
        time.sleep(1); os.write(fd, keys.encode()); sent = True
    if os.waitpid(pid, os.WNOHANG)[0]: break
else:
    os.kill(pid, signal.SIGKILL)
text = re.sub(rb'\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b[()][0-9A-Za-z]|\x1b[=>78]|\x1b\][^\x07]*\x07', b'', out)
sys.stdout.write(text.decode('utf-8', 'replace'))
