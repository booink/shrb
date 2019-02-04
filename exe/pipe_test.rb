#!/usr/bin/env ruby


r, w = IO.pipe

pid = Process.fork do
  STDOUT.reopen w
  Process.exec 'echo', *['aaa']
end
Process.waitpid(pid)

STDIN.reopen r
Process.exec 'grep', *['vvv']
r.close
