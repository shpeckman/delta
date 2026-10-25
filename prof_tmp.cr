require "benchmark"
require "./src/delta"
rnd = Random.new(77)
base = (1..50_000).map { |i| "line #{i % 5000}" }
changed = base.map { |line| rnd.rand < 0.05 ? "changed #{line}" : line }
old = base.join("\n") + "\n"
new = changed.join("\n") + "\n"
t = Benchmark.memory { Delta.unified_diff(old, new) }
puts "unified_diff alloc: #{t}"
t2 = Benchmark.realtime { Delta.unified_diff(old, new) }
puts "unified_diff time: #{t2.total_milliseconds.round(2)}ms"
